import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import '../models/checkout_request.dart';
import '../models/cart_item.dart';
import 'inventory_service.dart';

class SaleCompletedResult {
  final Sale sale;
  final List<SaleLine> lines;
  final List<SalePayment> payments;
  final String printJobId;

  const SaleCompletedResult({
    required this.sale,
    required this.lines,
    required this.payments,
    required this.printJobId,
  });
}

class SaleService {
  final AppDatabase db;
  final InventoryService inventoryService;

  SaleService(this.db, this.inventoryService);

  /// Execute an atomic POS sale checkout
  Future<SaleCompletedResult> checkout(CheckoutRequest request) async {
    if (request.items.isEmpty) {
      throw const ValidationException('Cannot checkout an empty cart');
    }
    if (request.payments.isEmpty) {
      throw const ValidationException(
        'At least one payment method is required',
      );
    }
    final seenVariants = <String>{};
    for (final item in request.items) {
      if (!seenVariants.add(item.variantId)) {
        throw const ValidationException(
          'Duplicate variants must be combined into one cart line.',
        );
      }
      if (item.quantity <= 0) {
        throw const ValidationException(
          'Sale quantity must be greater than zero',
        );
      }
      if (item.unitPrice.isNegative || item.originalPrice.isNegative) {
        throw const ValidationException('Sale prices cannot be negative');
      }
      if (item.lineDiscount.isNegative || item.lineDiscount > item.subtotal) {
        throw const ValidationException('Invalid sale line discount');
      }
      if (!item.taxRatePercent.isFinite ||
          item.taxRatePercent < 0 ||
          item.taxRatePercent > 100) {
        throw const ValidationException('Invalid tax rate');
      }
    }
    if (request.cartDiscount.isNegative ||
        request.cartDiscount > request.subtotal) {
      throw const ValidationException('Invalid cart discount');
    }

    // 1. Check idempotency: if already processed, return existing sale
    final existingSale =
        await (db.select(db.sales)..where(
              (tbl) => tbl.idempotencyKey.equals(request.idempotencyKey),
            ))
            .getSingleOrNull();
    if (existingSale != null) {
      PosLogger.instance.warning(
        'Sales',
        'Duplicate checkout prevented by idempotencyKey: ${request.idempotencyKey}',
      );
      final existingLines = await (db.select(
        db.saleLines,
      )..where((tbl) => tbl.saleId.equals(existingSale.id))).get();
      final existingPayments = await (db.select(
        db.salePayments,
      )..where((tbl) => tbl.saleId.equals(existingSale.id))).get();
      return SaleCompletedResult(
        sale: existingSale,
        lines: existingLines,
        payments: existingPayments,
        printJobId: '',
      );
    }

    // 2. Validate stock for each line according to store policy
    final setting =
        await (db.select(db.appSettings)..where(
              (tbl) => tbl.key.equals(AppConstants.keyNegativeStockPolicy),
            ))
            .getSingleOrNull();
    final policy = setting?.value ?? AppConstants.negativeStockWarn;

    final defaultLocation = await inventoryService.getDefaultLocation(
      request.storeId,
    );

    for (final item in request.items) {
      await inventoryService.validateStockAvailability(
        variantId: item.variantId,
        requestedQuantity: item.quantity,
        policy: policy,
        managerOverrideId: request.managerOverrideId,
        locationId: defaultLocation.id,
      );
    }

    // 3. Compute totals in exact integer millimes
    final subtotal = request.subtotal;
    final totalDiscount =
        request.cartDiscount +
        request.items.fold(Money.zero, (s, i) => s + i.lineDiscount);
    final totalAmount = request.total;

    // Payment records represent the amount applied to the receipt; cash
    // tendered and change are tracked separately. Over-recording payment would
    // inflate cash and payment-method reports just as surely as underpayment.
    if (request.totalPaid != totalAmount) {
      throw ValidationException(
        'Applied payments (${request.totalPaid}) must equal the sale total ($totalAmount)',
      );
    }
    const supportedPayments = {
      AppConstants.paymentCash,
      AppConstants.paymentCard,
      AppConstants.paymentMixed,
      AppConstants.paymentStoreCredit,
      AppConstants.paymentOther,
    };
    for (final payment in request.payments) {
      if (!supportedPayments.contains(payment.method) ||
          payment.amount.isNegative ||
          payment.tendered.isNegative ||
          payment.change.isNegative) {
        throw const ValidationException('Invalid payment details');
      }
      if (payment.method == AppConstants.paymentCash &&
          payment.tendered > Money.zero &&
          payment.tendered - payment.change != payment.amount) {
        throw const ValidationException(
          'Cash tendered, change, and applied amount do not agree.',
        );
      }
    }

    final saleId = IdGenerator.uuid();
    final receiptNumber = IdGenerator.receiptNumber();
    final printJobId = IdGenerator.uuid();
    final now = DateTime.now();

    late Sale committedSale;
    late List<SaleLine> committedLines;
    late List<SalePayment> committedPayments;
    SaleCompletedResult? duplicateResult;

    // 4. ATOMIC SQLITE TRANSACTION
    await db.transaction(() async {
      final duplicate =
          await (db.select(db.sales)..where(
                (table) => table.idempotencyKey.equals(request.idempotencyKey),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        duplicateResult = SaleCompletedResult(
          sale: duplicate,
          lines: await (db.select(
            db.saleLines,
          )..where((table) => table.saleId.equals(duplicate.id))).get(),
          payments: await (db.select(
            db.salePayments,
          )..where((table) => table.saleId.equals(duplicate.id))).get(),
          printJobId: '',
        );
        return;
      }

      // A checkout may have been initiated just as another operator closes the
      // register. Re-check the actual shift inside the write transaction so a
      // completed sale can never be attached to a closed or different register.
      final activeShift = await (db.select(
        db.shifts,
      )..where((tbl) => tbl.id.equals(request.shiftId))).getSingleOrNull();
      if (activeShift == null ||
          activeShift.status != AppConstants.shiftOpen ||
          activeShift.registerId != request.registerId) {
        throw const ValidationException(
          'The selected cash register shift is no longer open.',
        );
      }
      final register =
          await (db.select(db.registers)
                ..where((table) => table.id.equals(request.registerId)))
              .getSingleOrNull();
      if (register == null || register.storeId != request.storeId) {
        throw const ValidationException(
          'The selected register does not belong to this store.',
        );
      }
      final cashier =
          await (db.select(db.users)..where(
                (table) =>
                    table.id.equals(request.cashierId) &
                    table.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (cashier == null) {
        throw const AuthException('An active cashier session is required.');
      }

      final currentPolicySetting =
          await (db.select(db.appSettings)..where(
                (table) =>
                    table.key.equals(AppConstants.keyNegativeStockPolicy),
              ))
              .getSingleOrNull();
      final currentPolicy =
          currentPolicySetting?.value ?? AppConstants.negativeStockWarn;
      for (final item in request.items) {
        final variant = await (db.select(
          db.productVariants,
        )..where((table) => table.id.equals(item.variantId))).getSingleOrNull();
        if (variant == null || !variant.isActive || variant.deletedAt != null) {
          throw const ValidationException(
            'A product variant in this cart is no longer available.',
          );
        }
        final product =
            await (db.select(db.products)
                  ..where((table) => table.id.equals(variant.productId)))
                .getSingleOrNull();
        if (product == null ||
            product.status != 'ACTIVE' ||
            product.deletedAt != null) {
          throw const ValidationException(
            'A product in this cart is archived or unavailable.',
          );
        }
        await inventoryService.validateStockAvailability(
          variantId: item.variantId,
          requestedQuantity: item.quantity,
          policy: currentPolicy,
          managerOverrideId: request.managerOverrideId,
          locationId: defaultLocation.id,
        );
      }

      // 4a. Insert Sale
      final saleCompanion = SalesCompanion.insert(
        id: saleId,
        receiptNumber: receiptNumber,
        storeId: request.storeId,
        registerId: request.registerId,
        shiftId: request.shiftId,
        cashierId: request.cashierId,
        customerId: Value(request.customerId),
        subtotalMillimes: subtotal.millimes,
        discountMillimes: Value(totalDiscount.millimes),
        taxMillimes: Value(
          request.items.fold(0, (s, i) => s + i.taxAmount.millimes),
        ),
        totalMillimes: totalAmount.millimes,
        status: const Value(AppConstants.saleCompleted),
        notes: Value(request.notes),
        idempotencyKey: request.idempotencyKey,
        createdAt: now,
      );
      await db.into(db.sales).insert(saleCompanion);

      // 4b. Insert Sale Lines with immutable snapshots
      final insertedLines = <SaleLine>[];
      for (final item in request.items) {
        final lineId = IdGenerator.uuid();
        final lineCompanion = SaleLinesCompanion.insert(
          id: lineId,
          saleId: saleId,
          variantId: item.variantId,
          productName: item.productName,
          variantDescription: item.variantDescription,
          sku: item.sku,
          barcode: item.barcode,
          quantity: item.quantity,
          unitPriceMillimes: item.unitPrice.millimes,
          originalPriceMillimes: item.originalPrice.millimes,
          discountMillimes: Value(item.lineDiscount.millimes),
          taxRatePercent: Value(item.taxRatePercent),
          taxAmountMillimes: Value(item.taxAmount.millimes),
          totalMillimes: item.total.millimes,
          unitCostMillimes: Value(item.unitCost.millimes),
        );
        await db.into(db.saleLines).insert(lineCompanion);
        insertedLines.add(
          await (db.select(
            db.saleLines,
          )..where((tbl) => tbl.id.equals(lineId))).getSingle(),
        );

        // 4c. Deduct physical stock through StockMovements
        await inventoryService.recordMovement(
          variantId: item.variantId,
          movementType: AppConstants.movementSale,
          quantityDelta: -item.quantity,
          fromLocationId: defaultLocation.id,
          unitCostMillimes: item.unitCost.millimes,
          referenceId: saleId,
          referenceType: 'SALE',
          actorId: request.cashierId,
          reason: 'Sale #$receiptNumber',
        );
      }

      // 4d. Insert Payment Records
      final insertedPayments = <SalePayment>[];

      for (final p in request.payments) {
        final paymentId = IdGenerator.uuid();
        final paymentCompanion = SalePaymentsCompanion.insert(
          id: paymentId,
          saleId: saleId,
          paymentMethod: p.method,
          amountMillimes: p.amount.millimes,
          tenderedMillimes: Value(p.tendered.millimes),
          changeMillimes: Value(p.change.millimes),
          reference: Value(p.reference),
          createdAt: now,
        );
        await db.into(db.salePayments).insert(paymentCompanion);
        insertedPayments.add(
          await (db.select(
            db.salePayments,
          )..where((tbl) => tbl.id.equals(paymentId))).getSingle(),
        );
      }

      // 4e. Update Customer spending if attached
      if (request.customerId != null) {
        final cust =
            await (db.select(db.customers)
                  ..where((tbl) => tbl.id.equals(request.customerId!)))
                .getSingleOrNull();
        if (cust != null) {
          await (db.update(
            db.customers,
          )..where((tbl) => tbl.id.equals(cust.id))).write(
            CustomersCompanion(
              totalSpentMillimes: Value(
                cust.totalSpentMillimes + totalAmount.millimes,
              ),
            ),
          );
        }
      }

      // 4f. Insert Audit Event
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'SALE_COMPLETED',
              entityType: 'SALE',
              entityId: Value(saleId),
              userId: request.cashierId,
              managerId: Value(request.managerOverrideId),
              detailsJson: Value(
                jsonEncode({
                  'receiptNumber': receiptNumber,
                  'total': totalAmount.millimes,
                  'itemsCount': request.items.length,
                }),
              ),
              createdAt: now,
            ),
          );

      // 4g. Queue Outbox Event for async cloud sync
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'SALE',
              operation: 'INSERT',
              payloadJson: jsonEncode({
                'id': saleId,
                'receiptNumber': receiptNumber,
                'totalMillimes': totalAmount.millimes,
                'linesCount': request.items.length,
              }),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // 4h. Enqueue Print Job for hardware receipt printer
      await db
          .into(db.printJobs)
          .insert(
            PrintJobsCompanion.insert(
              id: printJobId,
              jobType: 'RECEIPT',
              payloadJson: jsonEncode({
                'saleId': saleId,
                'receiptNumber': receiptNumber,
                'totalMillimes': totalAmount.millimes,
                'cashierId': request.cashierId,
              }),
              createdAt: now,
              updatedAt: now,
            ),
          );

      committedSale = await (db.select(
        db.sales,
      )..where((tbl) => tbl.id.equals(saleId))).getSingle();
      committedLines = insertedLines;
      committedPayments = insertedPayments;
    });

    if (duplicateResult != null) return duplicateResult!;

    PosLogger.instance.info(
      'Sales',
      'Sale #$receiptNumber successfully committed locally in transaction.',
    );

    return SaleCompletedResult(
      sale: committedSale,
      lines: committedLines,
      payments: committedPayments,
      printJobId: printJobId,
    );
  }

  /// Suspend / hold a cart for later resumption
  Future<String> suspendCart({
    required String referenceName,
    required String cashierId,
    required String registerId,
    required List<CartItem> items,
    Money cartDiscount = Money.zero,
  }) async {
    final id = IdGenerator.uuid();
    final json = jsonEncode({
      'cartDiscount': cartDiscount.millimes,
      'items': items
          .map(
            (i) => {
              'variantId': i.variantId,
              'productId': i.productId,
              'productName': i.productName,
              'variantDescription': i.variantDescription,
              'sku': i.sku,
              'barcode': i.barcode,
              'unitPrice': i.unitPrice.millimes,
              'originalPrice': i.originalPrice.millimes,
              'quantity': i.quantity,
              'lineDiscount': i.lineDiscount.millimes,
              'taxRatePercent': i.taxRatePercent,
              'unitCost': i.unitCost.millimes,
            },
          )
          .toList(),
    });

    await db
        .into(db.suspendedCarts)
        .insert(
          SuspendedCartsCompanion.insert(
            id: id,
            referenceName: referenceName,
            cashierId: cashierId,
            registerId: registerId,
            cartJson: json,
            createdAt: DateTime.now(),
          ),
        );

    return id;
  }

  /// Get all currently held carts
  Future<List<SuspendedCart>> getSuspendedCarts(String registerId) async {
    return (db.select(
      db.suspendedCarts,
    )..where((tbl) => tbl.registerId.equals(registerId))).get();
  }

  /// Remove a suspended cart upon resuming or discarding
  Future<void> deleteSuspendedCart(String id) async {
    await (db.delete(
      db.suspendedCarts,
    )..where((tbl) => tbl.id.equals(id))).go();
  }

  /// Void an existing sale (requires manager authorization)
  Future<void> voidSale({
    required String saleId,
    required String actorId,
    required String managerId,
    required String reason,
  }) async {
    final sale = await (db.select(
      db.sales,
    )..where((tbl) => tbl.id.equals(saleId))).getSingleOrNull();
    if (sale == null) {
      throw const ValidationException('Sale not found');
    }
    if (sale.status == AppConstants.saleVoided) {
      throw const ValidationException('Sale is already voided');
    }

    final lines = await (db.select(
      db.saleLines,
    )..where((tbl) => tbl.saleId.equals(saleId))).get();
    final defaultLocation = await inventoryService.getDefaultLocation(
      sale.storeId,
    );
    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Update sale status
      await (db.update(db.sales)..where((tbl) => tbl.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value(AppConstants.saleVoided),
          notes: Value('Voided: $reason (authorized by manager $managerId)'),
        ),
      );

      // 2. Restock all items back into shop floor
      for (final line in lines) {
        await inventoryService.recordMovement(
          variantId: line.variantId,
          movementType: AppConstants.movementReturn,
          quantityDelta: line.quantity,
          toLocationId: defaultLocation.id,
          unitCostMillimes: line.unitCostMillimes,
          referenceId: saleId,
          referenceType: 'SALE_VOID',
          actorId: actorId,
          reason: 'Void sale #${sale.receiptNumber}: $reason',
        );
      }

      // 3. Audit log
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'SALE_VOIDED',
              entityType: 'SALE',
              entityId: Value(saleId),
              userId: actorId,
              managerId: Value(managerId),
              detailsJson: Value(
                '{"reason":"$reason","receiptNumber":"${sale.receiptNumber}"}',
              ),
              createdAt: now,
            ),
          );

      // 4. Outbox sync
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: IdGenerator.uuid(),
              entityType: 'SALE',
              operation: 'UPDATE',
              payloadJson: '{"id":"$saleId","status":"VOIDED"}',
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'Sales',
      'Sale #${sale.receiptNumber} voided by user $actorId authorized by $managerId',
    );
  }
}
