<#
.SYNOPSIS
    Automated build and packaging pipeline for JAZZ POS Windows x64 releases.
#>

$ErrorActionPreference = "Stop"

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " JAZZ POS — WINDOWS X64 RELEASE BUILD & PACKAGING PIPELINE" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 1. Check Flutter
Write-Host "`n[1/5] Checking Flutter SDK..." -ForegroundColor Yellow
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK not found in PATH."
}

# 2. Pub get
Write-Host "`n[2/5] Resolving dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Test verification
Write-Host "`n[3/5] Executing automated test suite..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Error "Automated test suite failed! Release build aborted."
}

# 4. Build Windows Release
Write-Host "`n[4/5] Building Windows x64 release binaries..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter Windows compilation failed!"
}

# 5. Compile Inno Setup Installer
Write-Host "`n[5/5] Compiling Inno Setup Installer..." -ForegroundColor Yellow
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Test-Path $isccPath) {
    $distDir = Join-Path $PSScriptRoot "..\dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
    $issFile = Join-Path $PSScriptRoot "installer\jazzpos_setup.iss"
    & $isccPath $issFile
    Write-Host "`n[SUCCESS] Windows Installer created at dist\JazzPOS_Setup_v1.0.0.exe" -ForegroundColor Green
} else {
    Write-Host "`n[NOTICE] Inno Setup 6 compiler not detected. Raw release binaries available in build\windows\x64\runner\Release\" -ForegroundColor Yellow
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " BUILD COMPLETED SUCCESSFULLY" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
