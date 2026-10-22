$exe = "$env:LOCALAPPDATA\Programs\Trace POS\tracepos.exe"
$startupLog = "$env:APPDATA\TracePOS\Trace POS\logs\startup.log"
$dbFile = "$env:APPDATA\TracePOS\Trace POS\database\tracepos.sqlite"

Write-Host "============================================================"
Write-Host "Trace POS REAL WINDOWS 10x RELAUNCH & STABILITY VERIFICATION"
Write-Host "Target: $exe"
Write-Host "============================================================"

# Clear prior startup log to get fresh trace
if (Test-Path $startupLog) {
    Remove-Item $startupLog -Force
}

$relaunchTimes = @()

for ($i = 1; $i -le 10; $i++) {
    Write-Host "`n--- Launch #$i / 10 ---"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $exe -PassThru
    
    # Wait until process starts and milestone is reached or 5s timeout
    $ready = $false
    $timeoutSeconds = 5
    $checkSw = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($checkSw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        Start-Sleep -Milliseconds 250
        if (Test-Path $startupLog) {
            $lines = Get-Content $startupLog -Tail 15 -ErrorAction SilentlyContinue
            if ($lines -match "first_usable_screen OK") {
                $ready = $true
                break
            }
        }
    }
    $sw.Stop()
    
    $wsMb = [math]::Round($proc.WorkingSet64 / 1MB, 2)
    Write-Host "Launch #$i: Ready=$ready, WorkingSet=${wsMb}MB, Elapsed=$([math]::Round($sw.Elapsed.TotalMilliseconds))ms"
    
    if (-not $ready) {
        Write-Error "Launch #$i failed to reach first_usable_screen within ${timeoutSeconds}s!"
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        exit 1
    }
    
    $relaunchTimes += $sw.Elapsed.TotalMilliseconds
    
    # Graceful termination
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 500
    if (-not $proc.HasExited) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 300
}

$avg = [math]::Round(($relaunchTimes | Measure-Object -Average).Average)
Write-Host "`n>>> 10x Relaunch Test PASSED: 10/10 successful. Avg startup: ${avg}ms <<<"

Write-Host "`n============================================================"
Write-Host "TESTING FORCE-CLOSE CRASH RECOVERY"
Write-Host "============================================================"
$procCrash = Start-Process -FilePath $exe -PassThru
Start-Sleep -Milliseconds 1200
Write-Host "Simulating sudden kill/crash during active operation (PID: $($procCrash.Id))..."
$procCrash | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host "Relaunching immediately following sudden crash..."
$swPostCrash = [System.Diagnostics.Stopwatch]::StartNew()
$procRecovery = Start-Process -FilePath $exe -PassThru
$recovered = $false
$checkSw = [System.Diagnostics.Stopwatch]::StartNew()
while ($checkSw.Elapsed.TotalSeconds -lt 5) {
    Start-Sleep -Milliseconds 250
    if (Test-Path $startupLog) {
        $tail = Get-Content $startupLog -Tail 15 -ErrorAction SilentlyContinue
        if ($tail -match "first_usable_screen OK") {
            $recovered = $true
            break
        }
    }
}
$swPostCrash.Stop()
Write-Host "Post-crash recovery launch: Ready=$recovered, Elapsed=$([math]::Round($swPostCrash.Elapsed.TotalMilliseconds))ms"
$procRecovery | Stop-Process -Force

if (-not $recovered) {
    Write-Error "Post-crash recovery failed to reach first_usable_screen!"
    exit 1
}
Write-Host ">>> Force-Close Crash Recovery PASSED <<<"

Write-Host "`n============================================================"
Write-Host "VALIDATING DATABASE INTEGRITY & HEALTH"
Write-Host "Database: $dbFile"
Write-Host "============================================================"

$tempScript = "$PSScriptRoot\temp_db_check.dart"
@"
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final dbPath = '$($dbFile.Replace('\', '/'))';
  final db = sqlite3.open(dbPath);
  
  final integrity = db.select('PRAGMA integrity_check;');
  print('INTEGRITY_CHECK: ' + integrity.first.values.first.toString());
  
  final foreignKeys = db.select('PRAGMA foreign_key_check;');
  print('FOREIGN_KEY_VIOLATIONS: ' + foreignKeys.length.toString());
  
  final users = db.select('SELECT id, username, role, created_at, typeof(created_at) FROM users;');
  print('USERS_COUNT: ' + users.length.toString());
  for (final row in users) {
    print('USER: ' + row.values.join(' | '));
  }
  
  final products = db.select('SELECT count(*) as count FROM products;');
  print('PRODUCTS_COUNT: ' + products.first['count'].toString());
  
  final sales = db.select('SELECT count(*) as count FROM sales;');
  print('SALES_COUNT: ' + sales.first['count'].toString());

  db.dispose();
}
"@ | Out-File -FilePath $tempScript -Encoding utf8

$dartResult = & "C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe" run $tempScript
Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
Write-Host $dartResult

Write-Host "`n============================================================"
Write-Host "STARTUP LOG MILESTONES SUMMARY"
Write-Host "============================================================"
Get-Content $startupLog -Tail 40
