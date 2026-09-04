import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// Creates a safe SQLite database connection with WAL mode and foreign keys enabled.
LazyDatabase createDatabaseConnection({String? customPath, bool inMemory = false}) {
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
      final dbFolder = await getApplicationSupportDirectory();
      final dir = Directory(p.join(dbFolder.path, 'database'));
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

    return NativeDatabase.createInBackground(
      dbFile,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
        rawDb.execute('PRAGMA synchronous = NORMAL;');
      },
    );
  });
}
