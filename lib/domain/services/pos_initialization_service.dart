import 'package:drift/drift.dart' as drift;
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/utils/password_hasher.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/data/database/app_database.dart';

class PosInitializationService {
  final AppDatabase db;

  PosInitializationService(this.db);

  /// Key in AppSettings table marking initial setup completion
  static const String settingSetupCompleted = 'setup_completed';
  static const String settingSetupCompletedAt = 'setup_completed_at';
  static const String settingCurrentStoreId = 'current_store_id';
  static const String settingCurrentRegisterId = 'current_register_id';
  static const String settingCurrentRegisterCode = 'current_register_code';
  static const String settingPrinterPaperWidth = 'hardware_printer_paper_width';
  static const String settingCurrency = 'hardware_currency';

  /// Check whether initial setup has been completed
  Future<bool> isSetupCompleted() async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(settingSetupCompleted)))
        .getSingleOrNull();
    return row?.value == 'true';
  }

  /// Check whether unauthenticated initial bootstrap is allowed.
  /// Bootstrap is allowed ONLY when setup is not completed AND no admin/owner user exists yet.
  Future<bool> isBootstrapAllowed() async {
    if (await isSetupCompleted()) {
      return false;
    }
    final existingAdmins = await (db.select(db.users)
          ..where((tbl) =>
              tbl.role.equals(AppRoles.owner) |
              tbl.role.equals(AppRoles.manager)))
        .get();
    return existingAdmins.isEmpty;
  }

  /// Get current bound register code from AppSettings, or fallback to query
  Future<String?> getCurrentRegisterCode() async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(settingCurrentRegisterCode)))
        .getSingleOrNull();
    if (row != null && row.value.trim().isNotEmpty) {
      return row.value.trim();
    }
    final firstReg = await (db.select(db.registers)..limit(1)).getSingleOrNull();
    return firstReg?.code;
  }

  /// Auto-generate next available register code (e.g. REG-001, REG-002, ...)
  /// Inspects existing register records, parses numeric sequences, and allocates
  /// the lowest unused positive integer formatted as zero-padded REG-XXX.
  Future<String> generateNextRegisterCode() async {
    final registers = await db.select(db.registers).get();
    final usedNumbers = <int>{};
    final regex = RegExp(r'^REG-(\d+)$', caseSensitive: false);

    for (final reg in registers) {
      final matchCode = regex.firstMatch(reg.code.trim());
      if (matchCode != null) {
        final num = int.tryParse(matchCode.group(1)!);
        if (num != null && num > 0) usedNumbers.add(num);
      }
      final matchId = regex.firstMatch(reg.id.trim());
      if (matchId != null) {
        final num = int.tryParse(matchId.group(1)!);
        if (num != null && num > 0) usedNumbers.add(num);
      }
    }

    int nextNum = 1;
    while (usedNumbers.contains(nextNum)) {
      nextNum++;
    }

    return 'REG-${nextNum.toString().padLeft(3, '0')}';
  }

  /// Perform complete, atomic, and idempotent POS initialization
  Future<void> initializePos({
    required String companyName,
    String? fiscalId,
    String? phone,
    String? address,
    required String storeName,
    required String registerCode,
    String? registerName,
    String? locationName,
    required String ownerUsername,
    required String ownerDisplayName,
    required String ownerPin,
    int paperWidthMm = 80,
  }) async {
    final alreadyCompleted = await isSetupCompleted();
    if (alreadyCompleted) {
      throw const PosException('Trace POS configuration has already been initialized.');
    }

    PosLogger.instance.info(
      'Init',
      'Starting initial setup bootstrap: store="$storeName", register="$registerCode"',
    );

    final cleanCompanyName = companyName.trim();
    final cleanStoreName = storeName.trim();
    final cleanRegisterCode = registerCode.trim().toUpperCase();
    final cleanRegisterName = (registerName != null && registerName.trim().isNotEmpty)
        ? registerName.trim()
        : 'Caisse Principale';
    final cleanLocationName = (locationName != null && locationName.trim().isNotEmpty)
        ? locationName.trim()
        : 'Stock principal';
    final cleanUsername = ownerUsername.trim();
    final cleanDisplayName = ownerDisplayName.trim();
    final cleanPin = ownerPin.trim();

    if (cleanCompanyName.isEmpty ||
        cleanStoreName.isEmpty ||
        cleanRegisterCode.isEmpty ||
        cleanUsername.isEmpty ||
        cleanDisplayName.isEmpty ||
        cleanPin.length < 4) {
      throw const PosException('Required setup fields are missing or invalid.');
    }

    final now = DateTime.now();

    await db.transaction(() async {
      // 1. Company: Idempotently create or update
      final existingCompanies = await db.select(db.companies).get();
      String companyId;
      if (existingCompanies.isNotEmpty) {
        companyId = existingCompanies.first.id;
        await (db.update(db.companies)..where((t) => t.id.equals(companyId))).write(
          CompaniesCompanion(
            name: drift.Value(cleanCompanyName),
            fiscalId: drift.Value(fiscalId?.trim()),
            phone: drift.Value(phone?.trim()),
            address: drift.Value(address?.trim()),
            updatedAt: drift.Value(now),
          ),
        );
      } else {
        companyId = IdGenerator.uuid();
        await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: cleanCompanyName,
            fiscalId: drift.Value(fiscalId?.trim()),
            phone: drift.Value(phone?.trim()),
            address: drift.Value(address?.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 2. Store: Idempotently create or update STORE-01
      const storeId = 'STORE-01';
      final existingStore = await (db.select(db.stores)
            ..where((t) => t.id.equals(storeId) | t.code.equals(storeId)))
          .getSingleOrNull();

      if (existingStore != null) {
        await (db.update(db.stores)..where((t) => t.id.equals(existingStore.id))).write(
          StoresCompanion(
            companyId: drift.Value(companyId),
            name: drift.Value(cleanStoreName),
            address: drift.Value(address?.trim()),
            phone: drift.Value(phone?.trim()),
            updatedAt: drift.Value(now),
          ),
        );
      } else {
        await db.into(db.stores).insert(
          StoresCompanion.insert(
            id: storeId,
            companyId: companyId,
            name: cleanStoreName,
            code: storeId,
            address: drift.Value(address?.trim()),
            phone: drift.Value(phone?.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 3. Register: Idempotently create or update register
      final existingRegister = await (db.select(db.registers)
            ..where((t) =>
                t.id.equals(cleanRegisterCode) | t.code.equals(cleanRegisterCode)))
          .getSingleOrNull();

      if (existingRegister != null) {
        await (db.update(db.registers)..where((t) => t.id.equals(existingRegister.id))).write(
          RegistersCompanion(
            storeId: const drift.Value(storeId),
            name: drift.Value(cleanRegisterName),
            code: drift.Value(cleanRegisterCode),
            updatedAt: drift.Value(now),
          ),
        );
      } else {
        await db.into(db.registers).insert(
          RegistersCompanion.insert(
            id: cleanRegisterCode,
            storeId: storeId,
            name: cleanRegisterName,
            code: cleanRegisterCode,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 4. Default Stock Location: Idempotently create or update LOC-SHOP
      const locationCode = 'LOC-SHOP';
      final existingLoc = await (db.select(db.stockLocations)
            ..where((t) =>
                t.storeId.equals(storeId) &
                (t.code.equals(locationCode) | t.isDefault.equals(true))))
          .getSingleOrNull();

      if (existingLoc != null) {
        await (db.update(db.stockLocations)..where((t) => t.id.equals(existingLoc.id))).write(
          StockLocationsCompanion(
            name: drift.Value(cleanLocationName),
            isDefault: const drift.Value(true),
          ),
        );
      } else {
        await db.into(db.stockLocations).insert(
          StockLocationsCompanion.insert(
            id: IdGenerator.uuid(),
            storeId: storeId,
            name: cleanLocationName,
            code: locationCode,
            locationType: AppConstants.locationShopFloor,
            isDefault: const drift.Value(true),
          ),
        );
      }

      // 5. Initial Owner Admin: Idempotently create or update
      final existingUser = await (db.select(db.users)
            ..where((t) => t.username.equals(cleanUsername)))
          .getSingleOrNull();

      final salt = PasswordHasher.generateSalt();
      final pinHash = PasswordHasher.hashPin(cleanPin, salt);
      String ownerId;

      if (existingUser != null) {
        ownerId = existingUser.id;
        await (db.update(db.users)..where((t) => t.id.equals(ownerId))).write(
          UsersCompanion(
            displayName: drift.Value(cleanDisplayName),
            role: const drift.Value(AppRoles.owner),
            pinHash: drift.Value(pinHash),
            pinSalt: drift.Value(salt),
            isActive: const drift.Value(true),
            updatedAt: drift.Value(now),
          ),
        );
      } else {
        ownerId = IdGenerator.uuid();
        await db.into(db.users).insert(
          UsersCompanion.insert(
            id: ownerId,
            username: cleanUsername,
            displayName: cleanDisplayName,
            role: AppRoles.owner,
            pinHash: pinHash,
            pinSalt: salt,
            isActive: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // Assign default Owner permissions
      final defaultPermissions = AppRoles.defaultPermissionsForRole(AppRoles.owner);
      final existingPerms = await (db.select(db.userPermissions)
            ..where((t) => t.userId.equals(ownerId)))
          .get();
      final existingPermSet = existingPerms.map((p) => p.permission).toSet();

      for (final perm in defaultPermissions) {
        if (!existingPermSet.contains(perm)) {
          await db.into(db.userPermissions).insert(
            UserPermissionsCompanion.insert(
              id: IdGenerator.uuid(),
              userId: ownerId,
              permission: perm,
            ),
          );
        }
      }

      // 6. Seed clothing attribute types & values
      var sizeAttr = await (db.select(db.attributeTypes)
            ..where((t) => t.code.equals('SIZE')))
          .getSingleOrNull();
      if (sizeAttr == null) {
        final sizeId = IdGenerator.uuid();
        await db.into(db.attributeTypes).insert(
          AttributeTypesCompanion.insert(
            id: sizeId,
            name: 'Taille',
            code: 'SIZE',
          ),
        );
        sizeAttr = await (db.select(db.attributeTypes)
              ..where((t) => t.id.equals(sizeId)))
            .getSingle();
      }

      var colorAttr = await (db.select(db.attributeTypes)
            ..where((t) => t.code.equals('COLOR')))
          .getSingleOrNull();
      if (colorAttr == null) {
        final colorId = IdGenerator.uuid();
        await db.into(db.attributeTypes).insert(
          AttributeTypesCompanion.insert(
            id: colorId,
            name: 'Couleur',
            code: 'COLOR',
          ),
        );
        colorAttr = await (db.select(db.attributeTypes)
              ..where((t) => t.id.equals(colorId)))
            .getSingle();
      }

      // Default Sizes
      final defaultSizes = [
        'XS',
        'S',
        'M',
        'L',
        'XL',
        'XXL',
        '38',
        '40',
        '42',
        '44',
      ];
      final existingSizes = await (db.select(db.attributeValues)
            ..where((t) => t.attributeTypeId.equals(sizeAttr!.id)))
          .get();
      final existingSizeCodes = existingSizes.map((s) => s.code).toSet();
      for (final size in defaultSizes) {
        if (!existingSizeCodes.contains(size)) {
          await db.into(db.attributeValues).insert(
            AttributeValuesCompanion.insert(
              id: IdGenerator.uuid(),
              attributeTypeId: sizeAttr.id,
              value: size,
              code: size,
            ),
          );
        }
      }

      // Default Colors
      final defaultColors = [
        ('Noir', '#000000'),
        ('Blanc', '#FFFFFF'),
        ('Bleu Marine', '#000080'),
        ('Beige', '#F5F5DC'),
        ('Rouge', '#FF0000'),
        ('Gris', '#808080'),
        ('Vert Kaki', '#556B2F'),
      ];
      final existingColors = await (db.select(db.attributeValues)
            ..where((t) => t.attributeTypeId.equals(colorAttr!.id)))
          .get();
      final existingColorNames = existingColors.map((c) => c.value).toSet();
      for (final col in defaultColors) {
        if (!existingColorNames.contains(col.$1)) {
          await db.into(db.attributeValues).insert(
            AttributeValuesCompanion.insert(
              id: IdGenerator.uuid(),
              attributeTypeId: colorAttr.id,
              value: col.$1,
              code: col.$1,
            ),
          );
        }
      }

      // 7. Seed standard clothing categories
      final defaultCategories = [
        'Hauts & Chemises',
        'Pantalons & Jeans',
        'Robes & Ensembles',
        'Vestes & Manteaux',
        'Accessoires',
      ];
      final existingCats = await db.select(db.categories).get();
      final existingCatNames = existingCats.map((c) => c.name.toLowerCase()).toSet();
      for (final cat in defaultCategories) {
        if (!existingCatNames.contains(cat.toLowerCase())) {
          await db.into(db.categories).insert(
            CategoriesCompanion.insert(id: IdGenerator.uuid(), name: cat),
          );
        }
      }

      // 8. Save AppSettings to transition system into initialized state
      Future<void> saveSetting(String key, String value) async {
        final cur = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
        if (cur != null) {
          await (db.update(db.appSettings)..where((t) => t.key.equals(key))).write(
            AppSettingsCompanion(
              value: drift.Value(value),
              updatedAt: drift.Value(now),
            ),
          );
        } else {
          await db.into(db.appSettings).insert(
            AppSettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt: now,
            ),
          );
        }
      }

      await saveSetting(settingSetupCompleted, 'true');
      await saveSetting(settingSetupCompletedAt, now.toIso8601String());
      await saveSetting(settingCurrentStoreId, storeId);
      await saveSetting(settingCurrentRegisterId, cleanRegisterCode);
      await saveSetting(settingCurrentRegisterCode, cleanRegisterCode);
      await saveSetting(settingPrinterPaperWidth, paperWidthMm.toString());
      await saveSetting(settingCurrency, 'TND');
    });

    PosLogger.instance.info(
      'Init',
      'Trace POS setup completed successfully: store="$storeName", register="$cleanRegisterCode", admin="$cleanUsername"',
    );
  }
}
