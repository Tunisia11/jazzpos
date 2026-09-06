import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/backup_service.dart';
import 'package:jazzpos/domain/services/report_service.dart';

void main() {
  late AppDatabase db;
  late BackupService backupService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backupService = BackupService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('BackupService Tests', () {
    test('Creates and validates a real atomic SQLite snapshot', () async {
      final backupDir = await Directory.systemTemp.createTemp(
        'jazzpos_backup_snapshot_',
      );
      final databaseFile = File('${backupDir.path}/live.sqlite');
      final fileDb = AppDatabase(NativeDatabase(databaseFile));
      final fileBackupService = BackupService(
        fileDb,
        backupDirectory: backupDir,
      );

      try {
        // Force Drift to create the full schema in a file-backed database.
        await fileDb.select(fileDb.products).get();

        final backup = await fileBackupService.createLocalBackup();
        final snapshot = File(backup.filePath);
        expect(await snapshot.exists(), isTrue);
        expect(await snapshot.length(), greaterThan(100));
        expect(
          await fileBackupService.validateBackupFile(snapshot.path),
          isTrue,
        );
      } finally {
        await fileDb.close();
        if (await backupDir.exists()) await backupDir.delete(recursive: true);
      }
    });

    test('Refuses invalid or corrupted backup files', () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/fake_corrupt_db.sqlite',
      );
      await tempFile.writeAsString(
        'This is not an SQLite database file at all!',
      );

      try {
        expect(
          () => backupService.validateBackupFile(tempFile.path),
          throwsA(isA<ValidationException>()),
        );
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    });

    test(
      'Restores a copied file-backed database and preserves rollback',
      () async {
        final root = await Directory.systemTemp.createTemp('jazzpos_restore_');
        final backupDir = Directory('${root.path}/backups');
        await backupDir.create();
        final databaseFile = File('${root.path}/live.sqlite');
        final liveDb = AppDatabase(NativeDatabase(databaseFile));
        final service = BackupService(
          liveDb,
          backupDirectory: backupDir,
          databaseFilePath: databaseFile.path,
        );
        final now = DateTime(2026, 9, 6, 10);

        try {
          await liveDb.transaction(() async {
            await liveDb
                .into(liveDb.companies)
                .insert(
                  CompaniesCompanion.insert(
                    id: 'company',
                    name: 'Original Company',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.stores)
                .insert(
                  StoresCompanion.insert(
                    id: 'store',
                    companyId: 'company',
                    name: 'Store',
                    code: 'STORE',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.registers)
                .insert(
                  RegistersCompanion.insert(
                    id: 'register',
                    storeId: 'store',
                    name: 'Register',
                    code: 'REG',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.users)
                .insert(
                  UsersCompanion.insert(
                    id: 'user',
                    username: 'owner',
                    displayName: 'Owner',
                    role: 'OWNER',
                    pinHash: 'hash',
                    pinSalt: 'salt',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.shifts)
                .insert(
                  ShiftsCompanion.insert(
                    id: 'shift',
                    registerId: 'register',
                    cashierId: 'user',
                    openedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.products)
                .insert(
                  ProductsCompanion.insert(
                    id: 'product',
                    name: 'Original Product',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.productVariants)
                .insert(
                  ProductVariantsCompanion.insert(
                    id: 'variant',
                    productId: 'product',
                    sku: 'SKU-1',
                    barcode: '619000000001',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.stockLocations)
                .insert(
                  StockLocationsCompanion.insert(
                    id: 'location',
                    storeId: 'store',
                    name: 'Shop',
                    code: 'SHOP',
                    locationType: AppConstants.locationShopFloor,
                  ),
                );
            await liveDb
                .into(liveDb.stockLevels)
                .insert(
                  StockLevelsCompanion.insert(
                    id: 'stock',
                    variantId: 'variant',
                    locationId: 'location',
                    quantity: const Value(9),
                    updatedAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.sales)
                .insert(
                  SalesCompanion.insert(
                    id: 'sale',
                    receiptNumber: 'REC-1',
                    storeId: 'store',
                    registerId: 'register',
                    shiftId: 'shift',
                    cashierId: 'user',
                    subtotalMillimes: 10000,
                    totalMillimes: 10000,
                    idempotencyKey: 'restore-fixture',
                    createdAt: now,
                  ),
                );
            await liveDb
                .into(liveDb.saleLines)
                .insert(
                  SaleLinesCompanion.insert(
                    id: 'line',
                    saleId: 'sale',
                    variantId: 'variant',
                    productName: 'Original Product',
                    variantDescription: 'Standard',
                    sku: 'SKU-1',
                    barcode: '619000000001',
                    quantity: 1,
                    unitPriceMillimes: 10000,
                    originalPriceMillimes: 10000,
                    totalMillimes: 10000,
                  ),
                );
            await liveDb
                .into(liveDb.salePayments)
                .insert(
                  SalePaymentsCompanion.insert(
                    id: 'payment',
                    saleId: 'sale',
                    paymentMethod: AppConstants.paymentCash,
                    amountMillimes: 10000,
                    createdAt: now,
                  ),
                );
          });

          final backup = await service.createLocalBackup();
          await (liveDb.update(liveDb.products)
                ..where((table) => table.id.equals('product')))
              .write(const ProductsCompanion(name: Value('Mutated Product')));
          await (liveDb.update(liveDb.stockLevels)
                ..where((table) => table.id.equals('stock')))
              .write(const StockLevelsCompanion(quantity: Value(999)));
          await (liveDb.update(
            liveDb.shifts,
          )..where((table) => table.id.equals('shift'))).write(
            const ShiftsCompanion(status: Value(AppConstants.shiftClosed)),
          );

          expect(
            () => service.restoreBackup(
              backup.filePath,
              'user',
              confirmed: false,
            ),
            throwsA(isA<ValidationException>()),
          );
          final rollbackPath = await service.restoreBackup(
            backup.filePath,
            'user',
            confirmed: true,
          );
          expect(await File(rollbackPath).exists(), isTrue);

          final restoredDb = AppDatabase(NativeDatabase(databaseFile));
          try {
            expect(
              (await restoredDb.select(restoredDb.products).getSingle()).name,
              'Original Product',
            );
            expect(
              (await restoredDb.select(restoredDb.stockLevels).getSingle())
                  .quantity,
              9,
            );
            expect(
              (await restoredDb.select(restoredDb.shifts).getSingle()).status,
              AppConstants.shiftOpen,
            );
            final report = await ReportService(restoredDb).getSalesReport(
              startDate: now.subtract(const Duration(hours: 1)),
              endDate: now.add(const Duration(hours: 1)),
            );
            expect(report.netSales, const Money.fromMillimes(10000));
          } finally {
            await restoredDb.close();
          }
        } finally {
          if (await root.exists()) await root.delete(recursive: true);
        }
      },
    );
  });
}
