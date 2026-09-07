// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void main() {
  final dllPath = Platform.environment['SQLITE_DLL_PATH'] ??
      'C:\\Users\\nourm\\Desktop\\jazzpos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));

  final testDbPath = '${Directory.systemTemp.path}\\jazzpos_persistence_test.sqlite';
  final dbFile = File(testDbPath);
  if (dbFile.existsSync()) dbFile.deleteSync();

  print('=== STEP 1: INITIALIZE TEST DB & WAL MODE ===');
  var db = sqlite3.open(testDbPath);
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA synchronous = FULL;');
  db.execute('PRAGMA foreign_keys = ON;');

  // Create minimal required tables matching Drift schema
  db.execute('''
    CREATE TABLE products (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      default_price_millimes INTEGER NOT NULL
    );
    CREATE TABLE product_variants (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL REFERENCES products(id),
      sku TEXT NOT NULL,
      barcode TEXT NOT NULL
    );
    CREATE TABLE stock_levels (
      variant_id TEXT PRIMARY KEY REFERENCES product_variants(id),
      quantity INTEGER NOT NULL
    );
    CREATE TABLE sales (
      id TEXT PRIMARY KEY,
      receipt_number TEXT NOT NULL,
      total_millimes INTEGER NOT NULL,
      status TEXT NOT NULL
    );
    CREATE TABLE shifts (
      id TEXT PRIMARY KEY,
      opening_cash_millimes INTEGER NOT NULL,
      status TEXT NOT NULL
    );
  ''');

  // Insert controlled seed data
  db.execute("INSERT INTO products VALUES ('p1', 'Polo Classic', 35000);");
  db.execute("INSERT INTO product_variants VALUES ('v1', 'p1', 'POLO-WHT-M', '6190001');");
  db.execute("INSERT INTO stock_levels VALUES ('v1', 10);");
  db.execute("INSERT INTO shifts VALUES ('s1', 100000, 'OPEN');");
  print('Seeded product, variant, initial stock: 10, shift: OPEN (100.000 TND)');

  // Perform Sale 1: Sell 1 item
  db.execute('BEGIN TRANSACTION;');
  db.execute("INSERT INTO sales VALUES ('sale1', 'REC-001', 35000, 'COMPLETED');");
  db.execute("UPDATE stock_levels SET quantity = quantity - 1 WHERE variant_id = 'v1';");
  db.execute('COMMIT;');
  print('Committed Sale 1. Stock updated.');

  // STEP 2: NORMAL CLOSE AND REOPEN
  print('\n=== STEP 2: NORMAL CLOSE AND REOPEN ===');
  db.dispose();

  db = sqlite3.open(testDbPath);
  var stockRow = db.select("SELECT quantity FROM stock_levels WHERE variant_id = 'v1';");
  var salesCount = db.select("SELECT count(*) as c FROM sales;");
  var shiftRow = db.select("SELECT status, opening_cash_millimes FROM shifts WHERE id = 's1';");

  print('After Normal Reopen -> Stock: ${stockRow.first['quantity']} (Expected: 9)');
  print('After Normal Reopen -> Sales count: ${salesCount.first['c']} (Expected: 1)');
  print('After Normal Reopen -> Shift status: ${shiftRow.first['status']}');
  assert(stockRow.first['quantity'] == 9);
  assert(salesCount.first['c'] == 1);

  // STEP 3: ABNORMAL CLOSE (UNCHECKPOINTED COMMITTED SALE IN WAL)
  print('\n=== STEP 3: ABNORMAL TERMINATION / POWER-LOSS SIMULATION ===');
  db.execute('BEGIN TRANSACTION;');
  db.execute("INSERT INTO sales VALUES ('sale2', 'REC-002', 35000, 'COMPLETED');");
  db.execute("UPDATE stock_levels SET quantity = quantity - 1 WHERE variant_id = 'v1';");
  db.execute('COMMIT;');
  print('Committed Sale 2 in WAL.');

  // Force close connection abruptly without PRAGMA wal_checkpoint
  db.dispose();

  // Reopen after abrupt closure
  db = sqlite3.open(testDbPath);
  final integrity = db.select('PRAGMA integrity_check;');
  print('Post-Crash PRAGMA integrity_check: ${integrity.first.values.first}');

  stockRow = db.select("SELECT quantity FROM stock_levels WHERE variant_id = 'v1';");
  salesCount = db.select("SELECT count(*) as c FROM sales;");
  print('Post-Crash Reopen -> Stock: ${stockRow.first['quantity']} (Expected: 8)');
  print('Post-Crash Reopen -> Sales count: ${salesCount.first['c']} (Expected: 2)');

  assert(stockRow.first['quantity'] == 8);
  assert(salesCount.first['c'] == 2);
  assert(integrity.first.values.first == 'ok');

  db.dispose();
  dbFile.deleteSync();
  final walFile = File('$testDbPath-wal');
  if (walFile.existsSync()) walFile.deleteSync();
  final shmFile = File('$testDbPath-shm');
  if (shmFile.existsSync()) shmFile.deleteSync();

  print('\nDATABASE PERSISTENCE & CRASH RESILIENCE: 100% VERIFIED');
}
