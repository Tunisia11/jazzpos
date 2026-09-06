import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late CatalogService catalogService;
  late SaleService saleService;

  late String storeId;
  late String locationId;
  late String registerId;
  late String shiftId;
  late String cashierId;
  late String productId;
  late String variantId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    catalogService = CatalogService(db, inventoryService);
    saleService = SaleService(db, inventoryService);

    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    locationId = IdGenerator.uuid();
    registerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();
    shiftId = IdGenerator.uuid();

    // 1. Seed Company, Store, Location, Register, User, Shift
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Jazz Retail SARL',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db
        .into(db.stores)
        .insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            name: 'Tunis Mall Store',
            code: 'TM-01',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db
        .into(db.stockLocations)
        .insert(
          StockLocationsCompanion.insert(
            id: locationId,
            storeId: storeId,
            name: 'Shop Floor',
            code: 'SHOP',
            locationType: AppConstants.locationShopFloor,
            isDefault: const drift.Value(true),
          ),
        );

    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: cashierId,
            username: 'admin',
            displayName: 'Proprietaire',
            role: AppRoles.owner,
            pinHash: 'hash',
            pinSalt: 'salt',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db
        .into(db.registers)
        .insert(
          RegistersCompanion.insert(
            id: registerId,
            storeId: storeId,
            name: 'Caisse 1',
            code: 'REG-01',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: shiftId,
            registerId: registerId,
            cashierId: cashierId,
            openedAt: now,
          ),
        );

    // 2. Seed initial Product and Variant with 10 stock
    variantId = IdGenerator.uuid();
    productId = await catalogService.createProductWithMatrix(
      name: 'Chemise Slim Fit',
      defaultCost: Money.fromTnd(35.0),
      defaultPrice: Money.fromTnd(79.0),
      variants: [
        MatrixVariantItem(
          id: variantId,
          selectedAttributes: const {},
          sku: 'CHM-SLIM-M',
          barcode: '1234567890123',
          costPrice: Money.fromTnd(35.0),
          salePrice: Money.fromTnd(79.0),
          initialStock: 10,
          minStockAlert: 3,
        ),
      ],
      actorId: cashierId,
      storeId: storeId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Product Management & Audit Integrity', () {
    test(
      'Editing product details without changing stock creates NO stock movements',
      () async {
        final initialMovements = await (db.select(
          db.stockMovements,
        )..where((tbl) => tbl.variantId.equals(variantId))).get();
        final initialCount = initialMovements.length;

        // Update name, price and min stock, but keep stock at 10
        await catalogService.updateProductFull(
          productId: productId,
          variantId: variantId,
          name: 'Chemise Slim Fit Blanche',
          sku: 'CHM-SLIM-M',
          barcode: '1234567890123',
          sizeOrVariant: 'M',
          salePrice: Money.fromTnd(89.0),
          costPrice: Money.fromTnd(40.0),
          newStock: 10, // Unchanged!
          minStockAlert: 4,
          actorId: cashierId,
          locationId: locationId,
        );

        final updatedProduct = await (db.select(
          db.products,
        )..where((tbl) => tbl.id.equals(productId))).getSingle();
        expect(updatedProduct.name, equals('Chemise Slim Fit Blanche'));

        final updatedVariant = await (db.select(
          db.productVariants,
        )..where((tbl) => tbl.id.equals(variantId))).getSingle();
        expect(updatedVariant.salePriceOverrideMillimes, equals(89000));
        expect(updatedVariant.minStockAlert, equals(4));

        // Movements count must be unchanged!
        final movementsAfter = await (db.select(
          db.stockMovements,
        )..where((tbl) => tbl.variantId.equals(variantId))).get();
        expect(movementsAfter.length, equals(initialCount));

        // But a price history record must be created
        final priceHistories = await (db.select(
          db.priceHistories,
        )..where((tbl) => tbl.variantId.equals(variantId))).get();
        expect(priceHistories.length, equals(1));
        expect(priceHistories.first.newPriceMillimes, equals(89000));
      },
    );

    test(
      'Editing stock quantity manually MUST create an audited stock movement',
      () async {
        final initialStock = await inventoryService.getStock(
          variantId,
          locationId: locationId,
        );
        expect(initialStock, equals(10));

        // Manually adjust stock from 10 to 18 (+8)
        await catalogService.updateProductFull(
          productId: productId,
          variantId: variantId,
          name: 'Chemise Slim Fit',
          sku: 'CHM-SLIM-M',
          barcode: '1234567890123',
          sizeOrVariant: 'M',
          salePrice: Money.fromTnd(79.0),
          costPrice: Money.fromTnd(35.0),
          newStock: 18,
          minStockAlert: 3,
          actorId: cashierId,
          locationId: locationId,
          stockAdjustmentReason: 'Inventaire physique de contrôle',
        );

        // Verify stock level updated
        final newStock = await inventoryService.getStock(
          variantId,
          locationId: locationId,
        );
        expect(newStock, equals(18));

        // Verify stock movement ledger
        final adjustmentMovements =
            await (db.select(db.stockMovements)..where(
                  (tbl) =>
                      tbl.variantId.equals(variantId) &
                      tbl.movementType.equals(
                        AppConstants.movementManualAdjustment,
                      ),
                ))
                .get();

        expect(adjustmentMovements.length, equals(1));
        final movement = adjustmentMovements.first;
        expect(movement.quantityDelta, equals(8));
        expect(movement.reason, contains('Inventaire physique de contrôle'));
        expect(movement.actorId, equals(cashierId));

        // Verify audit event
        final auditEvents =
            await (db.select(db.auditEvents)..where(
                  (tbl) =>
                      tbl.action.equals('STOCK_MANUAL_ADJUSTMENT') &
                      tbl.entityId.equals(variantId),
                ))
                .get();
        expect(auditEvents.length, equals(1));
        expect(auditEvents.first.detailsJson, contains('"oldStock":10'));
        expect(auditEvents.first.detailsJson, contains('"newStock":18'));
      },
    );

    test('SKU and barcode uniqueness validation during edit', () async {
      // Create a second product
      final secondVariantId = IdGenerator.uuid();
      await catalogService.createProductWithMatrix(
        name: 'Pantalon Chino',
        defaultCost: Money.fromTnd(30.0),
        defaultPrice: Money.fromTnd(65.0),
        variants: [
          MatrixVariantItem(
            id: secondVariantId,
            selectedAttributes: const {},
            sku: 'PNT-CHINO-40',
            barcode: '9999999999999',
            costPrice: Money.fromTnd(30.0),
            salePrice: Money.fromTnd(65.0),
            initialStock: 5,
          ),
        ],
        actorId: cashierId,
        storeId: storeId,
      );

      // Try to edit the second product with first product's SKU
      expect(
        () => catalogService.updateProductFull(
          productId: productId,
          variantId: secondVariantId,
          name: 'Pantalon Chino',
          sku: 'CHM-SLIM-M', // Duplicate SKU!
          barcode: '9999999999999',
          salePrice: Money.fromTnd(65.0),
          costPrice: Money.fromTnd(30.0),
          newStock: 5,
          minStockAlert: 2,
          actorId: cashierId,
        ),
        throwsA(isA<DuplicateException>()),
      );

      // Try to edit with first product's Barcode
      expect(
        () => catalogService.updateProductFull(
          productId: productId,
          variantId: secondVariantId,
          name: 'Pantalon Chino',
          sku: 'PNT-CHINO-40',
          barcode: '1234567890123', // Duplicate Barcode!
          salePrice: Money.fromTnd(65.0),
          costPrice: Money.fromTnd(30.0),
          newStock: 5,
          minStockAlert: 2,
          actorId: cashierId,
        ),
        throwsA(isA<DuplicateException>()),
      );
    });

    test(
      'Soft-delete hides product from search & inventory while protecting historical sales',
      () async {
        // 1. Perform a sale of the product before deleting
        final cartItem = CartItem(
          variantId: variantId,
          productId: productId,
          productName: 'Chemise Slim Fit',
          variantDescription: 'M',
          sku: 'CHM-SLIM-M',
          barcode: '1234567890123',
          unitPrice: Money.fromTnd(79.0),
          originalPrice: Money.fromTnd(79.0),
          unitCost: Money.fromTnd(35.0),
          quantity: 2,
        );

        final checkoutResult = await saleService.checkout(
          CheckoutRequest(
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            items: [cartItem],
            payments: [
              PaymentSplit(
                method: AppConstants.paymentCash,
                amount: Money.fromTnd(158.0),
                tendered: Money.fromTnd(160.0),
                change: Money.fromTnd(2.0),
              ),
            ],
            idempotencyKey: 'IDEMP-DEL-TEST-001',
          ),
        );
        final saleId = checkoutResult.sale.id;
        expect(saleId, isNotEmpty);

        // Verify product is currently found in active variants
        var searchResults = await catalogService.searchVariants('Chemise');
        expect(searchResults.any((v) => v.variantId == variantId), isTrue);

        var allActive = await catalogService.getAllActiveVariants();
        expect(allActive.any((v) => v.variantId == variantId), isTrue);

        // 2. Soft-delete the product
        await catalogService.softDeleteProduct(
          productId: productId,
          variantId: variantId,
          actorId: cashierId,
        );

        // Verify product status is ARCHIVED and deletedAt is set
        final deletedProduct = await (db.select(
          db.products,
        )..where((tbl) => tbl.id.equals(productId))).getSingle();
        expect(deletedProduct.status, equals('ARCHIVED'));
        expect(deletedProduct.deletedAt, isNotNull);

        final deletedVariant = await (db.select(
          db.productVariants,
        )..where((tbl) => tbl.id.equals(variantId))).getSingle();
        expect(deletedVariant.isActive, isFalse);
        expect(deletedVariant.deletedAt, isNotNull);

        // 3. Verify it NO LONGER appears in active search or catalog
        searchResults = await catalogService.searchVariants('Chemise');
        expect(searchResults.any((v) => v.variantId == variantId), isFalse);

        allActive = await catalogService.getAllActiveVariants();
        expect(allActive.any((v) => v.variantId == variantId), isFalse);

        // 4. CRITICAL: Historical sale record and line items remain 100% intact!
        final sale = await (db.select(
          db.sales,
        )..where((tbl) => tbl.id.equals(saleId))).getSingle();
        expect(sale.totalMillimes, equals(158000));

        final lines = await (db.select(
          db.saleLines,
        )..where((tbl) => tbl.saleId.equals(saleId))).get();
        expect(lines.length, equals(1));
        final line = lines.first;
        expect(line.variantId, equals(variantId));
        expect(line.productName, equals('Chemise Slim Fit'));
        expect(line.sku, equals('CHM-SLIM-M'));
        expect(line.quantity, equals(2));
        expect(line.totalMillimes, equals(158000));

        // Verify stock movements from the sale are intact
        final movements = await (db.select(
          db.stockMovements,
        )..where((tbl) => tbl.referenceId.equals(saleId))).get();
        expect(movements.length, equals(1));
        expect(movements.first.quantityDelta, equals(-2));
      },
    );

    test('Updating product image stores path and logs audit', () async {
      const testImagePath = '/data/images/prod_test_123.jpg';
      await catalogService.updateProductImage(
        productId: productId,
        variantId: variantId,
        imageUrl: testImagePath,
        actorId: cashierId,
      );

      final prod = await (db.select(
        db.products,
      )..where((tbl) => tbl.id.equals(productId))).getSingle();
      expect(prod.imageUrl, equals(testImagePath));

      final variant = await (db.select(
        db.productVariants,
      )..where((tbl) => tbl.id.equals(variantId))).getSingle();
      expect(variant.imageUrl, equals(testImagePath));

      final search = await catalogService.searchVariants('Chemise');
      expect(search.first.imageUrl, equals(testImagePath));
    });
  });
}
