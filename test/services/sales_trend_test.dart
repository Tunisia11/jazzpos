import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/report_service.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 10, 21, 18);

  Future<void> user(String id, String role) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: id, username: id, displayName: id, role: role,
            pinHash: 'h', pinSalt: 's', createdAt: now, updatedAt: now));

  Future<void> sale(String id, DateTime at, int total,
      {int discount = 0, int unitCost = 0}) async {
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: id, receiptNumber: 'R-$id', storeId: 'st', registerId: 'rg',
          shiftId: 'sh', cashierId: 'owner', subtotalMillimes: total,
          discountMillimes: Value(discount),
          totalMillimes: total - discount, idempotencyKey: 'k$id', createdAt: at));
    await db.into(db.saleLines).insert(SaleLinesCompanion.insert(
          id: 'l$id', saleId: id, variantId: 'v', productName: 'x',
          variantDescription: '', sku: 's', barcode: 'b', quantity: 2,
          unitPriceMillimes: total ~/ 2, originalPriceMillimes: total ~/ 2,
          unitCostMillimes: Value(unitCost), totalMillimes: total));
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = OFF;');
    await user('owner', 'OWNER');
    await user('cash', 'CASHIER');
  });
  tearDown(() => db.close());

  test('hourly buckets add up to the report totals, refunds and cost included', () async {
    await sale('a', DateTime(2026, 10, 21, 9, 5), 60000, discount: 5000, unitCost: 10000);
    await sale('b', DateTime(2026, 10, 21, 14, 30), 40000, unitCost: 8000);
    await db.into(db.returns).insert(ReturnsCompanion.insert(
          id: 'r1', returnNumber: 'RT-1', originalSaleId: const Value('a'), storeId: 'st',
          registerId: 'rg', shiftId: 'sh', cashierId: 'owner', reason: 'x',
          refundMethod: 'CASH', totalRefundMillimes: 15000,
          createdAt: DateTime(2026, 10, 21, 16)));

    final start = DateTime(2026, 10, 21);
    final end = DateTime(2026, 10, 22).subtract(const Duration(microseconds: 1));
    final svc = ReportService(db);
    final trend = await svc.getSalesTrend(
        actorId: 'owner', startDate: start, endDate: end, hourly: true);
    final report = await svc.getSalesReport(
        actorId: 'owner', startDate: start, endDate: end);

    expect(trend, hasLength(24));
    expect(trend[9].net.millimes, 60000 - 5000);
    expect(trend[14].net.millimes, 40000);
    expect(trend[16].net.millimes, -15000);
    expect(trend.fold<int>(0, (s, p) => s + p.net.millimes), report.netSales.millimes);
    expect(trend.fold<int>(0, (s, p) => s + p.cost.millimes), report.totalCost.millimes);
    expect(trend.fold<int>(0, (s, p) => s + p.profit.millimes), report.grossProfit.millimes);
  });

  test('daily buckets cover the whole range', () async {
    await sale('a', DateTime(2026, 10, 15, 10), 20000);
    await sale('b', DateTime(2026, 10, 21, 10), 30000);
    final trend = await ReportService(db).getSalesTrend(
      actorId: 'owner',
      startDate: DateTime(2026, 10, 15),
      endDate: DateTime(2026, 10, 22).subtract(const Duration(microseconds: 1)),
      hourly: false,
    );
    expect(trend, hasLength(7));
    expect(trend.first.net.millimes, 20000);
    expect(trend.last.net.millimes, 30000);
    expect(trend.last.start, DateTime(2026, 10, 21));
  });

  test('requires the view-reports permission', () {
    expect(
      ReportService(db).getSalesTrend(
          actorId: 'cash', startDate: now, endDate: now, hourly: true),
      throwsA(isA<AuthException>()),
    );
  });
}
