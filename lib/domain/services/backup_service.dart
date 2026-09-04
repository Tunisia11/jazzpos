import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/data/database/app_database.dart';

class BackupService {
  final AppDatabase db;

  BackupService(this.db);

  /// Create an atomic local SQLite backup snapshot
  Future<BackupRecord> createLocalBackup() async {
    final appDir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(appDir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestampStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final backupFileName = 'jazzpos_backup_$timestampStr.sqlite';
    final backupFilePath = p.join(backupDir.path, backupFileName);

    try {
      // Use SQLite VACUUM INTO for online, zero-lock safe snapshot
      await db.customStatement('VACUUM INTO ?;', [backupFilePath]);
    } catch (e) {
      // Fallback: file copy
      final currentDbPath = p.join(appDir.path, 'database', 'jazzpos.sqlite');
      final currentFile = File(currentDbPath);
      if (await currentFile.exists()) {
        await currentFile.copy(backupFilePath);
      } else {
        throw PosException('Failed to create backup: $e');
      }
    }

    final backupFile = File(backupFilePath);
    final bytes = await backupFile.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final size = bytes.length;
    final recordId = IdGenerator.uuid();
    final now = DateTime.now();

    await db.into(db.backupRecords).insert(
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
    await _enforceRetention(backupDir, maxBackups: 10);

    PosLogger.instance.info('Backup', 'Created local backup snapshot: $backupFileName (${(size / 1024).toStringAsFixed(1)} KB)');
    return (db.select(db.backupRecords)..where((tbl) => tbl.id.equals(recordId))).getSingle();
  }

  Future<void> _enforceRetention(Directory backupDir, {int maxBackups = 10}) async {
    try {
      final files = await backupDir.list().where((e) => e is File && e.path.endsWith('.sqlite')).toList();
      if (files.length > maxBackups) {
        files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
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
      final tempDb = sqlite.sqlite3.open(filePath, mode: sqlite.OpenMode.readOnly);
      try {
        final result = tempDb.select("SELECT name FROM sqlite_master WHERE type='table';");
        final tableNames = result.map((row) => row['name'] as String).toSet();
        if (!tableNames.contains('products') || !tableNames.contains('sales') || !tableNames.contains('users')) {
          throw const ValidationException('Backup file is missing essential POS database tables');
        }
      } finally {
        tempDb.dispose();
      }
    } catch (e) {
      throw ValidationException('Database integrity check failed on backup: $e');
    }

    return true;
  }

  /// Restore database from verified backup file
  Future<void> restoreBackup(String filePath, String actorId) async {
    await validateBackupFile(filePath);

    final appDir = await getApplicationSupportDirectory();
    final targetDbPath = p.join(appDir.path, 'database', 'jazzpos.sqlite');

    // Create an emergency rollback copy of current DB
    final currentDbFile = File(targetDbPath);
    final rollbackPath = '$targetDbPath.pre_restore';
    if (await currentDbFile.exists()) {
      await currentDbFile.copy(rollbackPath);
    }

    try {
      // Close active database connections
      await db.close();

      // Replace database file
      await File(filePath).copy(targetDbPath);

      // Remove WAL and SHM files to ensure clean state
      final walFile = File('$targetDbPath-wal');
      final shmFile = File('$targetDbPath-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      PosLogger.instance.info('Backup', 'Database successfully restored from $filePath by user $actorId');
    } catch (e) {
      // Rollback on failure
      PosLogger.instance.error('Backup', 'Restore failed. Rolling back...', e);
      final rollbackFile = File(rollbackPath);
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(targetDbPath);
      }
      throw PosException('Database restore failed: $e');
    }
  }

  /// Get backup history
  Future<List<BackupRecord>> getBackupHistory() async {
    return (db.select(db.backupRecords)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }
}
