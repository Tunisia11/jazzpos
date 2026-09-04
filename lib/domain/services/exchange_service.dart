import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import '../models/cart_item.dart';
import '../models/checkout_request.dart';
import 'return_service.dart';
import 'sale_service.dart';

class ExchangeRequest {
  final String? originalSaleId;
  final String storeId;
  final String registerId;
  final String shiftId;
  final String cashierId;
  final List<ReturnLineItem> returnedItems;
  final List<CartItem> newItems;
  final String paymentMethod; // CASH, CARD, STORE_CREDIT
  final Money tendered;
  final String reason;
  final String? managerOverrideId;

  const ExchangeRequest({
    this.originalSaleId,
    required this.storeId,
    required this.registerId,
    required this.shiftId,
    required this.cashierId,
    required this.returnedItems,
    required this.newItems,
    required this.paymentMethod,
    this.tendered = Money.zero,
    required this.reason,
    this.managerOverrideId,
  });

  Money get returnedTotal =>
      returnedItems.fold(Money.zero, (s, i) => s + i.totalRefund);
  Money get newTotal => newItems.fold(Money.zero, (s, i) => s + i.total);
  Money get difference =>
      newTotal -
      returnedTotal; // positive: customer pays, negative: customer refunded
}

class ExchangeCompletedResult {
  final Exchange exchange;
  final Return returnRecord;
  final Sale newSale;
  final Money difference;

  const ExchangeCompletedResult({
    required this.exchange,
    required this.returnRecord,
    required this.newSale,
    required this.difference,
  });
}

class ExchangeService {
  final AppDatabase db;
  final ReturnService returnService;
  final SaleService saleService;

  ExchangeService(this.db, this.returnService, this.saleService);

  /// Process an atomic exchange of clothing items
  Future<ExchangeCompletedResult> processExchange(
    ExchangeRequest request,
  ) async {
    if (request.returnedItems.isEmpty) {
      throw const ValidationException(
        'Exchange must include at least one returned item',
      );
    }
    if (request.newItems.isEmpty) {
      throw const ValidationException(
        'Exchange must include at least one new item',
      );
    }

    final diff = request.difference;

    // 1. Process return part
    // The returned items provide exchange credit. We record the return refund method as STORE_CREDIT
    // so that the gross value of returned items is not deducted from physical cash drawer in ShiftService.
    final returnRecord = await returnService.processReturn(
      ReturnRequest(
        originalSaleId: request.originalSaleId,
        storeId: request.storeId,
        registerId: request.registerId,
        shiftId: request.shiftId,
        cashierId: request.cashierId,
        reason: 'Exchange: ${request.reason}',
        refundMethod: AppConstants.paymentStoreCredit,
        items: request.returnedItems,
        managerId: request.managerOverrideId,
      ),
    );

    // If customer returned a more expensive item and is owed cash difference, record a cash payout
    if (diff.isNegative && request.paymentMethod == AppConstants.paymentCash) {
      await db
          .into(db.cashMovements)
          .insert(
            CashMovementsCompanion.insert(
              id: IdGenerator.uuid(),
              shiftId: request.shiftId,
              userId: request.cashierId,
              movementType: AppConstants.cashPayOut,
              amountMillimes: diff.abs.millimes,
              reason:
                  'Exchange refund difference for Return #${returnRecord.returnNumber}',
              createdAt: DateTime.now(),
            ),
          );
    }

    // 2. Prepare checkout for new item(s)
    // If difference > 0, customer pays difference.
    // If difference <= 0, new sale is paid in full by exchange credit (+ optional refund if negative)
    final payments = <PaymentSplit>[];
    if (diff.isPositive) {
      // Customer pays the difference
      final change = request.tendered > diff
          ? request.tendered - diff
          : Money.zero;
      payments.add(
        PaymentSplit(
          method: request.paymentMethod,
          amount: diff,
          tendered: request.tendered,
          change: change,
          reference: 'Exchange payment',
        ),
      );
      // Remainder covered by exchange credit
      payments.add(
        PaymentSplit(
          method: AppConstants.paymentStoreCredit,
          amount: request.returnedTotal,
          reference:
              'Exchange credit from Return #${returnRecord.returnNumber}',
        ),
      );
    } else {
      // Returned item was equal or more expensive: entire new sale covered by exchange credit
      payments.add(
        PaymentSplit(
          method: AppConstants.paymentStoreCredit,
          amount: request.newTotal,
          reference:
              'Exchange credit from Return #${returnRecord.returnNumber}',
        ),
      );
    }

    final checkoutResult = await saleService.checkout(
      CheckoutRequest(
        storeId: request.storeId,
        registerId: request.registerId,
        shiftId: request.shiftId,
        cashierId: request.cashierId,
        items: request.newItems,
        payments: payments,
        idempotencyKey: 'EXCHANGE-${returnRecord.id}',
        notes:
            'Exchange for Return #${returnRecord.returnNumber}. Net difference: ${diff.format()}',
        managerOverrideId: request.managerOverrideId,
      ),
    );

    // 3. Link them in the Exchanges table
    final exchangeId = IdGenerator.uuid();
    final now = DateTime.now();

    await db
        .into(db.exchanges)
        .insert(
          ExchangesCompanion.insert(
            id: exchangeId,
            returnId: returnRecord.id,
            newSaleId: checkoutResult.sale.id,
            differenceMillimes: diff.millimes,
            paymentMethod: Value(request.paymentMethod),
            cashierId: request.cashierId,
            createdAt: now,
          ),
        );

    final exchange = await (db.select(
      db.exchanges,
    )..where((tbl) => tbl.id.equals(exchangeId))).getSingle();

    PosLogger.instance.info(
      'Exchange',
      'Exchange completed: Return #${returnRecord.returnNumber} -> Sale #${checkoutResult.sale.receiptNumber}, diff: ${diff.format()}',
    );

    return ExchangeCompletedResult(
      exchange: exchange,
      returnRecord: returnRecord,
      newSale: checkoutResult.sale,
      difference: diff,
    );
  }
}
