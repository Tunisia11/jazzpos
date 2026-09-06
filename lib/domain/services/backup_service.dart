import 'dart:convert';
import 'dart:io';
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

  BackupService(this.db, {Directory? backupDirectory, String? databaseFilePath})
    : _backupDirectoryOverride = backupDirectory,
      _databaseFilePathOverride = databaseFilePath;

  /// Create an atomic local SQLite backup snapshot
  Future<BackupRecord> createLocalBackup() async {
    final backupDir = _backupDirectoryOverride;
    if (backupDir == null) {
      await AppPaths.instance.initialize();
    } else if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final resolvedBackupDir = backupDir ?? AppPaths.instance.backupsDir;

    final timestampStr = DateFormat(
      'yyyyMMdd_HHmmss_SSS',
    ).format(DateTime.now());
    final backupFileName = 'jazzpos_backup_$timestampStr.sqlite';
    final backupFilePath = p.join(resolvedBackupDir.path, backupFileName);

    try {
      // VACUUM INTO creates a consistent snapshot while the live database is
      // in WAL mode. Never fall back to copying only the main database file:
      // that can omit committed WAL frames.
      await db.customStatement('VACUUM INTO ?;', [backupFilePath]);
    } catch (e) {
      throw PosException('Failed to create atomic backup: $e');
    }

    final backupFile = File(backupFilePath);
    final bytes = await backupFile.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final size = bytes.length;
    final recordId = IdGenerator.uuid();
    final now = DateTime.now();

    await db
        .into(db.backupRecords)
        .insert(
          BackupRecordsCompanion.insert(
            id: recordId,
            filePath: backupFilePath,
            fileSizeBytes: size,
            checksum: checksum,
            backupType: 'LOCAL_SNAPSHOT',
            status: const Value('COMPLETED'),
            createdAt: now,
          ),
        );

    // Enforce rotating retention: keep latest 10 backups
    await _enforceRetention(resolvedBackupDir, maxBackups: 10);

    PosLogger.instance.info(
      'Backup',
      'Created local backup snapshot: $backupFileName (${(size / 1024).toStringAsFixed(1)} KB)',
    );
    return (db.select(
      db.backupRecords,
    )..where((tbl) => tbl.id.equals(recordId))).getSingle();
  }

  Future<void> _enforceRetention(
    Directory backupDir, {
    int maxBackups = 10,
  }) async {
    try {
      final files = await backupDir
          .list()
          .where((e) => e is File && e.path.endsWith('.sqlite'))
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

  /// Validate a backup file before restoring
  Future<bool> validateBackupFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const ValidationException('Backup file does not exist');
    }
    if (await file.length() < 100) {
      throw const ValidationException('Backup file is corrupted or empty');
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
      throw ValidationException(
        'Database integrity check failed on backup: $e',
      );
    }

    return true;
  }

  /// Restore database from verified backup file
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
    await validateBackupFile(filePath);

    if (_databaseFilePathOverride == null) {
      await AppPaths.instance.initialize();
    }
    final targetDbPath =
        _databaseFilePathOverride ?? AppPaths.instance.databaseFilePath;
    if (p.canonicalize(filePath) == p.canonicalize(targetDbPath)) {
      throw const ValidationException(
        'The active database cannot be used as its own restore source.',
      );
    }

    // VACUUM INTO preserves all committed WAL content in a standalone rollback
    // snapshot before the active connection is closed.
    final currentDbFile = File(targetDbPath);
    final timestamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
    final rollbackPath = '$targetDbPath.pre_restore_$timestamp.sqlite';
    final stagedPath = '$targetDbPath.restore_pending_$timestamp.sqlite';
    if (await currentDbFile.exists()) {
      await db.customStatement('VACUUM INTO ?;', [rollbackPath]);
      await validateBackupFile(rollbackPath);
    }

    try {
      await File(filePath).copy(stagedPath);
      await validateBackupFile(stagedPath);

      // Close active database connections
      await db.close();

      // Remove sidecars only after a clean close/checkpoint, then replace the
      // main file with the already validated staged snapshot.
      final walFile = File('$targetDbPath-wal');
      final shmFile = File('$targetDbPath-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();
      await File(stagedPath).copy(targetDbPath);
      await validateBackupFile(targetDbPath);
      if (await File(stagedPath).exists()) await File(stagedPath).delete();

      PosLogger.instance.info(
        'Backup',
        'Database successfully restored by user $actorId. Rollback snapshot: $rollbackPath',
      );
      return rollbackPath;
    } catch (e) {
      // Rollback on failure
      PosLogger.instance.error('Backup', 'Restore failed. Rolling back...', e);
      final rollbackFile = File(rollbackPath);
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(targetDbPath);
      }
      final stagedFile = File(stagedPath);
      if (await stagedFile.exists()) await stagedFile.delete();
      throw PosException('Database restore failed: $e');
    }
  }

  /// Get backup history
  Future<List<BackupRecord>> getBackupHistory() async {
    return (db.select(
      db.backupRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }
}
