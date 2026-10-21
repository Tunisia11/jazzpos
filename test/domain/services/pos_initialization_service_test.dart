import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/permissions.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/auth_service.dart';
import 'package:jazzpos/domain/services/pos_initialization_service.dart';

void main() {
  group('PosInitializationService & Bootstrap Architecture', () {
    late AppDatabase db;
    late PosInitializationService initService;
    late AuthService authService;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      initService = PosInitializationService(db);
      authService = AuthService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('TEST A: Clean initial setup creates complete, consistent POS records', () async {
      expect(await initService.isSetupCompleted(), isFalse);
      expect(await initService.isBootstrapAllowed(), isTrue);

      await initService.initializePos(
        companyName: 'Boutique Élégance',
        fiscalId: '1234567/A/M/000',
        phone: '+216 71 000 000',
        address: 'Avenue Habib Bourguiba, Tunis',
        storeName: 'Boutique Principale',
        registerCode: 'REG-001',
        registerName: 'Caisse Principale',
        locationName: 'Stock principal',
        ownerUsername: 'admin',
        ownerDisplayName: 'Directeur Général',
        ownerPin: '1234',
        paperWidthMm: 80,
      );

      // Verify setup completion
      expect(await initService.isSetupCompleted(), isTrue);
      expect(await initService.isBootstrapAllowed(), isFalse);

      // Verify Company
      final companies = await db.select(db.companies).get();
      expect(companies, hasLength(1));
      expect(companies.first.name, 'Boutique Élégance');
      expect(companies.first.fiscalId, '1234567/A/M/000');

      // Verify Store
      final stores = await db.select(db.stores).get();
      expect(stores, hasLength(1));
      expect(stores.first.id, 'STORE-01');
      expect(stores.first.name, 'Boutique Principale');

      // Verify Register
      final registers = await db.select(db.registers).get();
      expect(registers, hasLength(1));
      expect(registers.first.code, 'REG-001');
      expect(registers.first.name, 'Caisse Principale');

      // Verify Default Stock Location
      final locations = await db.select(db.stockLocations).get();
      expect(locations, hasLength(1));
      expect(locations.first.code, 'LOC-SHOP');
      expect(locations.first.name, 'Stock principal');
      expect(locations.first.isDefault, isTrue);

      // Verify Owner User & Permissions
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      final owner = users.first;
      expect(owner.username, 'admin');
      expect(owner.role, AppRoles.owner);
      expect(owner.isActive, isTrue);

      final permissions = await (db.select(db.userPermissions)
            ..where((t) => t.userId.equals(owner.id)))
          .get();
      expect(permissions.map((p) => p.permission).toSet(),
          containsAll([AppPermissions.manageUsers, AppPermissions.manageSettings]));

      // Verify Seed Attributes & Categories
      final attrTypes = await db.select(db.attributeTypes).get();
      expect(attrTypes.map((a) => a.code).toSet(), containsAll(['SIZE', 'COLOR']));

      final categories = await db.select(db.categories).get();
      expect(categories.isNotEmpty, isTrue);

      // Verify Immediate Login
      final session = await authService.login(username: 'admin', pin: '1234');
      expect(session.user.username, 'admin');
      expect(session.hasPermission(AppPermissions.manageUsers), isTrue);
    });

    test('TEST B: Register ID auto-generation sequence and gap filling', () async {
      // 1. Empty database -> REG-001
      expect(await initService.generateNextRegisterCode(), 'REG-001');

      // Insert REG-001
      await initService.initializePos(
        companyName: 'Test Store',
        storeName: 'Store 1',
        registerCode: 'REG-001',
        ownerUsername: 'owner1',
        ownerDisplayName: 'Owner 1',
        ownerPin: '1111',
      );

      // 2. REG-001 exists -> REG-002
      expect(await initService.generateNextRegisterCode(), 'REG-002');

      // Insert REG-003 manually to test gap filling
      final now = DateTime.now();
      await db.into(db.registers).insert(
        RegistersCompanion.insert(
          id: 'REG-003',
          storeId: 'STORE-01',
          name: 'Caisse Secondaire',
          code: 'REG-003',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 3. Gap filling: REG-001 and REG-003 exist -> safely allocates REG-002
      expect(await initService.generateNextRegisterCode(), 'REG-002');
    });

    test('TEST C: Repeated initialization after setup completed is blocked', () async {
      await initService.initializePos(
        companyName: 'Store',
        storeName: 'Main Store',
        registerCode: 'REG-001',
        ownerUsername: 'admin',
        ownerDisplayName: 'Admin',
        ownerPin: '1234',
      );

      // Subsequent initialization attempts must fail
      expect(
        () => initService.initializePos(
          companyName: 'Store 2',
          storeName: 'Main Store 2',
          registerCode: 'REG-002',
          ownerUsername: 'admin2',
          ownerDisplayName: 'Admin 2',
          ownerPin: '5678',
        ),
        throwsA(isA<PosException>()),
      );
    });

    test('TEST D: Idempotent re-run / retry on pre-existing records', () async {
      final now = DateTime.now();

      // Pre-seed an existing store STORE-01 and company
      final companyId = 'COMP-OLD';
      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: companyId,
          name: 'Old Name',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.stores).insert(
        StoresCompanion.insert(
          id: 'STORE-01',
          companyId: companyId,
          name: 'Old Store Name',
          code: 'STORE-01',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Run initializePos — must not crash on duplicate PK
      await initService.initializePos(
        companyName: 'Updated Company Name',
        storeName: 'Updated Store Name',
        registerCode: 'REG-001',
        ownerUsername: 'admin',
        ownerDisplayName: 'Admin User',
        ownerPin: '9999',
      );

      final updatedStore = await (db.select(db.stores)
            ..where((t) => t.id.equals('STORE-01')))
          .getSingle();
      expect(updatedStore.name, 'Updated Store Name');

      final updatedCompany = await db.select(db.companies).getSingle();
      expect(updatedCompany.name, 'Updated Company Name');
    });

    test('TEST E: Bootstrap succeeds even when non-admin cashier exists (reproduction fix)', () async {
      final now = DateTime.now();

      // Simulate the exact real-world bug: a test cashier user already exists in DB
      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'usr_inst',
          username: 'cashier1',
          displayName: 'Cashier Test',
          role: AppRoles.cashier,
          pinHash: 'dummy',
          pinSalt: 'dummy',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify that bootstrap is still allowed because NO owner or manager exists yet
      expect(await initService.isBootstrapAllowed(), isTrue);

      // Verify that AuthService allows creating the owner
      await initService.initializePos(
        companyName: 'My Fashion Shop',
        storeName: 'Shop Floor',
        registerCode: 'REG-001',
        ownerUsername: 'real_owner',
        ownerDisplayName: 'Shop Owner',
        ownerPin: '2026',
      );

      expect(await initService.isSetupCompleted(), isTrue);

      final owner = await (db.select(db.users)
            ..where((t) => t.username.equals('real_owner')))
          .getSingle();
      expect(owner.role, AppRoles.owner);
    });

    test('TEST F: Post-setup unauthenticated account creation is strictly forbidden', () async {
      await initService.initializePos(
        companyName: 'Secure POS',
        storeName: 'Branch 1',
        registerCode: 'REG-001',
        ownerUsername: 'owner',
        ownerDisplayName: 'Owner',
        ownerPin: '1111',
      );

      // Now setup_completed is true. Unauthenticated user creation must throw AuthException
      await expectLater(
        authService.createUser(
          username: 'hacker',
          displayName: 'Unauthorized User',
          role: AppRoles.cashier,
          pin: '0000',
        ),
        throwsA(isA<AuthException>()),
      );

      // Authenticated admin with manageUsers permission CAN create users
      await authService.login(username: 'owner', pin: '1111');
      final newUserId = await authService.createUser(
        username: 'legit_cashier',
        displayName: 'Legit Cashier',
        role: AppRoles.cashier,
        pin: '5555',
      );
      expect(newUserId, isNotEmpty);
    });
  });
}
