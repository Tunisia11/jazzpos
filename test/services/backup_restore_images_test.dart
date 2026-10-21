import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory rootDir;
  late Directory backupDir;
  late File databaseFile;
  late AppDatabase liveDb;
  late BackupService service;

  setUp(() async {
    rootDir = await Directory.systemTemp.createTemp('jazzpos_pkg_backup_');
    await AppPaths.instance.initialize(customBaseDir: rootDir);

    backupDir = Directory(p.join(rootDir.path, 'backups'));
    await backupDir.create(recursive: true);

    databaseFile = File(p.join(rootDir.path, 'live.sqlite'));
    liveDb = AppDatabase(NativeDatabase(databaseFile));

    service = BackupService(
      liveDb,
      backupDirectory: backupDir,
      databaseFilePath: databaseFile.path,
      baseDirectory: rootDir,
    );

    final now = DateTime.now();
    await liveDb.into(liveDb.users).insert(
      UsersCompanion.insert(
        id: 'test_admin',
        username: 'admin1',
        displayName: 'Test Admin',
        role: 'OWNER',
        pinHash: 'hash',
        pinSalt: 'salt',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await liveDb.into(liveDb.users).insert(
      UsersCompanion.insert(
        id: 'legacy_admin',
        username: 'admin2',
        displayName: 'Legacy Admin',
        role: 'OWNER',
        pinHash: 'hash',
        pinSalt: 'salt',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await liveDb.close();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  });

  test('Creates a self-contained .zip backup bundling database, manifest, and product images', () async {
    final now = DateTime.now();

    // 1. Populate database with products
    await liveDb.into(liveDb.products).insert(
      ProductsCompanion.insert(
        id: 'prod_alpha',
        name: 'Alpha Product',
        imageUrl: const drift.Value('images/products/prod_alpha/main.jpg'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await liveDb.into(liveDb.products).insert(
      ProductsCompanion.insert(
        id: 'prod_beta',
        name: 'Beta Product',
        imageUrl: const drift.Value('images/products/prod_beta/main.png'),
        createdAt: now,
        updatedAt: now,
      ),
    );


    // 2. Populate product images on disk
    final alphaDir = Directory(p.join(AppPaths.instance.productImagesDir.path, 'prod_alpha'));
    await alphaDir.create(recursive: true);
    final alphaImg = img.Image(width: 100, height: 100);
    img.fill(alphaImg, color: img.ColorRgb8(255, 0, 0));
    await File(p.join(alphaDir.path, 'main.jpg')).writeAsBytes(img.encodeJpg(alphaImg));
    await File(p.join(alphaDir.path, 'thumb.jpg')).writeAsBytes(img.encodeJpg(alphaImg));

    final betaDir = Directory(p.join(AppPaths.instance.productImagesDir.path, 'prod_beta'));
    await betaDir.create(recursive: true);
    final betaImg = img.Image(width: 50, height: 50);
    img.fill(betaImg, color: img.ColorRgb8(0, 255, 0));
    await File(p.join(betaDir.path, 'main.png')).writeAsBytes(img.encodePng(betaImg));

    // 3. Create local backup package
    final record = await service.createLocalBackup();
    expect(record.filePath.endsWith('.zip'), isTrue);
    expect(await File(record.filePath).exists(), isTrue);

    // 4. Inspect ZIP package contents
    final zipBytes = await File(record.filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    expect(archive.findFile('database.sqlite'), isNotNull);
    expect(archive.findFile('manifest.json'), isNotNull);
    expect(archive.findFile('images/products/prod_alpha/main.jpg'), isNotNull);
    expect(archive.findFile('images/products/prod_alpha/thumb.jpg'), isNotNull);
    expect(archive.findFile('images/products/prod_beta/main.png'), isNotNull);

    // 5. Validate the backup
    final isValid = await service.validateBackupFile(record.filePath);
    expect(isValid, isTrue);

    // 6. Mutate DB and wipe images to test restore
    await (liveDb.update(liveDb.products)..where((t) => t.id.equals('prod_alpha')))
        .write(const ProductsCompanion(name: drift.Value('Mutated Name')));
    await alphaDir.delete(recursive: true);
    expect(await alphaDir.exists(), isFalse);

    // 7. Restore backup
    final rollbackPath = await service.restoreBackup(
      record.filePath,
      'test_admin',
      confirmed: true,
    );
    expect(await File(rollbackPath).exists(), isTrue);

    // Verify images were restored onto filesystem
    expect(await File(p.join(alphaDir.path, 'main.jpg')).exists(), isTrue);
    expect(await File(p.join(alphaDir.path, 'thumb.jpg')).exists(), isTrue);

    // Verify database was restored
    final restoredDb = AppDatabase(NativeDatabase(databaseFile));
    try {
      final restoredProduct = await (restoredDb.select(restoredDb.products)
            ..where((t) => t.id.equals('prod_alpha')))
          .getSingle();
      expect(restoredProduct.name, 'Alpha Product');
    } finally {
      await restoredDb.close();
    }
  });

  test('Supports restoring legacy single-file .sqlite backups seamlessly', () async {
    final now = DateTime.now();

    // Create minimal valid legacy SQLite file
    await liveDb.into(liveDb.products).insert(
      ProductsCompanion.insert(
        id: 'legacy_prod',
        name: 'Legacy Product',
        createdAt: now,
        updatedAt: now,
      ),
    );


    final legacySqlitePath = p.join(backupDir.path, 'legacy_backup.sqlite');
    await liveDb.customStatement('VACUUM INTO ?;', [legacySqlitePath]);

    // Validate legacy sqlite backup
    final isValid = await service.validateBackupFile(legacySqlitePath);
    expect(isValid, isTrue);

    // Restore legacy sqlite backup
    final rollbackPath = await service.restoreBackup(
      legacySqlitePath,
      'legacy_admin',
      confirmed: true,
    );
    expect(await File(rollbackPath).exists(), isTrue);
  });
}
