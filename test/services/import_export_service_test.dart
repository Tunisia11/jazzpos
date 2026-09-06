import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/catalog_service.dart';
import 'package:jazzpos/domain/services/import_export_service.dart';
import 'package:jazzpos/domain/services/inventory_service.dart';

void main() {
  late AppDatabase db;
  late InventoryService inventory;
  late ImportExportService service;
  late String storeId;
  late String ownerId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = InventoryService(db);
    service = ImportExportService(db, CatalogService(db, inventory), inventory);
    final now = DateTime.now();
    final companyId = IdGenerator.uuid();
    storeId = IdGenerator.uuid();
    ownerId = IdGenerator.uuid();
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: companyId,
            name: 'Jazz',
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
            name: 'Store',
            code: 'STORE',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.stockLocations)
        .insert(
          StockLocationsCompanion.insert(
            id: IdGenerator.uuid(),
            storeId: storeId,
            name: 'Shop floor',
            code: 'SHOP',
            locationType: AppConstants.locationShopFloor,
            isDefault: const drift.Value(true),
          ),
        );
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: ownerId,
            username: 'owner',
            displayName: 'Owner',
            role: AppRoles.owner,
            pinHash: 'hash',
            pinSalt: 'salt',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  test('malformed values reject only their rows with exact reasons', () async {
    const csv = '''Product Name;SKU;Barcode;Cost Price TND;Sale Price TND;Stock
Bad price;A;100;2.000;oops;4
Negative stock;B;200;2.000;4.000;-1
Too precise;C;300;2.000;4.0001;2
Valid;D;400;2.000;4.000;3''';

    final preview = await service.previewCsvImport(csv);

    expect(preview.totalRows, 4);
    expect(preview.validRows, 1);
    expect(preview.invalidRows, 3);
    expect(preview.previews[0].errorMessage, contains('Invalid sale price'));
    expect(preview.previews[1].errorMessage, contains('non-negative'));
    expect(preview.previews[2].errorMessage, contains('3 decimal'));
  });

  test(
    'semicolon import commits atomically and export is round-trip compatible',
    () async {
      const csv =
          '''Product Name;SKU;Barcode;Cost Price TND;Sale Price TND;Stock
Chemise;CH-1;619000000001;12.500;29.900;7''';
      final preview = await service.previewCsvImport(csv);
      expect(preview.validRows, 1);

      await service.commitImport(
        preview: preview,
        fileName: 'catalog.csv',
        actorId: ownerId,
        storeId: storeId,
      );

      final variant = await db.select(db.productVariants).getSingle();
      expect(variant.costPriceOverrideMillimes, 12500);
      expect(variant.salePriceOverrideMillimes, 29900);
      expect(await inventory.getStock(variant.id), 7);

      final exported = await service.exportCatalogCsv();
      expect(exported, startsWith('Product Name;SKU;Barcode;'));
      expect(
        exported,
        contains('Chemise;CH-1;619000000001;29.900;12.500;7;ACTIVE'),
      );
    },
  );
}
