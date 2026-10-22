import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/catalog_service.dart';
import 'package:tracepos/domain/services/inventory_service.dart';
import 'package:tracepos/domain/services/sale_service.dart';
import 'package:tracepos/providers/cart_provider.dart';

VariantSearchResult _variant(int stock) => VariantSearchResult(
      variantId: 'v1',
      productId: 'p1',
      productName: 'Tshirt',
      variantDescription: 'Standard',
      sku: 'HAUT-1',
      barcode: '123',
      salePrice: const Money.fromMillimes(69000),
      costPrice: Money.zero,
      stock: stock,
      taxRatePercent: 19,
    );

void main() {
  late AppDatabase db;
  late SaleService sales;
  late CartNotifier cart;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final inv = InventoryService(db);
    sales = SaleService(db, inv);
    final now = DateTime(2026);
    await db.into(db.users).insert(UsersCompanion.insert(
        id: 'owner', username: 'o', displayName: 'O', role: AppRoles.owner,
        pinHash: 'h', pinSalt: 's', createdAt: now, updatedAt: now));
    await db.into(db.users).insert(UsersCompanion.insert(
        id: 'cash', username: 'c', displayName: 'C', role: AppRoles.cashier,
        pinHash: 'h', pinSalt: 's', createdAt: now, updatedAt: now));
    cart = CartNotifier(CatalogService(db, inv), sales);
    await cart.reloadStockPolicy();
  });
  tearDown(() => db.close());

  test('default policy blocks adding more than the stock on hand', () {
    expect(cart.addItem(_variant(2)), isTrue);
    expect(cart.addItem(_variant(2)), isTrue);
    expect(cart.state.items.single.quantity, 2);

    expect(cart.addItem(_variant(2)), isFalse);
    expect(cart.state.items.single.quantity, 2);
    expect(cart.state.stockNotice, contains('Stock insuffisant'));
  });

  test('zero or negative stock cannot be sold', () {
    expect(cart.addItem(_variant(0)), isFalse);
    expect(cart.addItem(_variant(-1)), isFalse);
    expect(cart.state.items, isEmpty);
    expect(cart.state.stockNotice, contains('0 disponible'));
  });

  test('quantity stepper is also limited by stock', () {
    cart.addItem(_variant(3));
    cart.updateQuantity('v1', 5);
    expect(cart.state.items.single.quantity, 1);
    expect(cart.state.stockNotice, isNotNull);
    cart.updateQuantity('v1', 3);
    expect(cart.state.items.single.quantity, 3);
    expect(cart.state.stockNotice, isNull);
  });

  test('WARN policy lets the sale through with a warning', () async {
    await sales.setNegativeStockPolicy(AppConstants.negativeStockWarn, actorId: 'owner');
    await cart.reloadStockPolicy();

    expect(cart.addItem(_variant(0)), isTrue);
    expect(cart.state.items.single.quantity, 1);
    expect(cart.state.stockNotice, startsWith('Attention'));
  });

  test('policy defaults to BLOCK and only settings managers can change it', () async {
    expect(await sales.getNegativeStockPolicy(), AppConstants.negativeStockBlock);
    await expectLater(
      sales.setNegativeStockPolicy(AppConstants.negativeStockWarn, actorId: 'cash'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      sales.setNegativeStockPolicy('NOPE', actorId: 'owner'),
      throwsA(isA<ValidationException>()),
    );
    expect(await sales.getNegativeStockPolicy(), AppConstants.negativeStockBlock);
  });
}
