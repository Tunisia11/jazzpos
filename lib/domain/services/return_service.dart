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

  void _validateItemsAgainstSale({
    required ReturnRequest request,
    required List<SaleLine> saleLines,
    required List<ReturnLine> priorReturnLines,
  }) {
    final saleLineMap = {for (final line in saleLines) line.id: line};
    final requestedQuantityByLine = <String, int>{};
    final requestedRefundByLine = <String, int>{};
    final requestedQuantityByVariant = <String, int>{};

    for (final item in request.items) {
      if (item.originalSaleLineId != null) {
        final line = saleLineMap[item.originalSaleLineId];
        if (line == null) {
          throw ValidationException(
            'Invalid original sale line ID: ${item.originalSaleLineId}',
          );
        }
        if (line.variantId != item.variantId) {
          throw const ValidationException(
            'Returned variant does not match the original receipt line.',
          );
        }
        requestedQuantityByLine.update(
          line.id,
          (quantity) => quantity + item.quantity,
          ifAbsent: () => item.quantity,
        );
        requestedRefundByLine.update(
          line.id,
          (amount) => amount + item.totalRefund.millimes,
          ifAbsent: () => item.totalRefund.millimes,
        );
      } else {
        requestedQuantityByVariant.update(
          item.variantId,
          (quantity) => quantity + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }

    for (final entry in requestedQuantityByLine.entries) {
      final line = saleLineMap[entry.key]!;
      final priorForLine = priorReturnLines.where(
        (returnLine) => returnLine.originalSaleLineId == line.id,
      );
      final alreadyReturned = priorForLine.fold<int>(
        0,
        (sum, returnLine) => sum + returnLine.quantity,
      );
      if (alreadyReturned + entry.value > line.quantity) {
        throw ValidationException(
          'Return quantity exceeds the quantity purchased for "${line.productName}".',
        );
      }
      final alreadyRefunded = priorForLine.fold<int>(
        0,
        (sum, returnLine) => sum + returnLine.totalRefundMillimes,
      );
      if (alreadyRefunded + requestedRefundByLine[entry.key]! >
          line.totalMillimes) {
        throw ValidationException(
          'Refund amount exceeds the amount paid for "${line.productName}".',
        );
      }
    }

    for (final entry in requestedQuantityByVariant.entries) {
      final sold = saleLines
          .where((line) => line.variantId == entry.key)
          .fold<int>(0, (sum, line) => sum + line.quantity);
      final returned = priorReturnLines
          .where((line) => line.variantId == entry.key)
          .fold<int>(0, (sum, line) => sum + line.quantity);
      if (sold == 0 || returned + entry.value > sold) {
        throw const ValidationException(
          'Return quantity exceeds the quantity purchased for this variant.',
        );
      }
    }
  }

  /// Find a sale for return by receipt ticket number or ID
  Future<Sale?> findSaleForReturn(String query) async {
    final clean = query.trim();
    return (db.select(db.sales)
          ..where(
            (tbl) => tbl.receiptNumber.equals(clean) | tbl.id.equals(clean),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get lines for an original sale
  Future<List<SaleLine>> getSaleLines(String saleId) async {
    return (db.select(
      db.saleLines,
    )..where((tbl) => tbl.saleId.equals(saleId))).get();
  }

  /// Process return transaction atomically
  Future<Return> processReturn(ReturnRequest request) async {
    if (request.items.isEmpty) {
      throw const ValidationException('Cannot process return without items');
    }

    for (final item in request.items) {
      if (item.quantity <= 0) {
        throw const ValidationException(
          'Return quantity must be greater than zero',
        );
      }
      if (item.refundUnitPrice.isNegative) {
        throw const ValidationException('Refund amount cannot be negative');
      }
      if (item.condition != AppConstants.returnConditionSellable &&
          item.condition != AppConstants.returnConditionDamaged) {
        throw const ValidationException('Invalid return item condition');
      }
    }
    if (request.totalRefund <= Money.zero) {
      throw const ValidationException('Refund total must be greater than zero');
    }
    if (request.reason.trim().isEmpty) {
      throw const ValidationException('A return reason is required');
    }

    // If returning against an original sale, strictly enforce return quantity invariants
    List<SaleLine> saleLines = [];
    List<ReturnLine> priorReturnLines = [];
    if (request.originalSaleId != null) {
      final sale =
          await (db.select(db.sales)
                ..where((tbl) => tbl.id.equals(request.originalSaleId!)))
              .getSingleOrNull();
      if (sale == null) {
        throw ValidationException(
          'Original sale not found: ${request.originalSaleId}',
        );
      }
      if (sale.status == AppConstants.saleRefunded) {
        throw const ValidationException(
          'This sale has already been completely refunded.',
        );
      }
      if (sale.status == AppConstants.saleVoided) {
        throw const ValidationException(
          'Cannot return items from a voided sale.',
        );
      }
      if (sale.storeId != request.storeId) {
        throw const ValidationException(
          'The receipt does not belong to the selected store.',
        );
      }

      saleLines = await (db.select(
        db.saleLines,
      )..where((tbl) => tbl.saleId.equals(request.originalSaleId!))).get();
      final priorReturns =
          await (db.select(db.returns)..where(
                (tbl) => tbl.originalSaleId.equals(request.originalSaleId!),
              ))
              .get();
      final priorReturnIds = priorReturns.map((r) => r.id).toList();
      priorReturnLines = priorReturnIds.isEmpty
          ? <ReturnLine>[]
          : await (db.select(
              db.returnLines,
            )..where((tbl) => tbl.returnId.isIn(priorReturnIds))).get();

      _validateItemsAgainstSale(
        request: request,
        saleLines: saleLines,
        priorReturnLines: priorReturnLines,
      );
    } else {
      // If no receipt return, verify manager authorization
      final allowNoReceipt =
          await (db.select(db.appSettings)..where(
                (tbl) => tbl.key.equals(AppConstants.keyAllowNoReceiptReturns),
              ))
              .getSingleOrNull();
      if (allowNoReceipt?.value == 'false') {
        throw const ValidationException(
          'No-receipt returns are disabled in store settings',
        );
      }
      if (request.managerId == null || request.managerId!.isEmpty) {
        throw const AuthException(
          'Manager authorization is required for no-receipt returns',
        );
      }
    }

    final returnId = IdGenerator.uuid();
    final returnNumber = IdGenerator.returnNumber();
    final now = DateTime.now();
    final totalRefund = request.totalRefund;

    // Get default shop floor and damaged locations
    final shopFloor = await inventoryService.getDefaultLocation(
      request.storeId,
    );
    final hasDamagedItems = request.items.any(
      (item) => item.condition == AppConstants.returnConditionDamaged,
    );
    final damagedLocation = hasDamagedItems
        ? await inventoryService.getDamagedLocation(request.storeId)
        : null;

    late Return committedReturn;

    await db.transaction(() async {
      await PermissionGuard.requirePermission(
        db,
        request.cashierId,
        AppPermissions.processReturn,
      );
      final activeShift = await (db.select(
        db.shifts,
      )..where((table) => table.id.equals(request.shiftId))).getSingleOrNull();
      if (activeShift == null ||
          activeShift.status != AppConstants.shiftOpen ||
          activeShift.registerId != request.registerId) {
        throw const ValidationException(
          'Returns require an open shift on the selected register.',
        );
      }

      if (request.originalSaleId != null) {
        final currentSale =
            await (db.select(db.sales)
                  ..where((table) => table.id.equals(request.originalSaleId!)))
                .getSingleOrNull();
        if (currentSale == null ||
            currentSale.status == AppConstants.saleRefunded ||
            currentSale.status == AppConstants.saleVoided ||
            currentSale.storeId != request.storeId) {
          throw const ValidationException(
            'The original sale is no longer eligible for return.',
          );
        }
        saleLines =
            await (db.select(db.saleLines)..where(
                  (table) => table.saleId.equals(request.originalSaleId!),
                ))
                .get();
        final currentReturns =
            await (db.select(db.returns)..where(
                  (table) =>
                      table.originalSaleId.equals(request.originalSaleId!),
                ))
                .get();
        final currentReturnIds = currentReturns
            .map((value) => value.id)
            .toList();
        priorReturnLines = currentReturnIds.isEmpty
            ? <ReturnLine>[]
            : await (db.select(
                db.returnLines,
              )..where((table) => table.returnId.isIn(currentReturnIds))).get();
        _validateItemsAgainstSale(
          request: request,
          saleLines: saleLines,
          priorReturnLines: priorReturnLines,
        );
      } else {
        await PermissionGuard.requirePermission(
          db,
          request.managerId!,
          AppPermissions.noReceiptReturn,
        );
      }

      // 1. Insert Return record
      await db
          .into(db.returns)
          .insert(
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
        final restockLocationId =
            (item.condition == AppConstants.returnConditionDamaged)
            ? damagedLocation!.id
            : shopFloor.id;

        await db
            .into(db.returnLines)
            .insert(
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
          reason:
              'Return #$returnNumber: ${request.reason} (${item.condition})',
        );
      }

      // 3. Update original sale status (PARTIALLY_REFUNDED or REFUNDED)
      if (request.originalSaleId != null) {
        final totalUnitsSold = saleLines.fold<int>(0, (s, l) => s + l.quantity);
        final totalUnitsReturnedPrior = priorReturnLines.fold<int>(
          0,
          (s, l) => s + l.quantity,
        );
        final totalUnitsReturnedNow = request.items.fold<int>(
          0,
          (s, i) => s + i.quantity,
        );
        final isFullyReturned =
            (totalUnitsReturnedPrior + totalUnitsReturnedNow) >= totalUnitsSold;

        await (db.update(
          db.sales,
        )..where((tbl) => tbl.id.equals(request.originalSaleId!))).write(
          SalesCompanion(
            status: Value(
              isFullyReturned
                  ? AppConstants.saleRefunded
                  : 'PARTIALLY_REFUNDED',
            ),
          ),
        );
      }

      // 4. Audit entry
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'RETURN_PROCESSED',
              entityType: 'RETURN',
              entityId: Value(returnId),
              userId: request.cashierId,
              managerId: Value(request.managerId),
              detailsJson: Value(
                '{"returnNumber":"$returnNumber","totalRefund":${totalRefund.millimes},"method":"${request.refundMethod}"}',
              ),
              createdAt: now,
            ),
          );

      // 5. Outbox event
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'RETURN',
              operation: 'INSERT',
              payloadJson:
                  '{"id":"$returnId","returnNumber":"$returnNumber","totalRefund":${totalRefund.millimes}}',
              createdAt: now,
              updatedAt: now,
            ),
          );

      committedReturn = await (db.select(
        db.returns,
      )..where((tbl) => tbl.id.equals(returnId))).getSingle();
    });

    PosLogger.instance.info(
      'Returns',
      'Return #$returnNumber completed: total refund $totalRefund',
    );
    return committedReturn;
  }
}
