import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/core/utils/password_hasher.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/cart_item.dart';
import 'package:jazzpos/domain/models/checkout_request.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/domain/services/auth_service.dart';
import 'package:jazzpos/domain/services/backup_service.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';
import 'package:jazzpos/domain/services/exchange_service.dart';
import 'package:jazzpos/domain/services/inventory_count_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/domain/services/purchase_service.dart';
import 'package:jazzpos/domain/services/return_service.dart';
import 'package:jazzpos/domain/services/sale_service.dart';
import 'package:jazzpos/domain/services/shift_service.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/hardware/label_printer/tspl_commands.dart';
import 'package:jazzpos/hardware/receipt_printer/esc_pos_commands.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late CatalogService catalogService;
  late SaleService saleService;
  late ReturnService returnService;
  late ExchangeService exchangeService;
  late ShiftService shiftService;
  late PurchaseService purchaseService;
  late InventoryCountService inventoryCountService;
  late AuthService authService;
  late DatabaseIntegrityService integrityService;
  late BackupService backupService;

  late String companyId;
  late String storeId;
  late String registerId;
  late String ownerId;
  late String managerId;
  late String cashierId;
  late StockLocation shopFloor;
  late StockLocation damagedLoc;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    catalogService = CatalogService(db, inventoryService);
    saleService = SaleService(db, inventoryService);
    returnService = ReturnService(db, inventoryService);
    exchangeService = ExchangeService(db, returnService, saleService);
    shiftService = ShiftService(db);
    purchaseService = PurchaseService(db, inventoryService);
    inventoryCountService = InventoryCountService(db, inventoryService);
    authService = AuthService(db);
    integrityService = DatabaseIntegrityService(db);
    backupService = BackupService(db);

    final now = DateTime.now();
    companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    registerId = 'REG-01';
    ownerId = IdGenerator.uuid();
    managerId = IdGenerator.uuid();
    cashierId = IdGenerator.uuid();

    // 1. Seed Company
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

    // 2. Seed Store
    await db
        .into(db.stores)
        .insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            name: 'Jazz Tunis Mall Flagship',
            code: 'TM-01',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 3. Seed Register
    await db
        .into(db.registers)
        .insert(
          RegistersCompanion.insert(
            id: registerId,
            storeId: storeId,
            name: 'Caisse Principale',
            code: 'REG-01',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 4. Seed Stock Locations
    shopFloor = await inventoryService.getDefaultLocation(storeId);

    final dmgId = IdGenerator.uuid();
    await db
        .into(db.stockLocations)
        .insert(
          StockLocationsCompanion.insert(
            id: dmgId,
            storeId: storeId,
            name: 'Damaged Items',
            code: 'DMG',
            locationType: AppConstants.locationDamaged,
            isDefault: const Value(false),
          ),
        );
    damagedLoc = await (db.select(
      db.stockLocations,
    )..where((tbl) => tbl.id.equals(dmgId))).getSingle();

    // 5. Seed Users with Salted Hashes
    final ownerSalt = PasswordHasher.generateSalt();
    final ownerHash = PasswordHasher.hashPin('9999', ownerSalt);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: ownerId,
            username: 'owner',
            displayName: 'Mohamed Jazz Owner',
            pinHash: ownerHash,
            pinSalt: ownerSalt,
            role: AppRoles.owner,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final mgrSalt = PasswordHasher.generateSalt();
    final mgrHash = PasswordHasher.hashPin('1234', mgrSalt);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: managerId,
            username: 'manager1',
            displayName: 'Fatma Responsable',
            pinHash: mgrHash,
            pinSalt: mgrSalt,
            role: AppRoles.manager,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final cashSalt = PasswordHasher.generateSalt();
    final cashHash = PasswordHasher.hashPin('0000', cashSalt);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: cashierId,
            username: 'cashier1',
            displayName: 'Ahmed Caissier',
            pinHash: cashHash,
            pinSalt: cashSalt,
            role: AppRoles.cashier,
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('1. Authentication & Cryptographic Security QA', () {
    test(
      '1.1 Salt generation produces unique cryptographically random 32-byte hex strings',
      () {
        final salt1 = PasswordHasher.generateSalt();
        final salt2 = PasswordHasher.generateSalt();
        expect(salt1, isNot(equals(salt2)));
        expect(salt1.length, equals(64)); // 32 bytes in hex = 64 chars
      },
    );

    test(
      '1.2 PasswordHasher verifyPin uses constant-time comparison and rejects bad PIN',
      () {
        final salt = PasswordHasher.generateSalt();
        final hash = PasswordHasher.hashPin('5555', salt);

        expect(
          PasswordHasher.verifyPin(
            pin: '5555',
            saltHex: salt,
            expectedHashHex: hash,
          ),
          isTrue,
        );
        expect(
          PasswordHasher.verifyPin(
            pin: '5554',
            saltHex: salt,
            expectedHashHex: hash,
          ),
          isFalse,
        );
        expect(
          PasswordHasher.verifyPin(
            pin: '',
            saltHex: salt,
            expectedHashHex: hash,
          ),
          isFalse,
        );
      },
    );

    test(
      '1.3 AuthService login succeeds for valid credentials and initializes session permissions',
      () async {
        final session = await authService.login(
          username: 'manager1',
          pin: '1234',
        );
        expect(session.user.id, equals(managerId));
        expect(session.user.role, equals(AppRoles.manager));
        expect(session.hasPermission(AppPermissions.viewReports), isTrue);
        expect(session.hasPermission(AppPermissions.manageInventory), isTrue);
      },
    );

    test(
      '1.4 AuthService login fails for incorrect PIN with AuthException',
      () async {
        expect(
          () => authService.login(username: 'manager1', pin: '9999'),
          throwsA(isA<AuthException>()),
        );
      },
    );

    test(
      '1.5 Manager override allows Manager and Owner PIN, but rejects Cashier PIN',
      () async {
        final mgr = await authService.verifyManagerOverride('1234');
        expect(mgr.role, equals(AppRoles.manager));

        final owner = await authService.verifyManagerOverride('9999');
        expect(owner.role, equals(AppRoles.owner));

        expect(
          () => authService.verifyManagerOverride('0000'), // Cashier PIN
          throwsA(isA<AuthException>()),
        );
      },
    );
  });

  group('2. Shift Lifecycle & Cash Drawer Accounting QA', () {
    test(
      '2.1 Open shift with standard float (150.000 TND) creates OPEN shift',
      () async {
        final shift = await shiftService.openShift(
          registerId: registerId,
          cashierId: cashierId,
          openingCash: Money.fromTnd(150.000),
        );

        expect(shift.status, equals(AppConstants.shiftOpen));
        expect(shift.openingCashMillimes, equals(150000));
      },
    );

    test('2.2 Open shift allows zero float (0.000 TND)', () async {
      final shift = await shiftService.openShift(
        registerId: registerId,
        cashierId: cashierId,
        openingCash: Money.zero,
      );
      expect(shift.openingCashMillimes, equals(0));
    });

    test(
      '2.3 Open shift rejects negative float with ValidationException',
      () async {
        expect(
          () => shiftService.openShift(
            registerId: registerId,
            cashierId: cashierId,
            openingCash: Money.fromMillimes(-5000),
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test(
      '2.4 Open shift rejects second concurrent open shift on same register',
      () async {
        await shiftService.openShift(
          registerId: registerId,
          cashierId: cashierId,
          openingCash: Money.fromTnd(100.000),
        );

        expect(
          () => shiftService.openShift(
            registerId: registerId,
            cashierId: cashierId,
            openingCash: Money.fromTnd(100.000),
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test(
      '2.5 Cash pay-in and pay-out movements track expected drawer balance',
      () async {
        final shift = await shiftService.openShift(
          registerId: registerId,
          cashierId: cashierId,
          openingCash: Money.fromTnd(100.000),
        );

        await shiftService.recordCashMovement(
          shiftId: shift.id,
          userId: managerId,
          type: 'PAY_IN',
          amount: Money.fromTnd(50.000),
          reason: 'Monnaie d\'appoint',
        );

        await shiftService.recordCashMovement(
          shiftId: shift.id,
          userId: managerId,
          type: 'PAY_OUT',
          amount: Money.fromTnd(20.000),
          reason: 'Achat fournitures caisse',
        );

        final summary = await shiftService.closeShift(
          shiftId: shift.id,
          cashierId: cashierId,
          countedCash: Money.fromTnd(130.000), // Expected: 100 + 50 - 20 = 130
        );

        expect(summary.shift.status, equals(AppConstants.shiftClosed));
        expect(summary.difference?.millimes, equals(0));
      },
    );

    test(
      '2.6 Shift close calculates discrepancy correctly on cash overage and shortage',
      () async {
        final shift = await shiftService.openShift(
          registerId: registerId,
          cashierId: cashierId,
          openingCash: Money.fromTnd(200.000),
        );

        // Actual cash 195.000 (shortage of 5.000 TND)
        final summary = await shiftService.closeShift(
          shiftId: shift.id,
          cashierId: cashierId,
          countedCash: Money.fromTnd(195.000),
          note: 'Perte de monnaie',
        );

        expect(summary.difference?.millimes, equals(-5000));
      },
    );

    test(
      '2.7 Shift double-close is rejected with ValidationException',
      () async {
        final shift = await shiftService.openShift(
          registerId: registerId,
          cashierId: cashierId,
          openingCash: Money.fromTnd(100.000),
        );

        await shiftService.closeShift(
          shiftId: shift.id,
          cashierId: cashierId,
          countedCash: Money.fromTnd(100.000),
        );

        expect(
          () => shiftService.closeShift(
            shiftId: shift.id,
            cashierId: cashierId,
            countedCash: Money.fromTnd(100.000),
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );
  });

  group('3. Clothing Matrix Catalog & Variant Integrity QA', () {
    test(
      '3.1 Create 3 Colors x 4 Sizes = 12 Variant Clothing Matrix with stock',
      () async {
        final brandId = IdGenerator.uuid();
        await db
            .into(db.brands)
            .insert(
              BrandsCompanion.insert(id: brandId, name: 'Jazz Collection'),
            );

        final catId = IdGenerator.uuid();
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(id: catId, name: 'Chemises Homme'),
            );

        final colorTypeId = IdGenerator.uuid();
        await db
            .into(db.attributeTypes)
            .insert(
              AttributeTypesCompanion.insert(
                id: colorTypeId,
                name: 'Couleur',
                code: 'COLOR',
              ),
            );

        final sizeTypeId = IdGenerator.uuid();
        await db
            .into(db.attributeTypes)
            .insert(
              AttributeTypesCompanion.insert(
                id: sizeTypeId,
                name: 'Taille',
                code: 'SIZE',
              ),
            );

        final colors = [
          (name: 'Blanc', code: 'WHT'),
          (name: 'Noir', code: 'BLK'),
          (name: 'Bleu Ciel', code: 'BLU'),
        ];
        final colorVals = <MatrixAttributeValue>[];
        for (final c in colors) {
          final id = IdGenerator.uuid();
          await db
              .into(db.attributeValues)
              .insert(
                AttributeValuesCompanion.insert(
                  id: id,
                  attributeTypeId: colorTypeId,
                  value: c.name,
                  code: c.code,
                ),
              );
          colorVals.add(
            MatrixAttributeValue(id: id, value: c.name, code: c.code),
          );
        }

        final sizes = [
          (name: 'S', code: 'S'),
          (name: 'M', code: 'M'),
          (name: 'L', code: 'L'),
          (name: 'XL', code: 'XL'),
        ];
        final sizeVals = <MatrixAttributeValue>[];
        for (final s in sizes) {
          final id = IdGenerator.uuid();
          await db
              .into(db.attributeValues)
              .insert(
                AttributeValuesCompanion.insert(
                  id: id,
                  attributeTypeId: sizeTypeId,
                  value: s.name,
                  code: s.code,
                ),
              );
          sizeVals.add(
            MatrixAttributeValue(id: id, value: s.name, code: s.code),
          );
        }

        final matrixItems = VariantMatrixGenerator.generateMatrix(
          productCode: 'CHM',
          attributes: [
            MatrixAttribute(
              attributeTypeId: colorTypeId,
              attributeTypeName: 'Couleur',
              selectedValues: colorVals,
            ),
            MatrixAttribute(
              attributeTypeId: sizeTypeId,
              attributeTypeName: 'Taille',
              selectedValues: sizeVals,
            ),
          ],
          defaultCost: Money.fromTnd(25.000),
          defaultPrice: Money.fromTnd(59.900),
        );

        expect(matrixItems.length, equals(12));
        for (final item in matrixItems) {
          item.initialStock = 5;
        }

        final productId = await catalogService.createProductWithMatrix(
          name: 'Chemise Oxford Slim Fit',
          brandId: brandId,
          categoryId: catId,
          defaultCost: Money.fromTnd(25.000),
          defaultPrice: Money.fromTnd(59.900),
          taxRatePercent: 19.0,
          variants: matrixItems,
          storeId: storeId,
          actorId: managerId,
        );

        final prod = await (db.select(
          db.products,
        )..where((t) => t.id.equals(productId))).getSingle();
        expect(prod.name, equals('Chemise Oxford Slim Fit'));

        final variantsInDb = await (db.select(
          db.productVariants,
        )..where((t) => t.productId.equals(productId))).get();
        expect(variantsInDb.length, equals(12));

        int totalStock = 0;
        for (final v in variantsInDb) {
          final stock = await inventoryService.getStock(
            v.id,
            locationId: shopFloor.id,
          );
          totalStock += stock;
        }
        expect(totalStock, equals(60));
      },
    );

    test(
      '3.2 Reject duplicate SKU across variants with DuplicateException',
      () async {
        final sku = 'PANTS-JEAN-32';
        final barcode1 = '619999999001';
        final barcode2 = '619999999002';

        final matrixItems = [
          MatrixVariantItem(
            id: IdGenerator.uuid(),
            sku: sku,
            barcode: barcode1,
            selectedAttributes: {},
            costPrice: Money.fromTnd(20.000),
            salePrice: Money.fromTnd(49.000),
            isEnabled: true,
          ),
          MatrixVariantItem(
            id: IdGenerator.uuid(),
            sku: sku, // Duplicate SKU!
            barcode: barcode2,
            selectedAttributes: {},
            costPrice: Money.fromTnd(20.000),
            salePrice: Money.fromTnd(49.000),
            isEnabled: true,
          ),
        ];

        expect(
          () => catalogService.createProductWithMatrix(
            name: 'Jean Denim',
            defaultCost: Money.fromTnd(20.000),
            defaultPrice: Money.fromTnd(49.000),
            taxRatePercent: 19.0,
            variants: matrixItems,
            storeId: storeId,
            actorId: managerId,
          ),
          throwsA(isA<DuplicateException>()),
        );
      },
    );

    test(
      '3.3 Multi-tier search finds variant by exact barcode, SKU, and name',
      () async {
        final prodId = IdGenerator.uuid();
        final varId = IdGenerator.uuid();
        final barcode = '619777888999';
        final sku = 'BLAZER-NAVY-50';

        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: prodId,
                name: 'Veste Blazer Laine',
                defaultCostMillimes: const Value(80000),
                defaultPriceMillimes: const Value(199000),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                id: varId,
                productId: prodId,
                sku: sku,
                barcode: barcode,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        final byBarcode = await catalogService.searchVariants(barcode);
        expect(byBarcode.length, equals(1));
        expect(byBarcode.first.variantId, equals(varId));

        final bySku = await catalogService.searchVariants('BLAZER');
        expect(bySku.any((r) => r.variantId == varId), isTrue);

        final byName = await catalogService.searchVariants('Veste Blazer');
        expect(byName.any((r) => r.variantId == varId), isTrue);
      },
    );
  });

  group('4. Checkout, Idempotency & Stock Concurrency QA', () {
    late String shiftId;
    late String testProductId;
    late String testVariantId;

    setUp(() async {
      final shift = await shiftService.openShift(
        registerId: registerId,
        cashierId: cashierId,
        openingCash: Money.fromTnd(100.000),
      );
      shiftId = shift.id;

      testProductId = IdGenerator.uuid();
      testVariantId = IdGenerator.uuid();

      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: testProductId,
              name: 'Polo Piqué Coton',
              defaultCostMillimes: const Value(15000),
              defaultPriceMillimes: const Value(45000),
              taxRatePercent: const Value(19.0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: testVariantId,
              productId: testProductId,
              sku: 'POLO-BLU-M',
              barcode: '619555111001',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Stock 10 units
      await inventoryService.recordMovement(
        variantId: testVariantId,
        movementType: AppConstants.movementInitial,
        quantityDelta: 10,
        toLocationId: shopFloor.id,
        actorId: managerId,
      );
    });

    test(
      '4.1 Standard cash checkout deducts stock, writes receipt, and logs audit',
      () async {
        final cart = <CartItem>[
          CartItem(
            variantId: testVariantId,
            productId: testProductId,
            productName: 'Polo Piqué Coton',
            variantDescription: 'Taille M - Bleu',
            sku: 'POLO-BLU-M',
            barcode: '619555111001',
            unitPrice: Money.fromTnd(45.000),
            originalPrice: Money.fromTnd(45.000),
            unitCost: Money.fromTnd(15.000),
            quantity: 2,
            taxRatePercent: 19.0,
          ),
        ];

        final request = CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: cart,
          payments: [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromTnd(90.000),
              tendered: Money.fromTnd(100.000),
              change: Money.fromTnd(10.000),
            ),
          ],
          idempotencyKey: 'SALE-IDEMP-01',
        );

        final result = await saleService.checkout(request);

        expect(result.sale.receiptNumber, startsWith('REC-'));
        expect(result.sale.totalMillimes, equals(90000));

        final remainingStock = await inventoryService.getStock(
          testVariantId,
          locationId: shopFloor.id,
        );
        expect(remainingStock, equals(8));
      },
    );

    test(
      '4.2 Idempotency key prevents double deduction on concurrent button double-click',
      () async {
        final cart = <CartItem>[
          CartItem(
            variantId: testVariantId,
            productId: testProductId,
            productName: 'Polo Piqué Coton',
            variantDescription: 'Taille M - Bleu',
            sku: 'POLO-BLU-M',
            barcode: '619555111001',
            unitPrice: Money.fromTnd(45.000),
            originalPrice: Money.fromTnd(45.000),
            unitCost: Money.fromTnd(15.000),
            quantity: 1,
          ),
        ];

        final request = CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: cart,
          payments: [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromTnd(45.000),
              tendered: Money.fromTnd(45.000),
              change: Money.zero,
            ),
          ],
          idempotencyKey: 'DOUBLE-CLICK-TOKEN',
        );

        final res1 = await saleService.checkout(request);
        final res2 = await saleService.checkout(request);

        expect(res1.sale.id, equals(res2.sale.id));

        final remainingStock = await inventoryService.getStock(
          testVariantId,
          locationId: shopFloor.id,
        );
        expect(remainingStock, equals(9));
      },
    );

    test(
      '4.3 Negative stock policy BLOCK strictly throws InsufficientStockException',
      () async {
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: AppConstants.keyNegativeStockPolicy,
                value: AppConstants.negativeStockBlock,
                updatedAt: DateTime.now(),
              ),
            );

        final cart = <CartItem>[
          CartItem(
            variantId: testVariantId,
            productId: testProductId,
            productName: 'Polo Piqué Coton',
            variantDescription: 'Taille M - Bleu',
            sku: 'POLO-BLU-M',
            barcode: '619555111001',
            unitPrice: Money.fromTnd(45.000),
            originalPrice: Money.fromTnd(45.000),
            unitCost: Money.fromTnd(15.000),
            quantity: 20, // Only 10 in stock!
          ),
        ];

        final request = CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: cart,
          payments: [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromTnd(900.000),
              tendered: Money.fromTnd(900.000),
              change: Money.zero,
            ),
          ],
          idempotencyKey: 'EXCEED-STOCK-01',
        );

        expect(
          () => saleService.checkout(request),
          throwsA(isA<InsufficientStockException>()),
        );
      },
    );
  });

  group('5. Returns & Exchange Cash Drawer Accounting QA', () {
    late String shiftId;
    late String prodId;
    late String variantA;
    late String variantB;
    late Sale originalSale;

    setUp(() async {
      final shift = await shiftService.openShift(
        registerId: registerId,
        cashierId: cashierId,
        openingCash: Money.fromTnd(200.000),
      );
      shiftId = shift.id;

      prodId = IdGenerator.uuid();
      variantA = IdGenerator.uuid();
      variantB = IdGenerator.uuid();

      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: prodId,
              name: 'Pull Col V Mérinos',
              defaultCostMillimes: const Value(20000),
              defaultPriceMillimes: const Value(50000),
              taxRatePercent: const Value(19.0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: variantA,
              productId: prodId,
              sku: 'PULL-M',
              barcode: '619111222001',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: variantB,
              productId: prodId,
              sku: 'PULL-L',
              barcode: '619111222002',
              salePriceOverrideMillimes: const Value(60000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await inventoryService.recordMovement(
        variantId: variantA,
        movementType: AppConstants.movementInitial,
        quantityDelta: 10,
        toLocationId: shopFloor.id,
        actorId: managerId,
      );
      await inventoryService.recordMovement(
        variantId: variantB,
        movementType: AppConstants.movementInitial,
        quantityDelta: 10,
        toLocationId: shopFloor.id,
        actorId: managerId,
      );

      final checkoutRes = await saleService.checkout(
        CheckoutRequest(
          storeId: storeId,
          registerId: registerId,
          shiftId: shiftId,
          cashierId: cashierId,
          items: [
            CartItem(
              variantId: variantA,
              productId: prodId,
              productName: 'Pull Col V Mérinos',
              variantDescription: 'Taille M',
              sku: 'PULL-M',
              barcode: '619111222001',
              unitPrice: Money.fromTnd(50.000),
              originalPrice: Money.fromTnd(50.000),
              unitCost: Money.fromTnd(20.000),
              quantity: 2,
            ),
          ],
          payments: [
            PaymentSplit(
              method: AppConstants.paymentCash,
              amount: Money.fromTnd(100.000),
              tendered: Money.fromTnd(100.000),
              change: Money.zero,
            ),
          ],
          idempotencyKey: 'ORIG-SALE-01',
        ),
      );
      originalSale = checkoutRes.sale;
    });

    test(
      '5.1 Partial return updates sale status to PARTIALLY_REFUNDED and restocks item',
      () async {
        final originalLines = await (db.select(
          db.saleLines,
        )..where((t) => t.saleId.equals(originalSale.id))).get();
        final lineToReturn = originalLines.first;

        final ret = await returnService.processReturn(
          ReturnRequest(
            originalSaleId: originalSale.id,
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            reason: 'Changement de taille souhaité',
            refundMethod: AppConstants.paymentCash,
            items: [
              ReturnLineItem(
                originalSaleLineId: lineToReturn.id,
                variantId: variantA,
                quantity: 1, // Returning 1 of 2
                refundUnitPrice: Money.fromTnd(50.000),
                condition: AppConstants.returnConditionSellable,
              ),
            ],
          ),
        );

        expect(ret.totalRefundMillimes, equals(50000));

        final updatedSale = await (db.select(
          db.sales,
        )..where((t) => t.id.equals(originalSale.id))).getSingle();
        expect(updatedSale.status, equals('PARTIALLY_REFUNDED'));

        final stockA = await inventoryService.getStock(
          variantA,
          locationId: shopFloor.id,
        );
        expect(stockA, equals(9));
      },
    );

    test(
      '5.2 Over-return and duplicate return are rejected with ValidationException',
      () async {
        final originalLines = await (db.select(
          db.saleLines,
        )..where((t) => t.saleId.equals(originalSale.id))).get();
        final lineToReturn = originalLines.first;

        // Attempt returning 3 units when only 2 were purchased
        expect(
          () => returnService.processReturn(
            ReturnRequest(
              originalSaleId: originalSale.id,
              storeId: storeId,
              registerId: registerId,
              shiftId: shiftId,
              cashierId: cashierId,
              reason: 'Trop d\'articles',
              refundMethod: AppConstants.paymentCash,
              items: [
                ReturnLineItem(
                  originalSaleLineId: lineToReturn.id,
                  variantId: variantA,
                  quantity: 3,
                  refundUnitPrice: Money.fromTnd(50.000),
                ),
              ],
            ),
          ),
          throwsA(isA<ValidationException>()),
        );

        // Return 2 units (full return)
        await returnService.processReturn(
          ReturnRequest(
            originalSaleId: originalSale.id,
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            reason: 'Retour complet',
            refundMethod: AppConstants.paymentCash,
            items: [
              ReturnLineItem(
                originalSaleLineId: lineToReturn.id,
                variantId: variantA,
                quantity: 2,
                refundUnitPrice: Money.fromTnd(50.000),
              ),
            ],
          ),
        );

        // Duplicate attempt should fail!
        expect(
          () => returnService.processReturn(
            ReturnRequest(
              originalSaleId: originalSale.id,
              storeId: storeId,
              registerId: registerId,
              shiftId: shiftId,
              cashierId: cashierId,
              reason: 'Deuxième tentative',
              refundMethod: AppConstants.paymentCash,
              items: [
                ReturnLineItem(
                  originalSaleLineId: lineToReturn.id,
                  variantId: variantA,
                  quantity: 1,
                  refundUnitPrice: Money.fromTnd(50.000),
                ),
              ],
            ),
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test(
      '5.3 Damaged return routes item to DAMAGED stock location, NOT sellable stock',
      () async {
        final originalLines = await (db.select(
          db.saleLines,
        )..where((t) => t.saleId.equals(originalSale.id))).get();

        await returnService.processReturn(
          ReturnRequest(
            originalSaleId: originalSale.id,
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            reason: 'Article défectueux',
            refundMethod: AppConstants.paymentCash,
            items: [
              ReturnLineItem(
                originalSaleLineId: originalLines.first.id,
                variantId: variantA,
                quantity: 1,
                refundUnitPrice: Money.fromTnd(50.000),
                condition: AppConstants.returnConditionDamaged,
              ),
            ],
          ),
        );

        final shopFloorStock = await inventoryService.getStock(
          variantA,
          locationId: shopFloor.id,
        );
        expect(shopFloorStock, equals(8));

        final damagedStock = await inventoryService.getStock(
          variantA,
          locationId: damagedLoc.id,
        );
        expect(damagedStock, equals(1));
      },
    );

    test(
      '5.4 Clothing exchange reconciles cash drawer: customer pays difference and drawer increases',
      () async {
        final originalLines = await (db.select(
          db.saleLines,
        )..where((t) => t.saleId.equals(originalSale.id))).get();

        // Customer exchanges 1 unit of Variant A (50.000 TND) for 1 unit of Variant B (60.000 TND)
        // Net difference = +10.000 TND paid by customer in cash
        final exchange = await exchangeService.processExchange(
          ExchangeRequest(
            originalSaleId: originalSale.id,
            storeId: storeId,
            registerId: registerId,
            shiftId: shiftId,
            cashierId: cashierId,
            returnedItems: [
              ReturnLineItem(
                originalSaleLineId: originalLines.first.id,
                variantId: variantA,
                quantity: 1,
                refundUnitPrice: Money.fromTnd(50.000),
                condition: AppConstants.returnConditionSellable,
              ),
            ],
            newItems: [
              CartItem(
                variantId: variantB,
                productId: prodId,
                productName: 'Pull Col V Mérinos',
                variantDescription: 'Taille L',
                sku: 'PULL-L',
                barcode: '619111222002',
                unitPrice: Money.fromTnd(60.000),
                originalPrice: Money.fromTnd(60.000),
                unitCost: Money.fromTnd(20.000),
                quantity: 1,
              ),
            ],
            paymentMethod: AppConstants.paymentCash,
            tendered: Money.fromTnd(10.000),
            reason: 'Échange contre taille supérieure L',
          ),
        );

        expect(exchange.difference.millimes, equals(10000));

        // Drawer expected cash:
        // Float: 200.000 + Sale Cash: 100.000 + Exchange Diff: 10.000 = 310.000 TND
        final summary = await shiftService.closeShift(
          shiftId: shiftId,
          cashierId: cashierId,
          countedCash: Money.fromTnd(310.000),
        );

        expect(summary.difference?.millimes, equals(0));
      },
    );
  });

  group('6. Purchasing, Receiving & Physical Inventory Count QA', () {
    late String supplierId;
    late String poVariantId;

    setUp(() async {
      supplierId = IdGenerator.uuid();
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              id: supplierId,
              name: 'Textile Ksar Hellal SARL',
              phone: const Value('71000000'),
              createdAt: DateTime.now(),
            ),
          );

      final prodId = IdGenerator.uuid();
      poVariantId = IdGenerator.uuid();
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: prodId,
              name: 'Jean Denim Brut',
              defaultCostMillimes: const Value(30000),
              defaultPriceMillimes: const Value(79000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: poVariantId,
              productId: prodId,
              sku: 'JEAN-RAW-32',
              barcode: '619333444555',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    });

    test(
      '6.1 Goods receiving increases stock and duplicate receipt is rejected',
      () async {
        final poId = await purchaseService.createPurchaseOrder(
          supplierId: supplierId,
          items: [
            (
              variantId: poVariantId,
              expectedQty: 20,
              unitCost: Money.fromTnd(30.000),
            ),
          ],
        );

        await purchaseService.receiveGoods(
          purchaseOrderId: poId,
          supplierId: supplierId,
          storeId: storeId,
          receivedById: managerId,
          lines: [
            ReceivedLineInput(
              variantId: poVariantId,
              quantityReceived: 20,
              quantityDamaged: 0,
              quantityRejected: 0,
              unitCost: Money.fromTnd(30.000),
            ),
          ],
        );

        final stock = await inventoryService.getStock(
          poVariantId,
          locationId: shopFloor.id,
        );
        expect(stock, equals(20));

        expect(
          () => purchaseService.receiveGoods(
            purchaseOrderId: poId,
            supplierId: supplierId,
            storeId: storeId,
            receivedById: managerId,
            lines: [
              ReceivedLineInput(
                variantId: poVariantId,
                quantityReceived: 20,
                unitCost: Money.fromTnd(30.000),
              ),
            ],
          ),
          throwsA(isA<ValidationException>()),
        );
      },
    );

    test(
      '6.2 Physical inventory count records discrepancy and reconciles stock',
      () async {
        await inventoryService.recordMovement(
          variantId: poVariantId,
          movementType: AppConstants.movementInitial,
          quantityDelta: 20,
          toLocationId: shopFloor.id,
          actorId: managerId,
        );

        final countId = await inventoryCountService.initiateCount(
          locationId: shopFloor.id,
          initiatedById: managerId,
        );

        await inventoryCountService.recordScannedVariant(
          countId: countId,
          barcodeOrSku: '619333444555',
          increment: 18,
        );

        await inventoryCountService.reconcileAndComplete(
          countId: countId,
          managerId: managerId,
        );

        final newStock = await inventoryService.getStock(
          poVariantId,
          locationId: shopFloor.id,
        );
        expect(newStock, equals(18));
      },
    );
  });

  group('7. Database Diagnostics, Integrity Checker & Self-Repair QA', () {
    test(
      '7.1 Diagnostics run clean on fresh database without foreign key or orphan violations',
      () async {
        final report = await integrityService.runDiagnostics();
        expect(report.isHealthy, isTrue);
        expect(report.issues, isEmpty);
      },
    );

    test(
      '7.2 Self-repair rebuilds corrupted stock cache from immutable movement ledger',
      () async {
        final varId = IdGenerator.uuid();
        final prodId = IdGenerator.uuid();

        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: prodId,
                name: 'T-Shirt Basique',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                id: varId,
                productId: prodId,
                sku: 'TSH-WHT-S',
                barcode: '619000111222',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        await inventoryService.recordMovement(
          variantId: varId,
          movementType: AppConstants.movementInitial,
          quantityDelta: 15,
          toLocationId: shopFloor.id,
          actorId: managerId,
        );

        // Artificially corrupt the cached stock_levels row
        await (db.update(db.stockLevels)
              ..where((t) => t.variantId.equals(varId)))
            .write(const StockLevelsCompanion(quantity: Value(999)));

        final corruptedStock = await inventoryService.getStock(
          varId,
          locationId: shopFloor.id,
        );
        expect(corruptedStock, equals(999));

        final repairedCount = await integrityService
            .rebuildStockLevelsFromMovements();
        expect(repairedCount, greaterThanOrEqualTo(1));

        final repairedStock = await inventoryService.getStock(
          varId,
          locationId: shopFloor.id,
        );
        expect(repairedStock, equals(15));
      },
    );
  });

  group('8. Backup Snapshot & Validation QA', () {
    test(
      '8.1 Backup validation rejects empty, non-existent, or invalid header files',
      () async {
        await expectLater(
          backupService.validateBackupFile('/path/that/does/not/exist.sqlite'),
          throwsA(isA<ValidationException>()),
        );

        final tempDir = Directory.systemTemp.createTempSync('jazz_qa_');
        final badFile = File('${tempDir.path}/fake.sqlite');
        await badFile.writeAsString(
          'This is not a SQLite database file at all!',
        );

        await expectLater(
          backupService.validateBackupFile(badFile.path),
          throwsA(isA<ValidationException>()),
        );

        tempDir.deleteSync(recursive: true);
      },
    );
  });

  group('9. POS Hardware Document Encoding QA', () {
    test(
      '9.1 ESC/POS receipt commands generate valid bytes and drawer kick pulse',
      () {
        final doc = ReceiptDocument(
          storeName: 'JAZZ POS TUNIS MALL',
          storeAddress: 'Les Berges du Lac 2, Tunis',
          storePhone: '+216 71 000 000',
          fiscalId: '1234567/A/M/000',
          receiptNumber: 'REC-20260904-001',
          cashierName: 'Ahmed Caissier',
          registerCode: 'REG-01',
          dateTime: DateTime(2026, 9, 4, 14, 30),
          lines: [
            ReceiptLineItem(
              productName: 'Chemise Oxford M',
              variantDescription: 'BLU / M',
              sku: 'CHM-BLU-M',
              barcode: '6191234567001',
              quantity: 2,
              unitPrice: Money.fromTnd(59.900),
              total: Money.fromTnd(119.800),
            ),
          ],
          subtotal: Money.fromTnd(119.800),
          discount: Money.zero,
          tax: Money.fromTnd(22.762),
          total: Money.fromTnd(119.800),
          payments: [
            ReceiptPaymentItem(
              method: 'CASH',
              amount: Money.fromTnd(119.800),
              tendered: Money.fromTnd(120.000),
              change: Money.fromTnd(0.200),
            ),
          ],
          footerMessage: 'Merci de votre visite à Jazz POS !',
        );

        expect(doc.receiptNumber, equals('REC-20260904-001'));

        final escBytes = EscPosCommands.openCashDrawer();
        expect(escBytes, equals([0x1B, 0x70, 0x00, 0x19, 0xFA]));

        final cutBytes = EscPosCommands.cutPaper();
        expect(cutBytes, equals([0x1D, 0x56, 0x42, 0x00]));

        final colLine = EscPosCommands.formatColumns(
          left: 'Chemise Oxford',
          right: '119.800 TND',
          width: 48,
        );
        expect(colLine.length, equals(48));
        expect(colLine.startsWith('Chemise Oxford'), isTrue);
        expect(colLine.endsWith('119.800 TND'), isTrue);
      },
    );

    test(
      '9.2 TSPL barcode label generator outputs valid TSPL/TSPL2 commands for label printer',
      () {
        final labelDoc = LabelDocument(
          storeName: 'JAZZ POS',
          productName: 'Pull Col V Mérinos',
          sku: 'PULL-NAV-L',
          barcode: '619111222002',
          price: Money.fromTnd(60.000),
          color: 'BLEU',
          size: 'L',
          brandName: 'Jazz Collection',
          copies: 2,
          widthMm: 50,
          heightMm: 30,
        );

        final tspl = TsplCommands.buildLabel(labelDoc);
        expect(tspl, contains('SIZE 50 mm, 30 mm'));
        expect(
          tspl,
          contains('BARCODE 20, 105, "128", 45, 1, 0, 2, 2, "619111222002"'),
        );
        expect(tspl, contains('60.000 TND'));
        expect(tspl, contains('BLEU'));
        expect(tspl, contains('PRINT 2, 1'));
      },
    );
  });
}
