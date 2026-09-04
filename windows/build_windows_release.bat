@echo off
setlocal enabledelayedexpansion

echo ====================================================================
echo  JAZZ POS — WINDOWS X64 RELEASE BUILD & PACKAGING SCRIPT
echo ====================================================================

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Flutter SDK not found in PATH!
    exit /b 1
)

echo [1/5] Cleaning previous build artifacts...
call flutter clean
if %errorlevel% neq 0 exit /b %errorlevel%

echo [2/5] Fetching Flutter dependencies...
call flutter pub get
if %errorlevel% neq 0 exit /b %errorlevel%

echo [3/5] Running automated tests...
call flutter test
if %errorlevel% neq 0 (
    echo [ERROR] Tests failed! Halting release build.
    exit /b %errorlevel%
)

echo [4/5] Compiling Windows x64 release executable...
call flutter build windows --release
if %errorlevel% neq 0 (
    echo [ERROR] Windows compilation failed!
    exit /b %errorlevel%
)

echo [5/5] Building Inno Setup Windows installer...
set ISCC="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if exist %ISCC% (
    if not exist "..\dist" mkdir "..\dist"
    %ISCC% "installer\jazzpos_setup.iss"
    if %errorlevel% equ 0 (
        echo [SUCCESS] Windows Installer created at dist\JazzPOS_Setup_v1.0.0.exe
    ) else (
        echo [WARNING] Inno Setup compilation reported warnings or errors.
    )
) else (
    echo [NOTICE] Inno Setup 6 not found at default path. Release binaries are in build\windows\x64\runner\Release
)

echo ====================================================================
echo  BUILD COMPLETE!
echo ====================================================================
