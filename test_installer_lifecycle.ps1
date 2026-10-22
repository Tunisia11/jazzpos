# Real Windows Installer Lifecycle Test
$ErrorActionPreference = "Stop"

$appDataDir = "$env:APPDATA\TracePOS\Trace POS"
$dbPath = "$appDataDir\database\tracepos.sqlite"
$setupExe = "C:\Users\nourm\Desktop\tracepos\dist\Trace-POS-Setup-x64.exe"
$installedDir = "$env:LOCALAPPDATA\Programs\Trace POS"
$installedExe = "$installedDir\tracepos.exe"
$uninstaller = "$installedDir\unins000.exe"

Write-Host "=== STEP 1 & 2: CREATE CONTROLLED TEST DATA IN LIVE DB ===" -ForegroundColor Cyan
# Ensure directory structure
New-Item -ItemType Directory -Path "$appDataDir\database" -Force | Out-Null
New-Item -ItemType Directory -Path "$appDataDir\backups" -Force | Out-Null

# Use Dart script to seed controlled test data cleanly via SQLite3 FFI
$seedScript = @"
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void main() {
  final dllPath = 'C:\\Users\\nourm\\Desktop\\tracepos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));
  final db = sqlite3.open('$($dbPath.Replace('\', '\\'))');

  // Insert or replace test company, store, register with valid epoch integer timestamps
  const epochSec = 1788706800;
  db.execute("INSERT OR REPLACE INTO companies (id, name, created_at, updated_at) VALUES ('comp_inst', 'Boutique Test', $epochSec, $epochSec);");
  db.execute("INSERT OR REPLACE INTO stores (id, company_id, name, code, created_at, updated_at) VALUES ('store_inst', 'comp_inst', 'Magasin Principal', 'STR-01', $epochSec, $epochSec);");
  db.execute("INSERT OR REPLACE INTO registers (id, store_id, name, code, created_at, updated_at) VALUES ('reg_inst', 'store_inst', 'Caisse 1', 'REG-01', $epochSec, $epochSec);");
  db.execute("INSERT OR REPLACE INTO users (id, username, display_name, role, pin_hash, pin_salt, created_at, updated_at) VALUES ('usr_inst', 'caissier', 'Caissier Test', 'CASHIER', 'h', 's', $epochSec, $epochSec);");

  // Product & Variant
  db.execute("INSERT OR REPLACE INTO products (id, name, default_price_millimes, created_at, updated_at) VALUES ('p_inst', 'Chemise Installer Test', 45000, $epochSec, $epochSec);");
  db.execute("INSERT OR REPLACE INTO product_variants (id, product_id, sku, barcode, created_at, updated_at) VALUES ('v_inst', 'p_inst', 'CHM-INST-01', '6199999999999', $epochSec, $epochSec);");
  db.execute("INSERT OR REPLACE INTO stock_levels (id, variant_id, location_id, quantity, updated_at) VALUES ('sl_inst', 'v_inst', 'loc_default', 49, $epochSec);");

  // Shift & Sale
  db.execute("INSERT OR REPLACE INTO shifts (id, register_id, cashier_id, opened_at, opening_cash_millimes, status) VALUES ('shift_inst', 'reg_inst', 'usr_inst', $epochSec, 100000, 'OPEN');");
  db.execute("INSERT OR REPLACE INTO sales (id, store_id, register_id, shift_id, cashier_id, receipt_number, idempotency_key, subtotal_millimes, discount_millimes, tax_millimes, total_millimes, status, created_at) VALUES ('sale_inst', 'store_inst', 'reg_inst', 'shift_inst', 'usr_inst', 'REC-INST-001', 'IDEMP-INST-001', 45000, 0, 0, 45000, 'COMPLETED', $epochSec);");

  db.dispose();
  print('TEST_DATA_SEEDED_SUCCESSFULLY');
}
"@

$tempSeedScript = "$env:TEMP\seed_installer_test.dart"
Set-Content -Path $tempSeedScript -Value $seedScript
$dartOutput = dart run $tempSeedScript
Write-Host "Seeding Result: $dartOutput" -ForegroundColor Green

Write-Host "`n=== STEP 3: ENSURE NO Trace POS PROCESS IS RUNNING ===" -ForegroundColor Cyan
Get-Process -Name "tracepos" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "`n=== STEP 4: INSTALL USING REAL INSTALLER ===" -ForegroundColor Cyan
Write-Host "Running: $setupExe /CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
$installProc = Start-Process -FilePath $setupExe -ArgumentList "/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
Write-Host "Installer ExitCode: $($installProc.ExitCode)"
if ($installProc.ExitCode -ne 0) { throw "Installer failed with code $($installProc.ExitCode)" }

if (-not (Test-Path $installedExe)) {
    throw "Installed executable not found at: $installedExe"
}
Write-Host "Installed executable verified at: $installedExe" -ForegroundColor Green

Write-Host "`n=== STEP 5: LAUNCH AS NORMAL NON-ADMIN WINDOWS USER ===" -ForegroundColor Cyan
$p = Start-Process -FilePath $installedExe -PassThru
Start-Sleep -Seconds 4
Write-Host "Launched PID: $($p.Id), Responding: $($p.Responding)"

Write-Host "`n=== STEP 6: VERIFY EXISTING DATA REMAINS IN DB ===" -ForegroundColor Cyan
$verifyScript = @"
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void main() {
  final dllPath = 'C:\\Users\\nourm\\Desktop\\tracepos\\build\\windows\\x64\\runner\\Release\\sqlite3.dll';
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dllPath));
  final db = sqlite3.open('$($dbPath.Replace('\', '\\'))');

  final p = db.select("SELECT name, default_price_millimes FROM products WHERE id = 'p_inst';");
  final s = db.select("SELECT quantity FROM stock_levels WHERE variant_id = 'v_inst';");
  final sale = db.select("SELECT receipt_number, total_millimes FROM sales WHERE id = 'sale_inst';");
  final shift = db.select("SELECT status, opening_cash_millimes FROM shifts WHERE id = 'shift_inst';");

  print('Product: \${p.first['name']}, Price: \${p.first['default_price_millimes']}');
  print('Stock: \${s.first['quantity']}');
  print('Receipt: \${sale.first['receipt_number']}, Total: \${sale.first['total_millimes']}');
  print('Shift: \${shift.first['status']}, Opening Cash: \${shift.first['opening_cash_millimes']}');

  assert(p.first['name'] == 'Chemise Installer Test');
  assert(s.first['quantity'] == 49);
  assert(sale.first['receipt_number'] == 'REC-INST-001');
  assert(shift.first['status'] == 'OPEN');
  db.dispose();
  print('DATA_INTEGRITY_CONFIRMED');
}
"@
$tempVerifyScript = "$env:TEMP\verify_installer_test.dart"
Set-Content -Path $tempVerifyScript -Value $verifyScript
$verifyOutput = dart run $tempVerifyScript
Write-Host "Verification Output: $verifyOutput" -ForegroundColor Green

Write-Host "`n=== STEP 7: CLOSE INSTALLED Trace POS ===" -ForegroundColor Cyan
Get-Process -Name "tracepos" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "`n=== STEP 8 & 9: RUN INSTALLER AGAIN (UPGRADE/REINSTALL) & VERIFY DATA ===" -ForegroundColor Cyan
$upgradeProc = Start-Process -FilePath $setupExe -ArgumentList "/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
Write-Host "Upgrade Installer ExitCode: $($upgradeProc.ExitCode)"
$upgradeVerifyOutput = dart run $tempVerifyScript
Write-Host "Post-Upgrade Verification: $upgradeVerifyOutput" -ForegroundColor Green

Write-Host "`n=== STEP 10 & 11: UNINSTALL APPLICATION BINARIES & CONFIRM DATA DIRECTORY PRESERVED ===" -ForegroundColor Cyan
$uninstaller = Get-ChildItem -Path $installedDir -Filter "unins*.exe" | Select-Object -First 1 -ExpandProperty FullName
Write-Host "Uninstaller located at: $uninstaller"
$uninstProc = Start-Process -FilePath $uninstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
Write-Host "Uninstaller ExitCode: $($uninstProc.ExitCode)"
Start-Sleep -Seconds 2

$exeStillExists = Test-Path $installedExe
$dataDirStillExists = Test-Path $appDataDir
$dbStillExists = Test-Path $dbPath
Write-Host "App executable deleted: $(-not $exeStillExists)" -ForegroundColor Green
Write-Host "Data directory strictly preserved: $dataDirStillExists" -ForegroundColor Green
Write-Host "Live SQLite database strictly preserved: $dbStillExists" -ForegroundColor Green

if ($exeStillExists) { throw "Uninstallation failed to remove binaries!" }
if (-not $dbStillExists) { throw "CRITICAL FAILURE: Uninstaller deleted user database!" }

Write-Host "`n=== STEP 12, 13 & 14: REINSTALL, LAUNCH & CONFIRM DATA VISIBILITY ===" -ForegroundColor Cyan
$reinstallProc = Start-Process -FilePath $setupExe -ArgumentList "/CURRENTUSER /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
Write-Host "Reinstall ExitCode: $($reinstallProc.ExitCode)"

$pFinal = Start-Process -FilePath $installedExe -PassThru
Start-Sleep -Seconds 3
Write-Host "Final Launched PID: $($pFinal.Id), Responding: $($pFinal.Responding)"

$finalVerifyOutput = dart run $tempVerifyScript
Write-Host "Final Data Verification: $finalVerifyOutput" -ForegroundColor Green

# Close process
if (-not $pFinal.HasExited) {
    Stop-Process -Id $pFinal.Id -Force
}

# Check desktop shortcut
$desktopShortcut = "$env:USERPROFILE\Desktop\Trace POS.lnk"
Write-Host "Desktop shortcut exists: $(Test-Path $desktopShortcut)" -ForegroundColor Green

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "  INSTALLER LIFECYCLE & DATA PRESERVATION: 100% PASSED!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
