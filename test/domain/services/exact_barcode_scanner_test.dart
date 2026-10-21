import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'package:jazzpos/providers/cart_provider.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late SaleService saleService;
  late CatalogService catalogService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    saleService = SaleService(db, inventoryService);
    catalogService = CatalogService(db, inventoryService);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    final storeId = IdGenerator.uuid();
    final categoryId = IdGenerator.uuid();

    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Test Retail',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.stores).insert(
      StoresCompanion.insert(
        id: storeId,
        companyId: companyId,
        name: 'Test Store',
        code: 'TST-01',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: categoryId,
        name: 'Vêtements',
      ),
    );

    // Product 1: "Chemise Blanche" with barcode "00123" and SKU "CHM-001"
    final p1Id = IdGenerator.uuid();
    final v1Id = IdGenerator.uuid();
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: p1Id,
        categoryId: Value(categoryId),
        name: 'Chemise Blanche',
        defaultPriceMillimes: const Value(35000),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: v1Id,
        productId: p1Id,
        sku: 'CHM-001',
        barcode: '00123',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Product 2: "Pantalon Noir" with barcode "123" and SKU "SKU-123-OTHER"
    final p2Id = IdGenerator.uuid();
    final v2Id = IdGenerator.uuid();
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: p2Id,
        categoryId: Value(categoryId),
        name: 'Pantalon Noir',
        defaultPriceMillimes: const Value(55000),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: v2Id,
        productId: p2Id,
        sku: 'SKU-123-OTHER',
        barcode: '123',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Alias for Product 1: alias barcode "ALIAS-00123"
    await db.into(db.barcodeAliases).insert(
      BarcodeAliasesCompanion.insert(
        id: IdGenerator.uuid(),
        variantId: v1Id,
        barcode: 'ALIAS-00123',
        createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Exact Barcode Scanner Lookup Tests', () {
    test('Exact primary barcode match returns the correct variant', () async {
      final res = await catalogService.findVariantByExactBarcode('00123');
      expect(res, isNotNull);
      expect(res!.productName, 'Chemise Blanche');
      expect(res.barcode, '00123');
      expect(res.sku, 'CHM-001');
    });

    test('Preserves leading zeros: "00123" is distinct from "123"', () async {
      final resWithLeadingZeros = await catalogService.findVariantByExactBarcode('00123');
      expect(resWithLeadingZeros, isNotNull);
      expect(resWithLeadingZeros!.productName, 'Chemise Blanche');
      expect(resWithLeadingZeros.barcode, '00123');

      final resWithoutLeadingZeros = await catalogService.findVariantByExactBarcode('123');
      expect(resWithoutLeadingZeros, isNotNull);
      expect(resWithoutLeadingZeros!.productName, 'Pantalon Noir');
      expect(resWithoutLeadingZeros.barcode, '123');
    });

    test('Exact barcode alias lookup finds corresponding variant', () async {
      final res = await catalogService.findVariantByExactBarcode('ALIAS-00123');
      expect(res, isNotNull);
      expect(res!.productName, 'Chemise Blanche');
      expect(res.sku, 'CHM-001');
    });

    test('Exact SKU match returns variant if input matches SKU exactly', () async {
      final res = await catalogService.findVariantByExactBarcode('CHM-001');
      expect(res, isNotNull);
      expect(res!.productName, 'Chemise Blanche');
    });

    test('Partial SKU substring does NEVER match', () async {
      // "123" exists inside "SKU-123-OTHER", but scanning "SKU-123" must return null
      final partial = await catalogService.findVariantByExactBarcode('SKU-123');
      expect(partial, isNull);

      final partialChm = await catalogService.findVariantByExactBarcode('CHM');
      expect(partialChm, isNull);
    });

    test('Product name NEVER matches scanner input', () async {
      final byName = await catalogService.findVariantByExactBarcode('Chemise');
      expect(byName, isNull);

      final byExactName = await catalogService.findVariantByExactBarcode('Chemise Blanche');
      expect(byExactName, isNull);
    });

    test('Unknown random barcode returns null', () async {
      final unknown = await catalogService.findVariantByExactBarcode('9999999999999');
      expect(unknown, isNull);
    });

    test('Whitespace-padded barcode is trimmed cleanly before exact lookup', () async {
      final res = await catalogService.findVariantByExactBarcode('  00123\n');
      expect(res, isNotNull);
      expect(res!.productName, 'Chemise Blanche');
    });
  });

  group('Cart Locking During Payment / Modals', () {
    test('Locked cart rejects addItem, updateQuantity, and clearCart', () {
      final notifier = CartNotifier(catalogService, saleService);

      const itemVariant = VariantSearchResult(
        variantId: 'v1',
        productId: 'p1',
        productName: 'Article Test',
        variantDescription: 'Standard',
        barcode: '123456',
        sku: 'SKU-1',
        costPrice: Money.fromMillimes(5000),
        salePrice: Money.fromMillimes(10000),
        taxRatePercent: 19.0,
        stock: 10,
      );

      // Add item while unlocked
      notifier.addItem(itemVariant);
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items.first.quantity, 1);

      // Lock the cart (e.g. payment dialog opened)
      notifier.lockCart();
      expect(notifier.state.isLocked, isTrue);

      // Attempt to add another item
      notifier.addItem(itemVariant);
      expect(notifier.state.items.first.quantity, 1, reason: 'Quantity must not increase while locked');

      // Attempt to update quantity
      notifier.updateQuantity('v1', 5);
      expect(notifier.state.items.first.quantity, 1, reason: 'Quantity update must be ignored while locked');

      // Attempt to clear cart
      notifier.clearCart();
      expect(notifier.state.items.length, 1, reason: 'Clear cart must be rejected while locked');

      // Unlock the cart (e.g. payment dialog cancelled)
      notifier.unlockCart();
      expect(notifier.state.isLocked, isFalse);

      // Modifications work again
      notifier.updateQuantity('v1', 3);
      expect(notifier.state.items.first.quantity, 3);
      notifier.clearCart();
      expect(notifier.state.items.isEmpty, isTrue);
    });
  });
}
