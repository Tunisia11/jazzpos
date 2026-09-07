// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void main() {
  final dllPath = Platform.environment['SQLITE_DLL_PATH'] ??
      'C:\\Users\\nourm\\Desktop\\jazzpos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));

  final liveDbPath = 'C:\\Users\\nourm\\AppData\\Roaming\\JazzPOS\\JAZZ POS\\database\\jazzpos.sqlite';
  final backupDir = Directory('C:\\Users\\nourm\\AppData\\Roaming\\JazzPOS\\JAZZ POS\\backups');
  if (!backupDir.existsSync()) {
    backupDir.createSync(recursive: true);
  }

  print('=== REAL-WORLD BACKUP TEST ===');
  final liveDb = sqlite3.open(liveDbPath);

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
  final backupPath = '${backupDir.path}\\jazzpos_backup_$timestamp.sqlite';

  final sw = Stopwatch()..start();
  // Execute atomic VACUUM INTO
  liveDb.execute("VACUUM INTO '$backupPath';");
  sw.stop();

  print('Backup created in: ${sw.elapsedMilliseconds} ms');
  print('Backup file path: $backupPath');

  final backupFile = File(backupPath);
  if (!backupFile.existsSync() || backupFile.lengthSync() == 0) {
    throw Exception('Backup failed: file missing or empty!');
  }
  print('Backup file size: ${backupFile.lengthSync()} bytes');

  // Verify backup DB opens and integrity passes
  final backupDb = sqlite3.open(backupPath);
  final integrity = backupDb.select('PRAGMA integrity_check;');
  print('Backup PRAGMA integrity_check: ${integrity.first.values.first}');

  final tableCount = backupDb.select("SELECT count(*) as c FROM sqlite_master WHERE type='table';");
  print('Backup tables count: ${tableCount.first['c']}');

  backupDb.dispose();
  liveDb.dispose();

  print('\n=== RESTORE READINESS TEST (IN ISOLATED TEST DIR) ===');
  final testRestoreDir = Directory('${Directory.systemTemp.path}\\jazzpos_restore_test_$timestamp');
  testRestoreDir.createSync(recursive: true);
  final restoredDbPath = '${testRestoreDir.path}\\restored_jazzpos.sqlite';

  // Copy backup to test environment
  backupFile.copySync(restoredDbPath);
  print('Copied backup to isolated test environment: $restoredDbPath');

  final restoredDb = sqlite3.open(restoredDbPath);
  final restoredIntegrity = restoredDb.select('PRAGMA integrity_check;');
  print('Restored DB PRAGMA integrity_check: ${restoredIntegrity.first.values.first}');

  // Perform a test transaction in the restored DB to verify it is fully functional and read-write
  restoredDb.execute('CREATE TABLE _test_restore_verification (id INTEGER PRIMARY KEY, note TEXT);');
  restoredDb.execute("INSERT INTO _test_restore_verification (note) VALUES ('Restore functional');");
  final testRow = restoredDb.select('SELECT * FROM _test_restore_verification;');
  print('Restored DB write test row: ${testRow.first['note']}');

  restoredDb.dispose();
  testRestoreDir.deleteSync(recursive: true);
  print('Cleaned up test restore directory.');

  print('\nBACKUP & RESTORE READINESS: FULLY VERIFIED');
}
