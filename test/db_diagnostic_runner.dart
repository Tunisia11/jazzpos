// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void main() {
  final dllPath = Platform.environment['SQLITE_DLL_PATH'] ??
      'C:\\Users\\nourm\\Desktop\\jazzpos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));

  final dbPath = 'C:\\Users\\nourm\\AppData\\Roaming\\JazzPOS\\JAZZ POS\\database\\jazzpos.sqlite';
  print('Opening DB at: $dbPath');

  final db = sqlite3.open(dbPath);

  // 1. Integrity Check
  final integrity = db.select('PRAGMA integrity_check;');
  print('PRAGMA integrity_check: ${integrity.first.values.first}');

  // 2. Foreign Key Check
  final fkCheck = db.select('PRAGMA foreign_key_check;');
  print('PRAGMA foreign_key_check: ${fkCheck.isEmpty ? "CLEAN (0 errors)" : fkCheck.toString()}');

  // 3. Journal Mode
  final journalMode = db.select('PRAGMA journal_mode;');
  print('PRAGMA journal_mode: ${journalMode.first.values.first}');

  // 4. Foreign Keys enabled
  final fkEnabled = db.select('PRAGMA foreign_keys;');
  print('PRAGMA foreign_keys: ${fkEnabled.first.values.first}');

  // 5. Synchronous setting
  final synchronous = db.select('PRAGMA synchronous;');
  print('PRAGMA synchronous: ${synchronous.first.values.first}');

  // 6. Schema / User Version
  final userVersion = db.select('PRAGMA user_version;');
  print('PRAGMA user_version: ${userVersion.first.values.first}');

  // 7. List tables
  final tables = db.select("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;");
  print('Tables count: ${tables.length}');
  for (final row in tables) {
    print('  - ${row['name']}');
  }

  // 8. Record counts
  for (final table in ['companies', 'stores', 'registers', 'users', 'products', 'product_variants', 'sales', 'shifts']) {
    try {
      final count = db.select('SELECT count(*) as c FROM $table;');
      print('Table $table rows: ${count.first['c']}');
    } catch (e) {
      print('Table $table: $e');
    }
  }

  db.dispose();
  print('DB Diagnostic Completed Successfully.');
}
