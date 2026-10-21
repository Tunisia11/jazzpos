# Trace POS

Offline-first point-of-sale for a fashion boutique, built with Flutter (Windows primary, macOS supported). Data lives in a local SQLite database; optional Supabase sync pushes sales and pulls catalog changes.

## Features
- Cashier screen with exact barcode lookup, size/colour variants, hold sale, discounts
- Returns and exchanges, shifts and Z-report, cash movements
- Inventory with an immutable stock-movement ledger, purchasing, physical counts
- Receipt printing (Windows spooler, macOS CUPS, network ESC/POS), cash drawer, barcode scanner
- Roles: owner, manager, cashier, stock manager, with manager-PIN override
- French, English and Arabic (RTL)
- Backups with integrity checks and restore

## Requirements
- Flutter 3.38.x (Dart ^3.10)
- Windows 10/11 x64 for the release build (Inno Setup 6 for the installer)

## Develop
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after changing drift tables
flutter analyze
flutter test
flutter run -d macos        # or -d windows
```

## Build
- Windows installer: `windows/build_windows_release.ps1 -VerifyInstall` (runs on Windows; also used by the CI workflow). Signing: see `docs/WINDOWS_CODE_SIGNING_GUIDE.md`.
- macOS DMG: `scripts/build_macos_dmg.sh`

## First run
The setup wizard creates the store, the register and the owner account. PINs are stored as salted PBKDF2 hashes; repeated wrong PINs lock the account temporarily.

## Cloud sync (optional)
Run `scripts/supabase_schema.sql` in your Supabase project, then enter the URL and key in Settings. Read the security notes at the top of that script before enabling it.

## Release and hardware checks
See `release_audit/` — notably `ONSITE_HARDWARE_ACCEPTANCE.md` for the physical scanner/printer/drawer checklist. Hardware must be verified on the target Windows machine before going live.
