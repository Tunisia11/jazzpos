import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'inventory_service.dart';
import 'permission_guard.dart';

class ReceivedLineInput {
  final String variantId;
  final int quantityReceived;
  final int quantityDamaged;
  final int quantityRejected;
  final Money unitCost;

  const ReceivedLineInput({
    required this.variantId,
    required this.quantityReceived,
    this.quantityDamaged = 0,
    this.quantityRejected = 0,
    required this.unitCost,
  });

  int get sellableQuantity =>
      quantityReceived - quantityDamaged - quantityRejected;
}

class PurchaseService {
  final AppDatabase db;
  final InventoryService inventoryService;

  PurchaseService(this.db, this.inventoryService);

  /// Create a purchase order
  Future<String> createPurchaseOrder({
    required String supplierId,
    required List<({String variantId, int expectedQty, Money unitCost})> items,
    String? createdById,
    String? notes,
  }) async {
    if (createdById != null) {
      await PermissionGuard.requirePermission(
        db,
        createdById,
        AppPermissions.manageSuppliers,
      );
    }
    if (items.isEmpty) {
      throw const ValidationException('PO must have at least one line');
    }

    final poId = IdGenerator.uuid();
    final poNumber = IdGenerator.poNumber();
    final now = DateTime.now();

    final totalCost = items.fold(
      Money.zero,
      (sum, i) => sum + (i.unitCost * i.expectedQty),
    );

    await db.transaction(() async {
      await db
          .into(db.purchaseOrders)
          .insert(
            PurchaseOrdersCompanion.insert(
              id: poId,
              poNumber: poNumber,
              supplierId: supplierId,
              status: const Value('ORDERED'),
              totalCostMillimes: Value(totalCost.millimes),
              notes: Value(notes),
              createdAt: now,
              updatedAt: now,
            ),
          );

      for (final item in items) {
        final lineCost = item.unitCost * item.expectedQty;
        await db
            .into(db.purchaseOrderLines)
            .insert(
              PurchaseOrderLinesCompanion.insert(
                id: IdGenerator.uuid(),
                purchaseOrderId: poId,
                variantId: item.variantId,
                expectedQty: item.expectedQty,
                unitCostMillimes: item.unitCost.millimes,
                totalCostMillimes: lineCost.millimes,
              ),
            );
      }
    });

    PosLogger.instance.info(
      'Purchasing',
      'Created PO #$poNumber with ${items.length} items. Total: ${totalCost.format()}',
    );
    return poId;
  }

  /// Receive goods against a purchase order or direct supplier delivery
  Future<String> receiveGoods({
    String? purchaseOrderId,
    required String supplierId,
    String? invoiceReference,
    required String receivedById,
    required String storeId,
    required List<ReceivedLineInput> lines,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw const ValidationException('Cannot receive empty shipment');
    }

    final receivedVariantIds = <String>{};
    for (final line in lines) {
      if (!receivedVariantIds.add(line.variantId)) {
        throw const ValidationException(
          'Each variant may appear only once in a goods receipt.',
        );
      }
      if (line.quantityReceived <= 0) {
        throw const ValidationException(
          'Received quantity must be greater than zero',
        );
      }
      if (line.quantityDamaged < 0 || line.quantityRejected < 0) {
        throw const ValidationException(
          'Damaged or rejected quantities cannot be negative',
        );
      }
      if (line.quantityDamaged + line.quantityRejected >
          line.quantityReceived) {
        throw const ValidationException(
          'Damaged plus rejected quantities cannot exceed total received quantity',
        );
      }
      if (line.unitCost.isNegative) {
        throw const ValidationException('Purchase cost cannot be negative');
      }
    }

    final grId = IdGenerator.uuid();
    final grNumber = IdGenerator.goodsReceiptNumber();
    final now = DateTime.now();

    final shopFloor = await inventoryService.getDefaultLocation(storeId);
    final hasDamagedItems = lines.any((line) => line.quantityDamaged > 0);
    final damagedLocation = hasDamagedItems
        ? await inventoryService.getDamagedLocation(storeId)
        : null;

    await db.transaction(() async {
      await PermissionGuard.requirePermission(
        db,
        receivedById,
        AppPermissions.manageSuppliers,
      );
      if (invoiceReference != null && invoiceReference.trim().isNotEmpty) {
        final duplicateReceipt =
            await (db.select(db.goodsReceipts)..where(
                  (table) =>
                      table.supplierId.equals(supplierId) &
                      table.invoiceReference.equals(invoiceReference.trim()),
                ))
                .getSingleOrNull();
        if (duplicateReceipt != null) {
          throw const ValidationException(
            'This supplier invoice has already been received.',
          );
        }
      }
      if (purchaseOrderId != null) {
        final po = await (db.select(
          db.purchaseOrders,
        )..where((tbl) => tbl.id.equals(purchaseOrderId))).getSingleOrNull();
        if (po == null) {
          throw const ValidationException('Purchase order not found');
        }
        if (po.supplierId != supplierId) {
          throw const ValidationException(
            'The supplier does not match this purchase order.',
          );
        }
        if (po.status != 'ORDERED' && po.status != 'PARTIALLY_RECEIVED') {
          throw const ValidationException(
            'This purchase order cannot receive additional goods.',
          );
        }
        for (final line in lines) {
          final poLine =
              await (db.select(db.purchaseOrderLines)..where(
                    (tbl) =>
                        tbl.purchaseOrderId.equals(purchaseOrderId) &
                        tbl.variantId.equals(line.variantId),
                  ))
                  .getSingleOrNull();
          if (poLine == null) {
            throw ValidationException(
              'Variant ${line.variantId} is not part of this purchase order.',
            );
          }
          if (poLine.receivedQty + line.quantityReceived > poLine.expectedQty) {
            throw ValidationException(
              'Receiving ${line.quantityReceived} units would exceed the remaining quantity for this purchase order.',
            );
          }
        }
      }

      // 1. Insert Goods Receipt
      await db
          .into(db.goodsReceipts)
          .insert(
            GoodsReceiptsCompanion.insert(
              id: grId,
              grNumber: grNumber,
              purchaseOrderId: Value(purchaseOrderId),
              supplierId: supplierId,
              invoiceReference: Value(invoiceReference),
              receivedById: receivedById,
              notes: Value(notes),
              createdAt: now,
            ),
          );

      // 2. Process each line
      for (final line in lines) {
        await db
            .into(db.goodsReceiptLines)
            .insert(
              GoodsReceiptLinesCompanion.insert(
                id: IdGenerator.uuid(),
                goodsReceiptId: grId,
                variantId: line.variantId,
                quantityReceived: line.quantityReceived,
                quantityDamaged: Value(line.quantityDamaged),
                quantityRejected: Value(line.quantityRejected),
                unitCostMillimes: line.unitCost.millimes,
                locationId: shopFloor.id,
              ),
            );

        // Update purchase cost override on the variant
        await (db.update(
          db.productVariants,
        )..where((tbl) => tbl.id.equals(line.variantId))).write(
          ProductVariantsCompanion(
            costPriceOverrideMillimes: Value(line.unitCost.millimes),
            updatedAt: Value(now),
          ),
        );

        // Record stock movement for sellable quantity
        if (line.sellableQuantity > 0) {
          await inventoryService.recordMovement(
            variantId: line.variantId,
            movementType: AppConstants.movementPurchaseReceipt,
            quantityDelta: line.sellableQuantity,
            toLocationId: shopFloor.id,
            unitCostMillimes: line.unitCost.millimes,
            referenceId: grId,
            referenceType: 'PURCHASE_RECEIPT',
            actorId: receivedById,
            reason: 'Received goods GR #$grNumber',
          );
        }

        // Record stock movement for damaged items
        if (line.quantityDamaged > 0) {
          await inventoryService.recordMovement(
            variantId: line.variantId,
            movementType: AppConstants.movementDamage,
            quantityDelta: line.quantityDamaged,
            toLocationId: damagedLocation!.id,
            unitCostMillimes: line.unitCost.millimes,
            referenceId: grId,
            referenceType: 'PURCHASE_DAMAGED',
            actorId: receivedById,
            reason: 'Damaged on delivery GR #$grNumber',
          );
        }

        // If linked to PO, update PO line receivedQty
        if (purchaseOrderId != null) {
          final poLine =
              await (db.select(db.purchaseOrderLines)..where(
                    (tbl) =>
                        tbl.purchaseOrderId.equals(purchaseOrderId) &
                        tbl.variantId.equals(line.variantId),
                  ))
                  .getSingleOrNull();

          if (poLine != null) {
            await (db.update(
              db.purchaseOrderLines,
            )..where((tbl) => tbl.id.equals(poLine.id))).write(
              PurchaseOrderLinesCompanion(
                receivedQty: Value(poLine.receivedQty + line.quantityReceived),
              ),
            );
          }
        }
      }

      // 3. Update PO status if completed
      if (purchaseOrderId != null) {
        final poLines = await (db.select(
          db.purchaseOrderLines,
        )..where((tbl) => tbl.purchaseOrderId.equals(purchaseOrderId))).get();
        final allReceived = poLines.every(
          (l) => l.receivedQty >= l.expectedQty,
        );
        await (db.update(
          db.purchaseOrders,
        )..where((tbl) => tbl.id.equals(purchaseOrderId))).write(
          PurchaseOrdersCompanion(
            status: Value(allReceived ? 'RECEIVED' : 'PARTIALLY_RECEIVED'),
            updatedAt: Value(now),
          ),
        );
      }

      // 4. Audit entry
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'GOODS_RECEIVED',
              entityType: 'PURCHASE',
              entityId: Value(grId),
              userId: receivedById,
              detailsJson: Value(
                '{"grNumber":"$grNumber","linesCount":${lines.length}}',
              ),
              createdAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'Purchasing',
      'Goods receipt #$grNumber completed for ${lines.length} lines',
    );
    return grId;
  }
}
