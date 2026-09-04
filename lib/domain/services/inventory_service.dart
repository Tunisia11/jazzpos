import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';

class InventoryService {
  final AppDatabase db;

  InventoryService(this.db);

  /// Get current available stock for a variant (optionally filtered by location)
  Future<int> getStock(String variantId, {String? locationId}) async {
    final query = db.select(db.stockLevels)..where((tbl) => tbl.variantId.equals(variantId));
    if (locationId != null) {
      query.where((tbl) => tbl.locationId.equals(locationId));
    }
    final results = await query.get();
    return results.fold<int>(0, (sum, lvl) => sum + (lvl.quantity - lvl.reservedQuantity));
  }

  /// Get physical stock level across all locations
  Future<int> getPhysicalStock(String variantId) async {
    final query = db.select(db.stockLevels)..where((tbl) => tbl.variantId.equals(variantId));
    final results = await query.get();
    return results.fold<int>(0, (sum, lvl) => sum + lvl.quantity);
  }

  /// Get the default location (e.g. Shop Floor) for a store
  Future<StockLocation> getDefaultLocation(String storeId) async {
    final loc = await (db.select(db.stockLocations)
          ..where((tbl) => tbl.storeId.equals(storeId) & tbl.isDefault.equals(true)))
        .getSingleOrNull();

    if (loc != null) return loc;

    final fallback = await (db.select(db.stockLocations)..where((tbl) => tbl.storeId.equals(storeId)))
        .getSingleOrNull();

    if (fallback != null) return fallback;

    // Create default Shop Floor if none exists
    final newId = IdGenerator.uuid();
    await db.into(db.stockLocations).insert(
          StockLocationsCompanion.insert(
            id: newId,
            storeId: storeId,
            name: 'Shop Floor',
            code: 'SHOP',
            locationType: AppConstants.locationShopFloor,
            isDefault: const Value(true),
          ),
        );
    return await (db.select(db.stockLocations)..where((tbl) => tbl.id.equals(newId))).getSingle();
  }

  /// Validate if stock is sufficient according to store negative stock policy
  Future<void> validateStockAvailability({
    required String variantId,
    required int requestedQuantity,
    required String policy, // BLOCK, WARN, MANAGER_OVERRIDE
    String? managerOverrideId,
    String? locationId,
  }) async {
    final currentStock = await getStock(variantId, locationId: locationId);
    if (currentStock >= requestedQuantity) return;

    // Physical stock is insufficient
    PosLogger.instance.warning(
      'Inventory',
      'Stock alert: variant $variantId requested $requestedQuantity but only $currentStock available (policy: $policy)',
    );

    if (policy == AppConstants.negativeStockBlock) {
      throw InsufficientStockException(
        variantId: variantId,
        availableStock: currentStock,
        requestedQuantity: requestedQuantity,
        message: 'Insufficient physical stock: $currentStock available, $requestedQuantity requested.',
      );
    } else if (policy == AppConstants.negativeStockOverride) {
      if (managerOverrideId == null || managerOverrideId.isEmpty) {
        throw InsufficientStockException(
          variantId: variantId,
          availableStock: currentStock,
          requestedQuantity: requestedQuantity,
          message: 'Manager override required to sell below zero stock.',
        );
      }
    }
    // WARN policy allows sale to proceed with warning logged
  }

  /// Record an atomic stock movement and update cached stock levels
  Future<void> recordMovement({
    required String variantId,
    required String movementType,
    required int quantityDelta, // positive for addition, negative for reduction
    String? fromLocationId,
    String? toLocationId,
    int unitCostMillimes = 0,
    String? referenceId,
    String? referenceType,
    String? actorId,
    String? reason,
  }) async {
    final movementId = IdGenerator.uuid();
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Insert immutable audit movement
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              id: movementId,
              variantId: variantId,
              movementType: movementType,
              quantityDelta: quantityDelta,
              fromLocationId: Value(fromLocationId),
              toLocationId: Value(toLocationId),
              unitCostMillimes: Value(unitCostMillimes),
              referenceId: Value(referenceId),
              referenceType: Value(referenceType),
              actorId: Value(actorId),
              reason: Value(reason),
              createdAt: now,
            ),
          );

      // 2. Update cached stock levels for fromLocation
      if (fromLocationId != null) {
        final existingFrom = await (db.select(db.stockLevels)
              ..where((tbl) => tbl.variantId.equals(variantId) & tbl.locationId.equals(fromLocationId)))
            .getSingleOrNull();

        if (existingFrom != null) {
          await (db.update(db.stockLevels)..where((tbl) => tbl.id.equals(existingFrom.id))).write(
            StockLevelsCompanion(
              quantity: Value(existingFrom.quantity - quantityDelta.abs()),
              updatedAt: Value(now),
            ),
          );
        } else {
          await db.into(db.stockLevels).insert(
                StockLevelsCompanion.insert(
                  id: IdGenerator.uuid(),
                  variantId: variantId,
                  locationId: fromLocationId,
                  quantity: Value(-quantityDelta.abs()),
                  updatedAt: now,
                ),
              );
        }
      }

      // 3. Update cached stock levels for toLocation
      if (toLocationId != null) {
        final existingTo = await (db.select(db.stockLevels)
              ..where((tbl) => tbl.variantId.equals(variantId) & tbl.locationId.equals(toLocationId)))
            .getSingleOrNull();

        if (existingTo != null) {
          await (db.update(db.stockLevels)..where((tbl) => tbl.id.equals(existingTo.id))).write(
            StockLevelsCompanion(
              quantity: Value(existingTo.quantity + quantityDelta.abs()),
              updatedAt: Value(now),
            ),
          );
        } else {
          await db.into(db.stockLevels).insert(
                StockLevelsCompanion.insert(
                  id: IdGenerator.uuid(),
                  variantId: variantId,
                  locationId: toLocationId,
                  quantity: Value(quantityDelta.abs()),
                  updatedAt: now,
                ),
              );
        }
      }
    });

    PosLogger.instance.info(
      'Inventory',
      'Stock movement: $movementType delta: $quantityDelta for variant $variantId',
    );
  }

  /// Transfer stock from one location to another (e.g. Back Room -> Shop Floor)
  Future<void> transferStock({
    required String variantId,
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
    required String actorId,
    String? reason,
  }) async {
    if (quantity <= 0) throw const ValidationException('Transfer quantity must be greater than zero');

    await recordMovement(
      variantId: variantId,
      movementType: AppConstants.movementTransferIn,
      quantityDelta: quantity,
      fromLocationId: fromLocationId,
      toLocationId: toLocationId,
      actorId: actorId,
      reason: reason ?? 'Stock transfer',
    );
  }

  /// Manual adjustment with authorized reason
  Future<void> adjustStock({
    required String variantId,
    required String locationId,
    required int newQuantity,
    required String actorId,
    required String reason,
    String? managerId,
  }) async {
    final current = await getStock(variantId, locationId: locationId);
    final delta = newQuantity - current;
    if (delta == 0) return;

    await recordMovement(
      variantId: variantId,
      movementType: AppConstants.movementManualAdjustment,
      quantityDelta: delta,
      fromLocationId: delta < 0 ? locationId : null,
      toLocationId: delta > 0 ? locationId : null,
      actorId: actorId,
      reason: reason,
    );

    // Record audit event
    await db.into(db.auditEvents).insert(
          AuditEventsCompanion.insert(
            id: IdGenerator.uuid(),
            action: 'STOCK_MANUAL_ADJUSTMENT',
            entityType: 'VARIANT',
            entityId: Value(variantId),
            userId: actorId,
            managerId: Value(managerId),
            detailsJson: Value('{"oldStock":$current,"newStock":$newQuantity,"delta":$delta,"reason":"$reason"}'),
            createdAt: DateTime.now(),
          ),
        );
  }
}
