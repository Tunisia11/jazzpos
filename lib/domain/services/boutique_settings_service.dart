import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:tracepos/core/constants/permissions.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/permission_guard.dart';

class BoutiqueSettings {
  final String name;
  final String? logoPath;
  final String? address;
  final String? phone;
  final String? email;
  final String? fiscalId;
  final String currency;
  final String? receiptHeader;
  final String? receiptFooter;

  const BoutiqueSettings({
    required this.name,
    this.logoPath,
    this.address,
    this.phone,
    this.email,
    this.fiscalId,
    this.currency = 'TND',
    this.receiptHeader,
    this.receiptFooter = 'Merci de votre visite ! À bientôt.',
  });

  BoutiqueSettings copyWith({
    String? name,
    String? logoPath,
    String? address,
    String? phone,
    String? email,
    String? fiscalId,
    String? currency,
    String? receiptHeader,
    String? receiptFooter,
  }) {
    return BoutiqueSettings(
      name: name ?? this.name,
      logoPath: logoPath ?? this.logoPath,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      fiscalId: fiscalId ?? this.fiscalId,
      currency: currency ?? this.currency,
      receiptHeader: receiptHeader ?? this.receiptHeader,
      receiptFooter: receiptFooter ?? this.receiptFooter,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'logoPath': logoPath,
    'address': address,
    'phone': phone,
    'email': email,
    'fiscalId': fiscalId,
    'currency': currency,
    'receiptHeader': receiptHeader,
    'receiptFooter': receiptFooter,
  };

  factory BoutiqueSettings.fromJson(Map<String, dynamic> json) => BoutiqueSettings(
    name: (json['name'] as String?)?.trim() ?? 'Trace POS Boutique',
    logoPath: json['logoPath'] as String?,
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    fiscalId: json['fiscalId'] as String?,
    currency: (json['currency'] as String?) ?? 'TND',
    receiptHeader: json['receiptHeader'] as String?,
    receiptFooter: (json['receiptFooter'] as String?) ?? 'Merci de votre visite ! À bientôt.',
  );
}

class BoutiqueSettingsService {
  final AppDatabase db;

  BoutiqueSettingsService(this.db);

  File get _configFile {
    final baseDir = AppPaths.instance.isInitialized
        ? AppPaths.instance.baseDir.path
        : Directory.current.path;
    return File(p.join(baseDir, 'boutique_config.json'));
  }

  /// Load current boutique settings, combining JSON config with database Company record
  Future<BoutiqueSettings> loadSettings() async {
    Map<String, dynamic> json = {};
    try {
      final file = _configFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        json = Map<String, dynamic>.from(jsonDecode(content) as Map);
      }
    } catch (e) {
      PosLogger.instance.warning('BoutiqueSettings', 'Could not read boutique_config.json: $e');
    }

    final company = await (db.select(db.companies)..limit(1)).getSingleOrNull();

    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : (company?.name.trim().isNotEmpty == true ? company!.name.trim() : 'Trace POS Boutique');

    return BoutiqueSettings(
      name: name,
      logoPath: json['logoPath'] as String?,
      address: json['address'] as String? ?? company?.address,
      phone: json['phone'] as String? ?? company?.phone,
      email: json['email'] as String?,
      fiscalId: json['fiscalId'] as String? ?? company?.fiscalId,
      currency: (json['currency'] as String?) ?? 'TND',
      receiptHeader: json['receiptHeader'] as String?,
      receiptFooter: (json['receiptFooter'] as String?) ?? 'Merci de votre visite ! À bientôt.',
    );
  }

  /// Save settings to JSON config and synchronize with SQLite Company and Store
  Future<void> saveSettings(
    BoutiqueSettings settings, {
    required String actorId,
  }) async {
    await PermissionGuard.requirePermission(
      db,
      actorId,
      AppPermissions.manageSettings,
    );
    // 1. Persist to JSON config
    try {
      final file = _configFile;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (e) {
      PosLogger.instance.error('BoutiqueSettings', 'Failed to write boutique_config.json: $e');
      throw PosException('Could not save store settings to disk: $e');
    }

    // 2. Synchronize SQLite Company & Store
    final now = DateTime.now();
    await db.transaction(() async {
      final existingCompanies = await db.select(db.companies).get();
      String companyId;
      if (existingCompanies.isNotEmpty) {
        companyId = existingCompanies.first.id;
        await (db.update(db.companies)..where((t) => t.id.equals(companyId))).write(
          CompaniesCompanion(
            name: drift.Value(settings.name.trim()),
            fiscalId: drift.Value(settings.fiscalId?.trim()),
            phone: drift.Value(settings.phone?.trim()),
            address: drift.Value(settings.address?.trim()),
            updatedAt: drift.Value(now),
          ),
        );
      } else {
        companyId = IdGenerator.uuid();
        await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: settings.name.trim(),
            fiscalId: drift.Value(settings.fiscalId?.trim()),
            phone: drift.Value(settings.phone?.trim()),
            address: drift.Value(settings.address?.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // Update primary store if present
      final store = await (db.select(db.stores)..limit(1)).getSingleOrNull();
      if (store != null) {
        await (db.update(db.stores)..where((t) => t.id.equals(store.id))).write(
          StoresCompanion(
            name: drift.Value(settings.name.trim()),
            address: drift.Value(settings.address?.trim()),
            phone: drift.Value(settings.phone?.trim()),
            updatedAt: drift.Value(now),
          ),
        );
      }
    });

    PosLogger.instance.info('BoutiqueSettings', 'Saved boutique settings: ${settings.name}');
  }
}
