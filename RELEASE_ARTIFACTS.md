# Trace POS — RELEASE ARTIFACTS SPECIFICATION (RC1)

**Product**: Trace POS (Point de Vente Prêt-à-Porter)  
**Version**: `1.0.0-RC1`  
**Build Target**: Windows x64 (Desktop POS)  
**Release Date**: 2026-09-04  
**Target POS Machine**: POSBANK Apexa G / AnyPOS / Windows 10 & 11 IoT Enterprise LTSC  

---

## 1. RELEASE ARTIFACTS OVERVIEW

| Artifact Descriptor | Value / Path | Notes |
| :--- | :--- | :--- |
| **Application Version** | `1.0.0+1` (RC1) | Semantic versioning |
| **Windows Executable** | `tracepos.exe` | Compiled via Flutter Windows engine + MSVC v143 |
| **Raw Build Directory** | `build\windows\x64\runner\Release\` | Self-contained bundle including all DLLs and data folder |
| **Production Installer** | `dist\Trace-POS-Setup-x64.exe` | Inno Setup 6 solid LZMA2 compressed single-file installer |
| **Database Schema Version** | `1` | Managed by Drift ORM (`schemaVersion = 1`) |
| **Flutter SDK Version** | `3.38.7 • channel stable` | Dart SDK 3.10.7 |
| **Supported Windows Architectures** | `x64` (AMD64 / Intel 64-bit) | Windows 10 1809+, Windows 11, Windows IoT Enterprise |

---

## 2. PRODUCTION RUNTIME & FILESYSTEM HIERARCHY

```
C:\Program Files\Trace POS\                <-- APPLICATION BINARIES (Read-Only)
├── tracepos.exe                           <-- Win32 POS Entry Point
├── flutter_windows.dll                   <-- Flutter Desktop Embedder
├── sqlite3.dll                           <-- SQLite Native Library (sqlite3_flutter_libs)
├── screen_retriever_windows_plugin.dll   <-- Display DPI & Geometry Plugin
├── window_manager_plugin.dll             <-- Kiosk Window Controls Plugin
└── data\
    ├── icudtl.dat                        <-- Unicode Tables
    └── flutter_assets\                   <-- Application Assets, Shaders, Fonts

%APPDATA%\TracePOS\                        <-- MUTABLE RETAIL DATA (User-Level Write)
├── database\
│   ├── tracepos.sqlite                    <-- SQLite Source of Truth (WAL Mode, synchronous=FULL)
│   ├── tracepos.sqlite-wal                <-- Write-Ahead Log
│   └── tracepos.sqlite-shm                <-- Shared Memory Index
├── backups\
│   └── tracepos_backup_YYYYMMDD_HHMMSS.sqlite <-- Atomic Hot Snapshots (VACUUM INTO)
├── logs\
│   ├── tracepos.log                       <-- Active Diagnostic Log (Max 10MB, Redacted PINs)
│   └── tracepos.log.old                   <-- Rotated Historical Log
└── temp\                                 <-- Temporary CSV and Export Staging
```

---

## 3. CHECKSUMS & ARTIFACT IDENTIFIERS

- **Installer Name**: `Trace-POS-Setup-x64.exe`
- **Inno Setup AppID**: `{D37F8E8A-B26C-49E2-8BCF-7519E8F3C92B}`
- **Checksum Verification**: Computed in CI via PowerShell `Get-FileHash -Algorithm SHA256` and recorded in `dist/SHA256SUMS.txt`.

---

## 4. LIFECYCLE & UPGRADE GUARANTEES

1. **Clean Installation**:
   - Deploys binaries to `C:\Program Files\Trace POS\`.
   - Silent prerequisite verification for Microsoft Visual C++ 2015-2022 Redistributable (`vc_redist.x64.exe`).
   - Automatically initializes writable `%APPDATA%\TracePOS\` on first launch.
2. **In-Place Upgrade**:
   - New installer safely shuts down running `tracepos.exe`.
   - Overwrites binary files in `C:\Program Files\Trace POS\`.
   - **Guarantees 100% data preservation**: `%APPDATA%\TracePOS\` is strictly untouched.
   - On next boot, Drift verifies database schema and executes required migrations safely within transactions.
3. **Uninstallation Behavior**:
   - Removes application executable, DLLs, and shortcuts.
   - **Never deletes `%APPDATA%\TracePOS` silently**. Store sales history and audit journals are preserved.
