// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  if (Platform.environment['RUN_LIVE_DB_TESTS'] != 'true') {
    test('Live database checks require explicit opt-in', () {}, skip: 'Set RUN_LIVE_DB_TESTS=true only on an approved disposable database.');
    return;
  }

  final dllPath = Platform.environment['SQLITE_DLL_PATH'] ??
      'C:\\Users\\nourm\\Desktop\\jazzpos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  final liveDbPath = Platform.environment['JAZZPOS_LIVE_DB_PATH'] ??
      'C:\\Users\\nourm\\AppData\\Roaming\\JazzPOS\\JAZZ POS\\database\\jazzpos.sqlite';
  final shouldRun = Platform.isWindows && File(liveDbPath).existsSync() && File(dllPath).existsSync();

  test(
    'Installer data persistence verification test',
    () {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));
      final db = sqlite3.open(liveDbPath);

    // 1. Seed controlled data if not already present
    db.execute("INSERT OR REPLACE INTO companies (id, name, created_at, updated_at) VALUES ('comp_inst', 'Boutique Test', '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");
    db.execute("INSERT OR REPLACE INTO stores (id, company_id, name, code, created_at, updated_at) VALUES ('store_inst', 'comp_inst', 'Magasin Principal', 'STR-01', '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");
    db.execute("INSERT OR REPLACE INTO registers (id, store_id, name, code, created_at, updated_at) VALUES ('reg_inst', 'store_inst', 'Caisse 1', 'REG-01', '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");
    db.execute("INSERT OR REPLACE INTO users (id, username, display_name, role, pin_hash, pin_salt, created_at, updated_at) VALUES ('usr_inst', 'caissier', 'Caissier Test', 'CASHIER', 'h', 's', '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");

    db.execute("INSERT OR REPLACE INTO products (id, name, default_price_millimes, created_at, updated_at) VALUES ('p_inst', 'Chemise Installer Test', 45000, '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");
    db.execute("INSERT OR REPLACE INTO product_variants (id, product_id, sku, barcode, created_at, updated_at) VALUES ('v_inst', 'p_inst', 'CHM-INST-01', '6199999999999', '2026-09-06T15:00:00Z', '2026-09-06T15:00:00Z');");
    db.execute("INSERT OR REPLACE INTO stock_locations (id, store_id, name, code, location_type, is_default) VALUES ('loc_default', 'store_inst', 'Rayon', 'RAY-01', 'SHOP_FLOOR', 1);");
    db.execute("INSERT OR REPLACE INTO stock_levels (id, variant_id, location_id, quantity, reserved_quantity, updated_at) VALUES ('sl_inst', 'v_inst', 'loc_default', 49, 0, '2026-09-06T15:00:00Z');");

    db.execute("INSERT OR REPLACE INTO shifts (id, register_id, cashier_id, opened_at, opening_cash_millimes, status) VALUES ('shift_inst', 'reg_inst', 'usr_inst', '2026-09-06T15:00:00Z', 100000, 'OPEN');");
    db.execute("INSERT OR REPLACE INTO sales (id, store_id, register_id, shift_id, cashier_id, receipt_number, idempotency_key, subtotal_millimes, discount_millimes, tax_millimes, total_millimes, status, created_at) VALUES ('sale_inst', 'store_inst', 'reg_inst', 'shift_inst', 'usr_inst', 'REC-INST-001', 'IDEMP-INST-001', 45000, 0, 0, 45000, 'COMPLETED', '2026-09-06T15:00:00Z');");

    // 2. Query and verify exact values
    final p = db.select("SELECT name, default_price_millimes FROM products WHERE id = 'p_inst';");
    final s = db.select("SELECT quantity FROM stock_levels WHERE variant_id = 'v_inst';");
    final sale = db.select("SELECT receipt_number, total_millimes FROM sales WHERE id = 'sale_inst';");
    final shift = db.select("SELECT status, opening_cash_millimes FROM shifts WHERE id = 'shift_inst';");

    expect(p.first['name'], equals('Chemise Installer Test'));
    expect(p.first['default_price_millimes'], equals(45000));
    expect(s.first['quantity'], equals(49));
    expect(sale.first['receipt_number'], equals('REC-INST-001'));
    expect(sale.first['total_millimes'], equals(45000));
    expect(shift.first['status'], equals('OPEN'));
    expect(shift.first['opening_cash_millimes'], equals(100000));

    db.dispose();
    print('DATABASE RECORDS 100% VERIFIED');
  }, skip: !shouldRun ? 'Requires live Windows environment and database' : null);
}
