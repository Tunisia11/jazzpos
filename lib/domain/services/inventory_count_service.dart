import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'inventory_service.dart';
import 'permission_guard.dart';

class InventoryCountLineWithDetails {
  final InventoryCountLine line;
  final ProductVariant variant;
  final Product product;
  final String attributeDesc;

  const InventoryCountLineWithDetails({
    required this.line,
    required this.variant,
    required this.product,
    required this.attributeDesc,
  });
}

class InventoryCountService {
  final AppDatabase db;
  final InventoryService inventoryService;

  InventoryCountService(this.db, this.inventoryService);

  /// Initiate a new inventory audit count session
  Future<String> initiateCount({
    required String locationId,
    required String initiatedById,
    String scope = 'FULL',
    String? categoryId,
    String? brandId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      initiatedById,
      AppPermissions.manageInventory,
    );
    final countId = IdGenerator.uuid();
    final countNumber = IdGenerator.stockCountNumber();
    final now = DateTime.now();

    await db.transaction(() async {
      await db
          .into(db.inventoryCounts)
          .insert(
            InventoryCountsCompanion.insert(
              id: countId,
              countNumber: countNumber,
              locationId: locationId,
              status: const Value('IN_PROGRESS'),
              scope: Value(scope),
              initiatedById: initiatedById,
              createdAt: now,
            ),
          );

      // Snapshot all matching variants and their current expected stock
      final variants = await (db.select(
        db.productVariants,
      )..where((tbl) => tbl.isActive.equals(true))).get();

      for (final v in variants) {
        final currentStock = await inventoryService.getStock(
          v.id,
          locationId: locationId,
        );
        await db
            .into(db.inventoryCountLines)
            .insert(
              InventoryCountLinesCompanion.insert(
                id: IdGenerator.uuid(),
                inventoryCountId: countId,
                variantId: v.id,
                expectedQuantity: currentStock,
                countedQuantity: 0,
                differenceQuantity: -currentStock,
                unitCostMillimes: Value(v.costPriceOverrideMillimes ?? 0),
              ),
            );
      }
    });

    PosLogger.instance.info(
      'InventoryCount',
      'Initiated count #$countNumber for location $locationId',
    );
    return countId;
  }

  /// Record scanned barcode in count (increments countedQuantity by 1 or set quantity)
  Future<void> recordScannedVariant({
    required String countId,
    required String barcodeOrSku,
    int increment = 1,
  }) async {
    final clean = barcodeOrSku.trim();
    // Find variant
    final variant =
        await (db.select(db.productVariants)..where(
              (tbl) =>
                  tbl.barcode.equals(clean) |
                  tbl.sku.equals(clean.toUpperCase()),
            ))
            .getSingleOrNull();

    if (variant == null) {
      throw ValidationException(
        'No variant found with barcode or SKU "$clean"',
      );
    }

    final countLine =
        await (db.select(db.inventoryCountLines)..where(
              (tbl) =>
                  tbl.inventoryCountId.equals(countId) &
                  tbl.variantId.equals(variant.id),
            ))
            .getSingleOrNull();

    if (countLine == null) {
      // Add line to count
      final expected = await inventoryService.getStock(variant.id);
      final newCounted = increment;
      await db
          .into(db.inventoryCountLines)
          .insert(
            InventoryCountLinesCompanion.insert(
              id: IdGenerator.uuid(),
              inventoryCountId: countId,
              variantId: variant.id,
              expectedQuantity: expected,
              countedQuantity: newCounted,
              differenceQuantity: newCounted - expected,
              unitCostMillimes: Value(variant.costPriceOverrideMillimes ?? 0),
            ),
          );
    } else {
      final newCounted = countLine.countedQuantity + increment;
      final diff = newCounted - countLine.expectedQuantity;
      await (db.update(
        db.inventoryCountLines,
      )..where((tbl) => tbl.id.equals(countLine.id))).write(
        InventoryCountLinesCompanion(
          countedQuantity: Value(newCounted),
          differenceQuantity: Value(diff),
        ),
      );
    }
  }

  /// Get all lines for an active count
  Future<List<InventoryCountLineWithDetails>> getCountLines(
    String countId,
  ) async {
    final lines = await (db.select(
      db.inventoryCountLines,
    )..where((tbl) => tbl.inventoryCountId.equals(countId))).get();
    final results = <InventoryCountLineWithDetails>[];

    for (final l in lines) {
      final variant = await (db.select(
        db.productVariants,
      )..where((tbl) => tbl.id.equals(l.variantId))).getSingle();
      final product = await (db.select(
        db.products,
      )..where((tbl) => tbl.id.equals(variant.productId))).getSingle();
      results.add(
        InventoryCountLineWithDetails(
          line: l,
          variant: variant,
          product: product,
          attributeDesc: variant.sku,
        ),
      );
    }
    return results;
  }

  /// Commit and reconcile inventory differences with manager authorization
  Future<void> reconcileAndComplete({
    required String countId,
    required String managerId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      managerId,
      AppPermissions.manageInventory,
    );
    final count = await (db.select(
      db.inventoryCounts,
    )..where((tbl) => tbl.id.equals(countId))).getSingle();
    if (count.status == 'COMPLETED') {
      throw const ValidationException(
        'This inventory count is already reconciled and completed',
      );
    }

    final lines = await (db.select(
      db.inventoryCountLines,
    )..where((tbl) => tbl.inventoryCountId.equals(countId))).get();
    final now = DateTime.now();

    await db.transaction(() async {
      for (final line in lines) {
        if (line.differenceQuantity != 0) {
          await inventoryService.recordMovement(
            variantId: line.variantId,
            movementType: AppConstants.movementStockCount,
            quantityDelta: line.differenceQuantity,
            toLocationId: line.differenceQuantity > 0 ? count.locationId : null,
            fromLocationId: line.differenceQuantity < 0
                ? count.locationId
                : null,
            unitCostMillimes: line.unitCostMillimes,
            referenceId: countId,
            referenceType: 'STOCK_COUNT',
            actorId: managerId,
            reason:
                'Reconciled difference for Count #${count.countNumber}: ${line.differenceQuantity}',
          );
        }

        await (db.update(
          db.inventoryCountLines,
        )..where((tbl) => tbl.id.equals(line.id))).write(
          const InventoryCountLinesCompanion(isReconciled: Value(true)),
        );
      }

      await (db.update(
        db.inventoryCounts,
      )..where((tbl) => tbl.id.equals(countId))).write(
        InventoryCountsCompanion(
          status: const Value('COMPLETED'),
          approvedById: Value(managerId),
          approvedAt: Value(now),
        ),
      );

      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'INVENTORY_COUNT_RECONCILED',
              entityType: 'INVENTORY_COUNT',
              entityId: Value(countId),
              userId: managerId,
              managerId: Value(managerId),
              detailsJson: Value(
                '{"countNumber":"${count.countNumber}","reconciledLines":${lines.length}}',
              ),
              createdAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'InventoryCount',
      'Count #${count.countNumber} reconciled and closed by manager $managerId',
    );
  }
}
