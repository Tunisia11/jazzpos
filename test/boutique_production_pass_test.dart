import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/core/utils/password_hasher.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/models/variant_matrix.dart';
import 'package:jazzpos/domain/services/auth_service.dart';
import 'package:jazzpos/domain/services/boutique_settings_service.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/receipt_printer/fake_receipt_printer.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_layout_builder.dart';
import 'package:jazzpos/hardware/label_printer/fake_label_printer.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/hardware/label_printer/tspl_commands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late InventoryService inventoryService;
  late CatalogService catalogService;
  late AuthService authService;
  late BoutiqueSettingsService boutiqueService;

  const adminId = 'USER-ADMIN';
  const storeId = 'STORE-TEST';

  Future<String> createTestProduct({
    required String name,
    required String sku,
    required String barcode,
    String? categoryId,
    Money defaultCost = const Money.fromMillimes(10000),
    Money defaultPrice = const Money.fromMillimes(20000),
    int stock = 5,
  }) async {
    final prodId = IdGenerator.uuid();
    await catalogService.createProductWithMatrix(
      productId: prodId,
      name: name,
      categoryId: categoryId,
      defaultCost: defaultCost,
      defaultPrice: defaultPrice,
      actorId: adminId,
      storeId: storeId,
      variants: [
        MatrixVariantItem(
          id: IdGenerator.uuid(),
          selectedAttributes: {},
          sku: sku,
          barcode: barcode,
          costPrice: defaultCost,
          salePrice: defaultPrice,
          initialStock: stock,
        ),
      ],
    );
    return prodId;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventoryService = InventoryService(db);
    catalogService = CatalogService(db, inventoryService);
    authService = AuthService(db);
    boutiqueService = BoutiqueSettingsService(db);

    final now = DateTime.now();

    // Setup initial admin and store
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: adminId,
        username: 'admin',
        displayName: 'Administrateur',
        role: AppRoles.owner,
        pinHash: PasswordHasher.hashPin('1234', 'salt123'),
        pinSalt: 'salt123',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Give admin permissions
    for (final p in AppRoles.defaultPermissionsForRole(AppRoles.owner)) {
      await db.into(db.userPermissions).insert(
        UserPermissionsCompanion.insert(
          id: IdGenerator.uuid(),
          userId: adminId,
          permission: p,
        ),
      );
    }

    const companyId = 'COMP-TEST';
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Boutique Élégance',
        fiscalId: const Value('1234567/A/M/000'),
        phone: const Value('+216 71 111 222'),
        address: const Value('10 Rue de la Mode, Tunis'),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.stores).insert(
      StoresCompanion.insert(
        id: storeId,
        companyId: companyId,
        name: 'Boutique Élégance',
        code: 'STORE-01',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Establish active authenticated owner session
    await authService.login(username: 'admin', pin: '1234');
  });

  tearDown(() async {
    await db.close();
  });

  group('Requirement 1 — Deterministic SKU Auto-Generation', () {
    test('Generates deterministic SKU with category prefix and 6-digit zero-padding', () async {
      // Create category with code TSH
      final cat = await catalogService.createCategory(
        name: 'T-Shirts',
        code: 'TSH',
        actorId: adminId,
      );

      final sku1 = await catalogService.generateNextProductSku(categoryId: cat.id);
      expect(sku1, equals('TSH-000001'));

      // Create product using sku1
      await createTestProduct(
        name: 'T-Shirt Basique',
        sku: sku1,
        barcode: '200100000001',
        categoryId: cat.id,
      );

      // Next SKU should increment sequentially to TSH-000002
      final sku2 = await catalogService.generateNextProductSku(categoryId: cat.id);
      expect(sku2, equals('TSH-000002'));
    });

    test('Falls back to sanitized name prefix when code is absent', () async {
      final cat = await catalogService.createCategory(
        name: 'Pantalons Chino',
        actorId: adminId,
      );

      final sku = await catalogService.generateNextProductSku(categoryId: cat.id);
      expect(sku.startsWith('PANT-'), isTrue);
      expect(sku, matches(r'^PANT-\d{6}$'));
    });

    test('Generates ART- prefix when no category is specified', () async {
      final sku = await catalogService.generateNextProductSku();
      expect(sku, equals('ART-000001'));
    });
  });

  group('Requirement 2 — Barcode Creation & Modulo-10 Check Digit', () {
    test('EAN-13 Modulo-10 check digit conforms to GS1 standard vectors', () {
      expect(IdGenerator.computeEan13CheckDigit('400638133393'), equals('1'));
      expect(IdGenerator.computeEan13CheckDigit('590123412345'), equals('7'));
      expect(IdGenerator.computeEan13CheckDigit('978020137962'), equals('4'));
    });

    test('Generated EAN-13 produces valid 13-digit string preserving leading zeros', () {
      final ean = IdGenerator.generateEan13(prefix: '200');
      expect(ean.length, equals(13));
      expect(ean.startsWith('200'), isTrue);
      expect(IdGenerator.isValidEan13(ean), isTrue);
    });

    test('generateUniqueEan13 guarantees collision-free barcodes against database', () async {
      final ean = await catalogService.generateUniqueEan13(prefix: '200');
      expect(ean.length, equals(13));
      expect(IdGenerator.isValidEan13(ean), isTrue);

      // Insert product with this barcode
      await createTestProduct(
        name: 'Article Unique',
        sku: 'ART-000099',
        barcode: ean,
      );

      // Next unique EAN must not collide with the existing one
      final nextEan = await catalogService.generateUniqueEan13(prefix: '200');
      expect(nextEan, isNot(equals(ean)));
    });

    test('findConflictForBarcode returns conflicting product name and SKU', () async {
      const existingBarcode = '2009876543210';
      await createTestProduct(
        name: 'Robe d\'été Fleurie',
        sku: 'ROB-000001',
        barcode: existingBarcode,
      );

      // Attempting to look up conflict for this barcode
      final conflict = await catalogService.findConflictForBarcode(existingBarcode);
      expect(conflict, isNotNull);
      expect(conflict, contains('Robe d\'été Fleurie'));
      expect(conflict, contains('ROB-000001'));

      // Safe exclusion of self when editing
      final variants = await (db.select(db.productVariants)..where((t) => t.barcode.equals(existingBarcode))).get();
      final selfConflict = await catalogService.findConflictForBarcode(existingBarcode, excludeVariantId: variants.first.id);
      expect(selfConflict, isNull);
    });
  });

  group('Requirement 3 — Non-Hardcoded Category CRUD & Safe Reassignment', () {
    test('Create, rename and update category', () async {
      final cat = await catalogService.createCategory(
        name: 'Chemises',
        code: 'CHM',
        actorId: adminId,
      );
      expect(cat.name, equals('Chemises'));
      expect(cat.code, equals('CHM'));

      await catalogService.updateCategory(
        id: cat.id,
        name: 'Chemises & Blouses',
        code: 'CHB',
        actorId: adminId,
      );

      final updated = await (db.select(db.categories)..where((t) => t.id.equals(cat.id))).getSingle();
      expect(updated.name, equals('Chemises & Blouses'));
      expect(updated.code, equals('CHB'));
    });

    test('Safe delete category with product reassignment', () async {
      final catA = await catalogService.createCategory(name: 'Catégorie A', actorId: adminId);
      final catB = await catalogService.createCategory(name: 'Catégorie B', actorId: adminId);

      // Create product in Cat A
      final pId = await createTestProduct(
        name: 'Produit Test',
        sku: 'PRD-000001',
        barcode: '2001112223334',
        categoryId: catA.id,
      );

      final p = await (db.select(db.products)..where((t) => t.id.equals(pId))).getSingle();
      expect(p.categoryId, equals(catA.id));

      // Delete Cat A with reassignment to Cat B
      await catalogService.deleteCategory(
        id: catA.id,
        reassignToCategoryId: catB.id,
        actorId: adminId,
      );

      // Verify Cat A is deleted
      final catACheck = await (db.select(db.categories)..where((t) => t.id.equals(catA.id))).getSingleOrNull();
      expect(catACheck, isNull);

      // Verify product was safely reassigned to Cat B
      final pUpdated = await (db.select(db.products)..where((t) => t.id.equals(pId))).getSingle();
      expect(pUpdated.categoryId, equals(catB.id));
    });

    test('Safe delete category with unassignment (NULL)', () async {
      final cat = await catalogService.createCategory(name: 'Catégorie Temporaire', actorId: adminId);

      final pId = await createTestProduct(
        name: 'Produit Détaché',
        sku: 'PRD-000002',
        barcode: '2002223334445',
        categoryId: cat.id,
      );

      // Delete category with null reassignment
      await catalogService.deleteCategory(
        id: cat.id,
        reassignToCategoryId: null,
        actorId: adminId,
      );

      final pUpdated = await (db.select(db.products)..where((t) => t.id.equals(pId))).getSingle();
      expect(pUpdated.categoryId, isNull);
    });
  });

  group('Requirement 4 & 6 — Staff Management & Cryptographic PIN Hashing', () {
    test('Create employee with salted PBKDF2 hash, update profile, reset PIN, toggle active', () async {
      // Create cashier
      final cashierId = await authService.createUser(
        username: 'caissier_nour',
        displayName: 'Nour Ben Ali',
        role: AppRoles.cashier,
        pin: '5678',
      );

      final users = await authService.getAllUsers();
      final cashier = users.firstWhere((u) => u.id == cashierId);
      expect(cashier.displayName, equals('Nour Ben Ali'));
      expect(cashier.role, equals(AppRoles.cashier));
      expect(cashier.isActive, isTrue);

      // Verify PIN login succeeds
      final session = await authService.login(username: 'caissier_nour', pin: '5678');
      expect(session.user.id, equals(cashierId));

      // Update profile
      await authService.updateUser(
        userId: cashierId,
        displayName: 'Nour B. Ali (Chef de Caisse)',
        role: AppRoles.manager,
      );
      final updatedUser = (await authService.getAllUsers()).firstWhere((u) => u.id == cashierId);
      expect(updatedUser.displayName, equals('Nour B. Ali (Chef de Caisse)'));
      expect(updatedUser.role, equals(AppRoles.manager));

      // Reset PIN to new PIN 9999
      await authService.resetUserPin(userId: cashierId, newPin: '9999');

      // Old PIN fails, new PIN succeeds
      expect(
        () async => await authService.login(username: 'caissier_nour', pin: '5678'),
        throwsA(isA<AuthException>()),
      );
      final newSession = await authService.login(username: 'caissier_nour', pin: '9999');
      expect(newSession.user.id, equals(cashierId));

      // Toggle active to false
      await authService.toggleUserActive(cashierId, false);
      expect(
        () async => await authService.login(username: 'caissier_nour', pin: '9999'),
        throwsA(isA<AuthException>()),
      );

      // Delete user
      await authService.deleteUser(cashierId);
      final remaining = await authService.getAllUsers();
      expect(remaining.any((u) => u.id == cashierId), isFalse);
    });

    test('Boutique settings service loads and updates boutique profile correctly', () async {
      final initial = await boutiqueService.loadSettings();
      expect(initial.name, isNotEmpty);

      await boutiqueService.saveSettings(
        initial.copyWith(
          name: 'La Parisienne Boutique',
          address: 'Avenue Habib Bourguiba, Tunis',
          phone: '+216 71 000 000',
          fiscalId: '1234567M/A/M/000',
        ),
      );

      final reloaded = await boutiqueService.loadSettings();
      expect(reloaded.name, equals('La Parisienne Boutique'));
      expect(reloaded.fiscalId, equals('1234567M/A/M/000'));
      expect(reloaded.address, equals('Avenue Habib Bourguiba, Tunis'));
    });
  });

  group('Requirement 6 — Hardware Diagnostics & Certified Receipt Test Print', () {
    test('Hardware test receipt contains all mandatory client installation strings', () async {
      final hw = HardwareManager.instance;
      hw.initializeSimulatedHardware();

      final fakePrinter = hw.receiptPrinter as FakeReceiptPrinter;

      const storeName = 'Boutique Jasmine';
      const barcode = '200123456789';

      await hw.testReceiptPrinter(storeName: storeName, barcode: barcode);

      expect(fakePrinter.printedDocuments.isNotEmpty, isTrue);
      final lastDoc = fakePrinter.printedDocuments.last;

      // Exact mandatory strings verification:
      // 1. Boutique: [name]
      expect(lastDoc.storeName, contains('Boutique: Boutique Jasmine'));
      // 2. Article Test 10.000
      expect(lastDoc.lines.any((l) => l.productName == 'Article Test 10.000'), isTrue);
      // 3. TOTAL 10.000
      expect(lastDoc.total.format(), contains('10.000'));
      // 4. Barcode
      expect(lastDoc.lines.first.barcode, equals(barcode));
      // 5. Printer test successful
      expect(lastDoc.footerMessage, contains('Printer test successful'));

      // Format to raw ESC/POS bytes through ReceiptLayoutBuilder
      final rawBytes = ReceiptLayoutBuilder.buildEscPosBytes(lastDoc);
      expect(rawBytes.isNotEmpty, isTrue);
    });

    test('Critical round-trip: generate barcode -> save product -> print label TSPL -> scan value -> exact product resolves', () async {
      final hw = HardwareManager.instance;
      hw.initializeSimulatedHardware();
      final fakeLabelPrinter = hw.labelPrinter as FakeLabelPrinter;

      // 1. Generate unique internal EAN-13 barcode
      final generatedBarcode = await catalogService.generateUniqueEan13();
      expect(IdGenerator.isValidEan13(generatedBarcode), isTrue);

      // 2. Save product with generated barcode
      final sku = await catalogService.generateNextProductSku(prefix: 'ROBE');
      final prodId = await createTestProduct(
        name: 'Robe de Soiree Velours',
        sku: sku,
        barcode: generatedBarcode,
        defaultPrice: const Money.fromMillimes(85000),
      );
      expect(prodId, isNotEmpty);

      // 3. Print barcode label
      final labelDoc = LabelDocument(
        storeName: 'Boutique Parisienne',
        productName: 'Robe de Soiree Velours',
        sku: sku,
        barcode: generatedBarcode,
        barcodeType: 'EAN13',
        price: const Money.fromMillimes(85000),
      );
      await fakeLabelPrinter.printLabel(labelDoc);

      expect(fakeLabelPrinter.printedLabels.isNotEmpty, isTrue);
      final lastLabel = fakeLabelPrinter.printedLabels.last;
      expect(lastLabel.barcode, equals(generatedBarcode));

      // 4. Verify TSPL command output encodes the EXACT barcode value
      final tsplOutput = TsplCommands.buildLabel(lastLabel);
      expect(tsplOutput, contains('"$generatedBarcode"'));
      expect(tsplOutput, contains('EAN13'));

      // 5. Scan value back into POS exact lookup
      final scannedMatch = await catalogService.findVariantByExactBarcode(generatedBarcode);
      expect(scannedMatch, isNotNull);
      expect(scannedMatch!.productName, equals('Robe de Soiree Velours'));
      expect(scannedMatch.barcode, equals(generatedBarcode));
      expect(scannedMatch.sku, equals(sku));
    });
  });
}
