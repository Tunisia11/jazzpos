import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';

class BackupService {
  final AppDatabase db;
  final Directory? _backupDirectoryOverride;
  final String? _databaseFilePathOverride;

  BackupService(
    this.db, {
    Directory? backupDirectory,
    String? databaseFilePath,
    Directory? baseDirectory,
  }) : _backupDirectoryOverride = backupDirectory,
       _databaseFilePathOverride = databaseFilePath,
       _baseDirectoryOverride = baseDirectory;

  final Directory? _baseDirectoryOverride;

  Future<void> _ensureInitialized() async {
    if (AppPaths.instance.isInitialized) return;
    try {
      if (_baseDirectoryOverride != null) {
        await AppPaths.instance.initialize(customBaseDir: _baseDirectoryOverride);
      } else if (_backupDirectoryOverride != null) {
        final parent = _backupDirectoryOverride.parent;
        await AppPaths.instance.initialize(customBaseDir: parent);
      } else {
        await AppPaths.instance.initialize();
      }
    } catch (_) {
      if (!AppPaths.instance.isInitialized) {
        final fallbackDir = Directory.systemTemp.createTempSync('jazzpos_app_');
        await AppPaths.instance.initialize(customBaseDir: fallbackDir);
      }
    }
  }

  /// Create an atomic local backup package (.zip) containing:
  /// - database.sqlite (consistent VACUUM INTO snapshot)
  /// - manifest.json (metadata, db checksum, images stats)
  /// - images/products/... (all managed product images)
  Future<BackupRecord> createLocalBackup() async {
    await _ensureInitialized();
    final backupDir = _backupDirectoryOverride;
    if (backupDir != null && !await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final resolvedBackupDir = backupDir ?? AppPaths.instance.backupsDir;

    final timestampStr = DateFormat(
      'yyyyMMdd_HHmmss_SSS',
    ).format(DateTime.now());
    final tempDbSnapshotPath = p.join(
      resolvedBackupDir.path,
      'temp_snapshot_$timestampStr.sqlite',
    );
    final backupZipFileName = 'jazzpos_backup_$timestampStr.zip';
    final backupZipFilePath = p.join(resolvedBackupDir.path, backupZipFileName);

    try {
      // 1. VACUUM INTO creates a consistent snapshot of the live SQLite database in WAL mode
      await db.customStatement('VACUUM INTO ?;', [tempDbSnapshotPath]);

      final tempDbFile = File(tempDbSnapshotPath);
      final dbBytes = await tempDbFile.readAsBytes();
      final dbChecksum = sha256.convert(dbBytes).toString();

      // 2. Gather managed product images
      final imagesDir = AppPaths.instance.productImagesDir;
      final imageFiles = <File>[];
      int imagesTotalBytes = 0;

      if (await imagesDir.exists()) {
        final allEntities = await imagesDir.list(recursive: true).toList();
        for (final entity in allEntities) {
          if (entity is File) {
            if (entity.path.endsWith('.tmp')) continue;
            final length = await entity.length();
            imageFiles.add(entity);
            imagesTotalBytes += length;
          }
        }
      }

      // 3. Create manifest
      final manifestMap = {
        'formatVersion': 1,
        'app': 'Trace POS',
        'createdAt': DateTime.now().toIso8601String(),
        'databaseChecksum': dbChecksum,
        'databaseSizeBytes': dbBytes.length,
        'schemaVersion': db.schemaVersion,
        'imagesCount': imageFiles.length,
        'imagesTotalBytes': imagesTotalBytes,
        'backupType': 'LOCAL_SNAPSHOT',
      };
      final manifestJson = jsonEncode(manifestMap);

      // 4. Build ZIP archive
      final archive = Archive();
      archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
      archive.addFile(ArchiveFile.string('manifest.json', manifestJson));

      final baseDirPath = AppPaths.instance.baseDir.path;
      for (final imgFile in imageFiles) {
        final rel = p.relative(imgFile.path, from: baseDirPath).replaceAll(r'\', '/');
        final bytes = await imgFile.readAsBytes();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw const PosException('Failed to compress backup package');
      }

      final zipFile = File(backupZipFilePath);
      await zipFile.writeAsBytes(zipBytes);

      // 5. Clean temporary SQLite snapshot
      if (await tempDbFile.exists()) {
        await tempDbFile.delete();
      }

      // 6. Record in database
      final zipChecksum = sha256.convert(zipBytes).toString();
      final recordId = IdGenerator.uuid();
      final now = DateTime.now();

      await db
          .into(db.backupRecords)
          .insert(
            BackupRecordsCompanion.insert(
              id: recordId,
              filePath: backupZipFilePath,
              fileSizeBytes: zipBytes.length,
              checksum: zipChecksum,
              backupType: 'LOCAL_SNAPSHOT',
              status: const Value('COMPLETED'),
              createdAt: now,
            ),
          );

      // 7. Enforce rotating retention: keep latest 10 backups
      await _enforceRetention(resolvedBackupDir, maxBackups: 10);

      PosLogger.instance.info(
        'Backup',
        'Created local backup package: $backupZipFileName (${(zipBytes.length / 1024).toStringAsFixed(1)} KB, ${imageFiles.length} images)',
      );

      return await (db.select(
        db.backupRecords,
      )..where((tbl) => tbl.id.equals(recordId))).getSingle();
    } catch (e) {
      try {
        final tempDbFile = File(tempDbSnapshotPath);
        if (await tempDbFile.exists()) await tempDbFile.delete();
      } catch (_) {}
      throw PosException('Failed to create atomic backup: $e');
    }
  }

  Future<void> _enforceRetention(
    Directory backupDir, {
    int maxBackups = 10,
  }) async {
    try {
      final files = await backupDir
          .list()
          .where(
            (e) =>
                e is File &&
                (e.path.endsWith('.zip') || e.path.endsWith('.sqlite')),
          )
          .toList();
      if (files.length > maxBackups) {
        files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
        );
        final toDelete = files.take(files.length - maxBackups);
        for (final f in toDelete) {
          await f.delete();
          PosLogger.instance.info('Backup', 'Rotated old backup: ${f.path}');
        }
      }
    } catch (e) {
      PosLogger.instance.warning('Backup', 'Error during backup rotation: $e');
    }
  }

  /// Validate a backup file before restoring (.zip package or legacy .sqlite)
  Future<bool> validateBackupFile(String filePath) async {
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        throw const ValidationException('Backup file does not exist');
      }
      if (await file.length() < 100) {
        throw const ValidationException('Backup file is corrupted or empty');
      }
    } on FileSystemException catch (e) {
      throw ValidationException('Cannot access backup file: ${e.message}');
    }

    if (filePath.endsWith('.zip')) {
      return _validateZipBackup(file);
    } else {
      return _validateSqliteFile(filePath);
    }
  }

  Future<bool> _validateZipBackup(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ValidationException('Invalid ZIP archive: $e');
    }

    final dbFile = archive.findFile('database.sqlite');
    if (dbFile == null) {
      throw const ValidationException('Backup archive is missing database.sqlite');
    }

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const ValidationException('Backup archive is missing manifest.json');
    }

    // Verify manifest JSON and checksum
    try {
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      final expectedChecksum = manifest['databaseChecksum'] as String?;
      if (expectedChecksum != null) {
        final actualChecksum = sha256.convert(dbFile.content as List<int>).toString();
        if (actualChecksum != expectedChecksum) {
          throw const ValidationException('Database checksum mismatch in backup archive');
        }
      }
    } catch (e) {
      if (e is ValidationException) rethrow;
      throw ValidationException('Corrupt manifest in backup archive: $e');
    }

    // Check entry paths for path traversal
    for (final entry in archive) {
      final name = entry.name.replaceAll(r'\', '/');
      if (name.contains('..') || name.startsWith('/')) {
        throw const ValidationException('Path traversal detected in backup archive');
      }
    }

    // Extract database.sqlite to temp file and run SQLite integrity checks
    final tempDbPath = p.join(
      AppPaths.instance.tempDir.path,
      'val_${IdGenerator.uuid()}.sqlite',
    );
    final tempDbFile = File(tempDbPath);
    try {
      await tempDbFile.writeAsBytes(dbFile.content as List<int>);
      await _validateSqliteFile(tempDbPath);
    } finally {
      if (await tempDbFile.exists()) {
        try {
          await tempDbFile.delete();
        } catch (_) {}
      }
    }

    return true;
  }

  Future<bool> _validateSqliteFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const ValidationException('SQLite database file does not exist');
    }

    // Verify SQLite Header ("SQLite format 3\000")
    final headerBytes = await file.openRead(0, 16).first;
    final header = ascii.decode(headerBytes);
    if (!header.startsWith('SQLite format 3')) {
      throw const ValidationException('File is not a valid SQLite database');
    }

    // Open read-only and verify critical tables exist
    try {
      final tempDb = sqlite.sqlite3.open(
        filePath,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        final result = tempDb.select(
          "SELECT name FROM sqlite_master WHERE type='table';",
        );
        final tableNames = result.map((row) => row['name'] as String).toSet();
        if (!tableNames.contains('products') ||
            !tableNames.contains('sales') ||
            !tableNames.contains('users')) {
          throw const ValidationException(
            'Backup file is missing essential POS database tables',
          );
        }
        final integrity = tempDb.select('PRAGMA integrity_check;');
        if (integrity.length != 1 || integrity.first.values.first != 'ok') {
          throw const ValidationException(
            'Backup failed SQLite integrity validation',
          );
        }
        final foreignKeyErrors = tempDb.select('PRAGMA foreign_key_check;');
        if (foreignKeyErrors.isNotEmpty) {
          throw const ValidationException(
            'Backup contains foreign-key violations',
          );
        }
        final versionRows = tempDb.select('PRAGMA user_version;');
        final schemaVersion = versionRows.first.values.first as int;
        if (schemaVersion < 1 || schemaVersion > db.schemaVersion) {
          throw ValidationException(
            'Unsupported backup schema version: $schemaVersion',
          );
        }
      } finally {
        tempDb.dispose();
      }
    } catch (e) {
      if (e is ValidationException) rethrow;
      throw ValidationException(
        'Database integrity check failed on backup: $e',
      );
    }

    return true;
  }

  /// Restore database (and product images if zip) from verified backup file
  Future<String> restoreBackup(
    String filePath,
    String actorId, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const ValidationException(
        'Explicit confirmation is required before restoring a backup.',
      );
    }
    await _ensureInitialized();
    await validateBackupFile(filePath);

    final targetDbPath =
        _databaseFilePathOverride ?? AppPaths.instance.databaseFilePath;
    if (p.canonicalize(filePath) == p.canonicalize(targetDbPath)) {
      throw const ValidationException(
        'The active database cannot be used as its own restore source.',
      );
    }

    final currentDbFile = File(targetDbPath);
    final timestamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
    final rollbackPath = '$targetDbPath.pre_restore_$timestamp.sqlite';
    final stagedPath = '$targetDbPath.restore_pending_$timestamp.sqlite';

    // Snapshot current active database
    if (await currentDbFile.exists()) {
      await db.customStatement('VACUUM INTO ?;', [rollbackPath]);
      await _validateSqliteFile(rollbackPath);
    }

    // Snapshot current product images for rollback
    final productImagesDir = AppPaths.instance.productImagesDir;
    final rollbackImagesDir = Directory(
      p.join(AppPaths.instance.tempDir.path, 'images_rollback_$timestamp'),
    );
    if (await productImagesDir.exists()) {
      await _copyDirectory(productImagesDir, rollbackImagesDir);
    }

    final stagedImagesDir = Directory(
      p.join(AppPaths.instance.tempDir.path, 'staged_restore_images_$timestamp'),
    );

    try {
      final isZip = filePath.endsWith('.zip');

      if (isZip) {
        // Unpack zip
        final zipBytes = await File(filePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);

        final dbArchiveFile = archive.findFile('database.sqlite');
        if (dbArchiveFile == null) {
          throw const ValidationException('Backup package is missing database.sqlite');
        }
        await File(stagedPath).writeAsBytes(dbArchiveFile.content as List<int>);

        // Unpack images into staged directory
        await stagedImagesDir.create(recursive: true);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final normalizedName = entry.name.replaceAll(r'\', '/');
          if (normalizedName.startsWith('images/products/')) {
            if (normalizedName.contains('..')) {
              throw const ValidationException('Path traversal detected in backup image entry');
            }
            final stagedOutPath = p.join(stagedImagesDir.path, p.normalize(normalizedName));
            final outFile = File(stagedOutPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          }
        }
      } else {
        // Legacy .sqlite file
        await File(filePath).copy(stagedPath);
      }

      await _validateSqliteFile(stagedPath);

      // Close active database connections
      await db.close();

      // Remove WAL/SHM sidecars
      final walFile = File('$targetDbPath-wal');
      final shmFile = File('$targetDbPath-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      // Replace active database file
      await File(stagedPath).copy(targetDbPath);
      await _validateSqliteFile(targetDbPath);
      if (await File(stagedPath).exists()) await File(stagedPath).delete();

      // If zip had images, deploy staged images into baseDir/images/products
      if (isZip && await stagedImagesDir.exists()) {
        final stagedProductImages = Directory(
          p.join(stagedImagesDir.path, 'images', 'products'),
        );
        if (await stagedProductImages.exists()) {
          await _copyDirectory(stagedProductImages, productImagesDir);
        }
        await stagedImagesDir.delete(recursive: true);
      }

      // Clean rollback images dir on success
      if (await rollbackImagesDir.exists()) {
        await rollbackImagesDir.delete(recursive: true);
      }

      PosLogger.instance.info(
        'Backup',
        'Database successfully restored by user $actorId. Rollback snapshot: $rollbackPath',
      );
      return rollbackPath;
    } catch (e) {
      PosLogger.instance.error('Backup', 'Restore failed. Rolling back...', e);
      // Rollback database
      final rollbackFile = File(rollbackPath);
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(targetDbPath);
      }
      // Rollback images
      if (await rollbackImagesDir.exists()) {
        if (await productImagesDir.exists()) {
          await productImagesDir.delete(recursive: true);
        }
        await _copyDirectory(rollbackImagesDir, productImagesDir);
        await rollbackImagesDir.delete(recursive: true);
      }
      final stagedFile = File(stagedPath);
      if (await stagedFile.exists()) await stagedFile.delete();
      if (await stagedImagesDir.exists()) await stagedImagesDir.delete(recursive: true);

      throw PosException('Database restore failed: $e');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  /// Get backup history
  Future<List<BackupRecord>> getBackupHistory() async {
    return (db.select(
      db.backupRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }
}
