import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// Creates a resilient SQLite database connection for desktop POS environments.
///
/// DURABILITY & POWER LOSS REALITIES:
/// While SQLite in WAL mode with `PRAGMA synchronous = NORMAL;` provides strong
/// crash resilience and prevents structural database corruption in standard OS
/// crashes, NO filesystem or database engine can guarantee 100% zero data loss
/// under catastrophic physical power cut if:
///   1. The storage controller (cheap SSD or USB) lies about flushing write caches.
///   2. A power drop occurs mid-sector write (torn write).
///
/// To protect retail transactions in production:
///   - Hardware POS terminals should be backed by a UPS (battery buffer).
///   - If power instability is severe, set JAZZPOS_STRICT_SYNC=1 for synchronous = FULL.
///   - Periodic hot backups via VACUUM INTO provide disaster recovery.
///   - DatabaseIntegrityService verifies PRAGMA integrity_check and rebuilds
///     cached stock balances from the immutable stock_movements ledger.
LazyDatabase createDatabaseConnection({
  String? customPath,
  bool inMemory = false,
  bool strictSynchronous = false,
}) {
  return LazyDatabase(() async {
    if (inMemory) {
      return NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute('PRAGMA foreign_keys = ON;');
        },
      );
    }

    File dbFile;
    if (customPath != null) {
      dbFile = File(customPath);
    } else {
      final appDir = await getApplicationSupportDirectory();
      final baseDir =
          (Platform.isWindows && !appDir.path.toLowerCase().contains('jazzpos'))
          ? Directory(p.join(appDir.path, 'JazzPOS'))
          : appDir;
      final dir = Directory(p.join(baseDir.path, 'database'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      dbFile = File(p.join(dir.path, 'jazzpos.sqlite'));
    }

    // Apply native library setup on desktop if needed
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      } catch (_) {}
    }

    // In production retail POS, synchronous = FULL is the default to guarantee physical
    // storage synchronization (FlushFileBuffers/fsync) on every completed sale transaction.
    // Set JAZZPOS_RELAXED_SYNC=1 only for high-speed synthetic batch benchmarks.
    final isRelaxedSync = Platform.environment['JAZZPOS_RELAXED_SYNC'] == '1';

    return NativeDatabase.createInBackground(
      dbFile,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
        rawDb.execute(
          isRelaxedSync
              ? 'PRAGMA synchronous = NORMAL;'
              : 'PRAGMA synchronous = FULL;',
        );
      },
    );
  });
}
