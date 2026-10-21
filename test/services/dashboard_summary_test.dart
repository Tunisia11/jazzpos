import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/report_service.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 10, 21, 18);

  Future<void> user(String id, String role) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: id, username: id, displayName: id, role: role,
            pinHash: 'h', pinSalt: 's', createdAt: now, updatedAt: now));

  Future<void> sale(String id, DateTime at, int total, String method) async {
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: id, receiptNumber: 'R-$id', storeId: 'st', registerId: 'rg',
          shiftId: 'sh', cashierId: 'owner', subtotalMillimes: total,
          totalMillimes: total, idempotencyKey: 'k$id', createdAt: at));
    await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
          id: 'p$id', saleId: id, paymentMethod: method,
          amountMillimes: total, createdAt: at));
    await db.into(db.saleLines).insert(SaleLinesCompanion.insert(
          id: 'l$id', saleId: id, variantId: 'v', productName: 'x',
          variantDescription: '', sku: 's', barcode: 'b', quantity: 2,
          unitPriceMillimes: total ~/ 2, originalPriceMillimes: total ~/ 2,
          totalMillimes: total));
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = OFF;');
    await user('owner', 'OWNER');
    await user('cash', 'CASHIER');
  });
  tearDown(() => db.close());

  test('summarises today vs yesterday with hourly buckets and recent sales', () async {
    await sale('a', DateTime(2026, 10, 21, 9, 5), 60000, 'CASH');
    await sale('b', DateTime(2026, 10, 21, 14, 30), 40000, 'CARD');
    await sale('y', DateTime(2026, 10, 20, 11), 50000, 'CASH');

    final s = await ReportService(db)
        .getDashboardSummary(actorId: 'owner', now: now);

    expect(s.current.totalSalesCount, 2);
    expect(s.current.netSales.millimes, 100000);
    expect(s.previous.netSales.millimes, 50000);
    expect(s.averageBasket.millimes, 50000);
    expect(s.current.salesByPaymentMethod['CARD']!.millimes, 40000);

    final hours = {for (final b in s.buckets) b.label: b.millimes};
    expect(hours['09h'], 60000);
    expect(hours['14h'], 40000);
    expect(hours['08h'], 0);

    expect(s.recent.first.receiptNumber, 'R-b');
    expect(s.recent.first.itemCount, 2);
    expect(s.recent.first.paymentMethod, 'CARD');
  });

  test('requires the view-reports permission', () async {
    expect(
      ReportService(db).getDashboardSummary(actorId: 'cash', now: now),
      throwsA(isA<AuthException>()),
    );
  });

  test('order details and dashboard rows carry product photos (variant, else product)', () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Chemise', createdAt: now, updatedAt: now,
        imageUrl: const Value('products/p1.jpg')));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p2', name: 'Jean', createdAt: now, updatedAt: now));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'va', productId: 'p1', sku: 'A', barcode: 'A', createdAt: now, updatedAt: now));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'vb', productId: 'p2', sku: 'B', barcode: 'B', createdAt: now, updatedAt: now,
        imageUrl: const Value('variants/vb.jpg')));

    await sale('o', DateTime(2026, 10, 21, 10), 60000, 'CASH');
    await (db.update(db.saleLines)..where((t) => t.saleId.equals('o')))
        .write(const SaleLinesCompanion(variantId: Value('va')));
    await db.into(db.saleLines).insert(SaleLinesCompanion.insert(
        id: 'l2', saleId: 'o', variantId: 'vb', productName: 'Jean',
        variantDescription: '', sku: 'B', barcode: 'B', quantity: 1,
        unitPriceMillimes: 1, originalPriceMillimes: 1, totalMillimes: 1));

    final svc = ReportService(db);
    final order = await svc.getOrderDetails(actorId: 'owner', saleId: 'o');
    expect(order.itemCount, 3);
    final byName = {for (final l in order.lines) l.line.productName: l.imageUrl};
    expect(byName['x'], 'products/p1.jpg'); // falls back to the product photo
    expect(byName['Jean'], 'variants/vb.jpg'); // variant photo wins

    final dash = await svc.getDashboardSummary(actorId: 'owner', now: now);
    expect(dash.recent.first.saleId, 'o');
    expect(dash.recent.first.imageUrls, containsAll(['products/p1.jpg', 'variants/vb.jpg']));

    expect(
      svc.getOrderDetails(actorId: 'cash', saleId: 'o'),
      throwsA(isA<AuthException>()),
    );
    expect(
      svc.getOrderDetails(actorId: 'owner', saleId: 'nope'),
      throwsA(isA<ValidationException>()),
    );
  });
}
