import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';

class ShiftSummary {
  final Shift shift;
  final Money openingCash;
  final Money cashSales;
  final Money cardSales;
  final Money mixedSales;
  final Money storeCreditSales;
  final Money cashRefunds;
  final Money cashIn;
  final Money cashOut;
  final Money expectedCash;
  final Money? countedCash;
  final Money? difference;
  final int totalTransactions;

  const ShiftSummary({
    required this.shift,
    required this.openingCash,
    required this.cashSales,
    required this.cardSales,
    required this.mixedSales,
    required this.storeCreditSales,
    required this.cashRefunds,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    this.countedCash,
    this.difference,
    required this.totalTransactions,
  });
}

class ShiftService {
  final AppDatabase db;

  ShiftService(this.db);

  /// Get active open shift for register or cashier
  Future<Shift?> getOpenShift(String registerId) async {
    return (db.select(db.shifts)
          ..where(
            (tbl) =>
                tbl.registerId.equals(registerId) &
                tbl.status.equals(AppConstants.shiftOpen),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Open a new shift with opening float cash
  Future<Shift> openShift({
    required String registerId,
    required String cashierId,
    required Money openingCash,
    String? note,
  }) async {
    if (openingCash.isNegative) {
      throw const ValidationException('Opening float cash cannot be negative.');
    }

    final existing = await getOpenShift(registerId);
    if (existing != null) {
      throw const ValidationException(
        'An active shift is already open for this register.',
      );
    }

    final shiftId = IdGenerator.uuid();
    final now = DateTime.now();

    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: shiftId,
            registerId: registerId,
            cashierId: cashierId,
            openedAt: now,
            openingCashMillimes: Value(openingCash.millimes),
            note: Value(note),
            status: const Value(AppConstants.shiftOpen),
          ),
        );

    // Audit event
    await db
        .into(db.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: IdGenerator.uuid(),
            action: 'SHIFT_OPENED',
            entityType: 'SHIFT',
            entityId: Value(shiftId),
            userId: cashierId,
            detailsJson: Value('{"openingCash":${openingCash.millimes}}'),
            createdAt: now,
          ),
        );

    PosLogger.instance.info(
      'Shift',
      'Shift $shiftId opened with float: ${openingCash.format()}',
    );
    return (db.select(
      db.shifts,
    )..where((tbl) => tbl.id.equals(shiftId))).getSingle();
  }

  /// Record cash movement (Pay In, Pay Out, Cash Drop)
  Future<void> recordCashMovement({
    required String shiftId,
    required String userId,
    required String type, // PAY_IN, PAY_OUT, CASH_DROP
    required Money amount,
    required String reason,
  }) async {
    if (amount <= Money.zero) {
      throw const ValidationException(
        'Cash movement amount must be greater than zero',
      );
    }

    final now = DateTime.now();
    await db
        .into(db.cashMovements)
        .insert(
          CashMovementsCompanion.insert(
            id: IdGenerator.uuid(),
            shiftId: shiftId,
            userId: userId,
            movementType: type,
            amountMillimes: amount.millimes,
            reason: reason,
            createdAt: now,
          ),
        );

    // Audit
    await db
        .into(db.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: IdGenerator.uuid(),
            action: 'CASH_MOVEMENT_$type',
            entityType: 'SHIFT',
            entityId: Value(shiftId),
            userId: userId,
            detailsJson: Value(
              '{"amount":${amount.millimes},"reason":"$reason"}',
            ),
            createdAt: now,
          ),
        );

    PosLogger.instance.info(
      'Shift',
      'Cash movement $type: ${amount.format()} reason: $reason',
    );
  }

  /// Calculate live shift summary and expected cash balance
  Future<ShiftSummary> calculateShiftSummary(String shiftId) async {
    final shift = await (db.select(
      db.shifts,
    )..where((tbl) => tbl.id.equals(shiftId))).getSingle();
    final openingCash = Money.fromMillimes(shift.openingCashMillimes);

    // Sales in this shift
    final sales =
        await (db.select(db.sales)..where(
              (tbl) =>
                  tbl.shiftId.equals(shiftId) &
                  tbl.status.isIn([
                    AppConstants.saleCompleted,
                    AppConstants.salePartiallyRefunded,
                    AppConstants.saleRefunded,
                  ]),
            ))
            .get();

    // Payments in this shift
    final saleIds = sales.map((s) => s.id).toList();
    final payments = saleIds.isEmpty
        ? <SalePayment>[]
        : await (db.select(
            db.salePayments,
          )..where((tbl) => tbl.saleId.isIn(saleIds))).get();

    Money cashSales = Money.zero;
    Money cardSales = Money.zero;
    Money mixedSales = Money.zero;
    Money storeCreditSales = Money.zero;

    for (final p in payments) {
      final amount = Money.fromMillimes(p.amountMillimes);
      switch (p.paymentMethod) {
        case AppConstants.paymentCash:
          cashSales += amount;
          break;
        case AppConstants.paymentCard:
          cardSales += amount;
          break;
        case AppConstants.paymentMixed:
          mixedSales += amount;
          break;
        case AppConstants.paymentStoreCredit:
          storeCreditSales += amount;
          break;
      }
    }

    // Cash refunds in this shift
    final returns = await (db.select(
      db.returns,
    )..where((tbl) => tbl.shiftId.equals(shiftId))).get();
    Money cashRefunds = Money.zero;
    for (final r in returns) {
      if (r.refundMethod == AppConstants.paymentCash) {
        cashRefunds += Money.fromMillimes(r.totalRefundMillimes);
      }
    }

    // Cash movements (Pay In / Pay Out)
    final movements = await (db.select(
      db.cashMovements,
    )..where((tbl) => tbl.shiftId.equals(shiftId))).get();
    Money cashIn = Money.zero;
    Money cashOut = Money.zero;

    for (final m in movements) {
      final amt = Money.fromMillimes(m.amountMillimes);
      if (m.movementType == AppConstants.cashPayIn) {
        cashIn += amt;
      } else {
        cashOut += amt;
      }
    }

    // Expected cash formula: Opening Cash + Cash Sales - Cash Refunds + Pay In - Pay Out
    final expectedCash =
        openingCash + cashSales - cashRefunds + cashIn - cashOut;

    Money? countedCash;
    Money? difference;
    if (shift.countedCashMillimes != null) {
      countedCash = Money.fromMillimes(shift.countedCashMillimes!);
      difference = countedCash - expectedCash;
    }

    return ShiftSummary(
      shift: shift,
      openingCash: openingCash,
      cashSales: cashSales,
      cardSales: cardSales,
      mixedSales: mixedSales,
      storeCreditSales: storeCreditSales,
      cashRefunds: cashRefunds,
      cashIn: cashIn,
      cashOut: cashOut,
      expectedCash: expectedCash,
      countedCash: countedCash,
      difference: difference,
      totalTransactions: sales.length,
    );
  }

  /// Close shift with physical cash count and generate Z-Report
  Future<ShiftSummary> closeShift({
    required String shiftId,
    required String cashierId,
    required Money countedCash,
    String? note,
  }) async {
    final existingShift = await (db.select(
      db.shifts,
    )..where((tbl) => tbl.id.equals(shiftId))).getSingleOrNull();
    if (existingShift == null) {
      throw const ValidationException('Shift not found.');
    }
    if (existingShift.status == AppConstants.shiftClosed) {
      throw const ValidationException('This register shift is already closed.');
    }

    final summary = await calculateShiftSummary(shiftId);
    final difference = countedCash - summary.expectedCash;
    final now = DateTime.now();

    await db.transaction(() async {
      await (db.update(
        db.shifts,
      )..where((tbl) => tbl.id.equals(shiftId))).write(
        ShiftsCompanion(
          closedAt: Value(now),
          expectedCashMillimes: Value(summary.expectedCash.millimes),
          countedCashMillimes: Value(countedCash.millimes),
          cashDifferenceMillimes: Value(difference.millimes),
          note: Value(note),
          status: const Value(AppConstants.shiftClosed),
        ),
      );

      // Enqueue Z-Report print job
      await db
          .into(db.printJobs)
          .insert(
            PrintJobsCompanion.insert(
              id: IdGenerator.uuid(),
              jobType: 'SHIFT_REPORT',
              payloadJson: jsonEncode({
                'shiftId': shiftId,
                'openingCash': summary.openingCash.millimes,
                'cashSales': summary.cashSales.millimes,
                'cardSales': summary.cardSales.millimes,
                'expectedCash': summary.expectedCash.millimes,
                'countedCash': countedCash.millimes,
                'difference': difference.millimes,
                'closedAt': now.toIso8601String(),
              }),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Audit event
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: IdGenerator.uuid(),
              action: 'SHIFT_CLOSED',
              entityType: 'SHIFT',
              entityId: Value(shiftId),
              userId: cashierId,
              detailsJson: Value(
                jsonEncode({
                  'expectedCash': summary.expectedCash.millimes,
                  'countedCash': countedCash.millimes,
                  'difference': difference.millimes,
                }),
              ),
              createdAt: now,
            ),
          );
    });

    PosLogger.instance.info(
      'Shift',
      'Shift $shiftId closed. Expected: ${summary.expectedCash.format()}, Counted: ${countedCash.format()}, Diff: ${difference.format()}',
    );

    return calculateShiftSummary(shiftId);
  }
}
