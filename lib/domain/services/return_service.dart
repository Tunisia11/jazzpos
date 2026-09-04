import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'inventory_service.dart';

class ReturnLineItem {
  final String? originalSaleLineId;
  final String variantId;
  final int quantity;
  final Money refundUnitPrice;
  final String condition; // SELLABLE, DAMAGED

  const ReturnLineItem({
    this.originalSaleLineId,
    required this.variantId,
    required this.quantity,
    required this.refundUnitPrice,
    this.condition = AppConstants.returnConditionSellable,
  });

  Money get totalRefund => refundUnitPrice * quantity;
}

class ReturnRequest {
  final String? originalSaleId;
  final String storeId;
  final String registerId;
  final String shiftId;
  final String cashierId;
  final String reason;
  final String refundMethod; // CASH, CARD, STORE_CREDIT
  final List<ReturnLineItem> items;
  final String? managerId; // required for no-receipt or large returns

  const ReturnRequest({
    this.originalSaleId,
    required this.storeId,
    required this.registerId,
    required this.shiftId,
    required this.cashierId,
    required this.reason,
    required this.refundMethod,
    required this.items,
    this.managerId,
  });

  Money get totalRefund {
    return items.fold(Money.zero, (sum, i) => sum + i.totalRefund);
  }
}

class ReturnService {
  final AppDatabase db;
  final InventoryService inventoryService;

  ReturnService(this.db, this.inventoryService);

  /// Find a sale for return by receipt ticket number or ID
  Future<Sale?> findSaleForReturn(String query) async {
    final clean = query.trim();
    return (db.select(db.sales)
          ..where((tbl) => tbl.receiptNumber.equals(clean) | tbl.id.equals(clean))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get lines for an original sale
  Future<List<SaleLine>> getSaleLines(String saleId) async {
    return (db.select(db.saleLines)..where((tbl) => tbl.saleId.equals(saleId))).get();
  }

  /// Process return transaction atomically
  Future<Return> processReturn(ReturnRequest request) async {
    if (request.items.isEmpty) {
      throw const ValidationException('Cannot process return without items');
    }

    // If no receipt return, verify manager authorization
    if (request.originalSaleId == null) {
      final allowNoReceipt = await (db.select(db.appSettings)..where((tbl) => tbl.key.equals(AppConstants.keyAllowNoReceiptReturns))).getSingleOrNull();
      if (allowNoReceipt?.value == 'false') {
        throw const ValidationException('No-receipt returns are disabled in store settings');
      }
      if (request.managerId == null || request.managerId!.isEmpty) {
        throw const AuthException('Manager authorization is required for no-receipt returns');
      }
    }

    final returnId = IdGenerator.uuid();
    final returnNumber = IdGenerator.returnNumber();
    final now = DateTime.now();
    final totalRefund = request.totalRefund;

    // Get default shop floor and damaged locations
    final shopFloor = await inventoryService.getDefaultLocation(request.storeId);
    final damagedLocation = await (db.select(db.stockLocations)
          ..where((tbl) => tbl.storeId.equals(request.storeId) & tbl.locationType.equals(AppConstants.locationDamaged)))
        .getSingleOrNull();

    late Return committedReturn;

    await db.transaction(() async {
      // 1. Insert Return record
      await db.into(db.returns).insert(
            ReturnsCompanion.insert(
              id: returnId,
              returnNumber: returnNumber,
              originalSaleId: Value(request.originalSaleId),
              storeId: request.storeId,
              registerId: request.registerId,
              shiftId: request.shiftId,
              cashierId: request.cashierId,
              reason: request.reason,
              totalRefundMillimes: totalRefund.millimes,
              refundMethod: request.refundMethod,
              managerId: Value(request.managerId),
              createdAt: now,
            ),
          );

      // 2. Insert Return Lines and update stock movements
      for (final item in request.items) {
        final restockLocationId = (item.condition == AppConstants.returnConditionDamaged)
            ? (damagedLocation?.id ?? shopFloor.id)
            : shopFloor.id;

        await db.into(db.returnLines).insert(
              ReturnLinesCompanion.insert(
                id: IdGenerator.uuid(),
                returnId: returnId,
                originalSaleLineId: Value(item.originalSaleLineId),
                variantId: item.variantId,
                quantity: item.quantity,
                refundUnitPriceMillimes: item.refundUnitPrice.millimes,
                totalRefundMillimes: item.totalRefund.millimes,
                condition: Value(item.condition),
                restockedLocationId: Value(restockLocationId),
              ),
            );

        // Record stock movement (restocking only sellable into shop floor)
        await inventoryService.recordMovement(
          variantId: item.variantId,
          movementType: (item.condition == AppConstants.returnConditionDamaged)
              ? AppConstants.movementDamage
              : AppConstants.movementReturn,
          quantityDelta: item.quantity,
          toLocationId: restockLocationId,
          unitCostMillimes: 0,
          referenceId: returnId,
          referenceType: 'RETURN',
          actorId: request.cashierId,
          reason: 'Return #$returnNumber: ${request.reason} (${item.condition})',
        );
      }

      // 3. Update original sale status if fully returned
      if (request.originalSaleId != null) {
        await (db.update(db.sales)..where((tbl) => tbl.id.equals(request.originalSaleId!))).write(
          const SalesCompanion(
            status: Value(AppConstants.saleRefunded),
          ),
        );
      }

      // 4. Audit entry
      await db.into(db.auditEvents).insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'RETURN_PROCESSED',
              entityType: 'RETURN',
              entityId: Value(returnId),
              userId: request.cashierId,
              managerId: Value(request.managerId),
              detailsJson: Value('{"returnNumber":"$returnNumber","totalRefund":${totalRefund.millimes},"method":"${request.refundMethod}"}'),
              createdAt: now,
            ),
          );

      // 5. Outbox event
      await db.into(db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'RETURN',
              operation: 'INSERT',
              payloadJson: '{"id":"$returnId","returnNumber":"$returnNumber","totalRefund":${totalRefund.millimes}}',
              createdAt: now,
              updatedAt: now,
            ),
          );

      committedReturn = await (db.select(db.returns)..where((tbl) => tbl.id.equals(returnId))).getSingle();
    });

    PosLogger.instance.info('Returns', 'Return #$returnNumber completed: total refund $totalRefund');
    return committedReturn;
  }
}
