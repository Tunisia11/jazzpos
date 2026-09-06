# JAZZ POS release audit — 6 September 2026

## Verdict: Yellow

**No data-loss/financial blockers, but specific limitations remain.**

The final macOS release was built from the audited working tree. The audit did not alter an existing client database, run a destructive migration, reset data, or discard pre-existing uncommitted work. The original revision was `61278a6bc3cc6df29a46449de18ead89588852c2`; preserved baseline evidence is in `release_audit/evidence/`.

## Final artifact

| Item | Result |
| --- | --- |
| Product/version | JAZZ POS, `1.0.0+1` |
| Release artifact | `build/macos/Build/Products/Release/jazzpos.app` |
| Debug and release macOS builds | Passed |
| Release executable SHA-256 | `4999af1bd2e7b86ab1631c10189223112440e43d41ab0205bec35c97a0b45ce7` |
| Bundle signature verification | `codesign --verify --deep --strict` passed |
| Static analysis | `flutter analyze` passed with no issues |
| Automated tests | `flutter test` passed: 60 tests |
| Diff whitespace check | `git diff --check` passed |

The configured macOS app identifier is still `com.example.jazzpos`. Do not change it the day before an upgrade: a bundle-ID change can change the macOS sandbox path and make an existing database appear missing. Plan an identifier/data-path migration for a future signed, notarized release.

## Architecture and coverage

| Area | Finding |
| --- | --- |
| Runtime | Flutter 3.38.7 stable, Dart 3.10.7 |
| Desktop targets | macOS, Windows, Linux project targets |
| State/UI | Flutter/Riverpod; French, Arabic, English localization and RTL tests |
| Local data | Drift/SQLite schema v2, foreign keys, WAL, 5-second busy timeout, full synchronous mode by default |
| Money | Exact integer millimes; TND displayed to three decimals |
| Modules | Login/setup, checkout, catalog, inventory, purchases, returns/exchanges, labels, shifts/Z, reports, settings/backups |
| Hardware | Receipt/label/drawer/display/scanner abstractions exist; runtime defaults are simulated devices |

No schema migration was changed. The existing v1-to-v2 migration adds product/variant image and deleted fields.

## Fixed P0/P1 findings

| Priority | Issue | Resolution and evidence | Status |
| --- | --- | --- | --- |
| P0 | Financial reports omitted fully refunded sales but subtracted their refunds; cart discounts and returned COGS were wrong. | Reports include completed/partial/full-refund receipts, use receipt-level discount, and reverse returned COGS. Regression: gross 100.000, discount 15.000, refund 85.000, net/COGS/profit 0.000. | Fixed/tested |
| P0 | Stock-integrity rebuild could collapse transfer stock into one location. | Replays movements per source/destination location and repairs each cached level. Regression: Shop 10, transfer 4, repaired Shop 6 / Back Room 4. | Fixed/tested |
| P1 | Main-file SQLite backup could omit WAL frames; timestamps could collide; app paths were inconsistent. | Uses atomic `VACUUM INTO` only, millisecond names, and the same AppPaths root for database, logs and backups. A real file-backed snapshot was opened and validated. | Fixed/tested |
| P1 | Checkout could use a stale/closed/wrong-register shift; close summary could race a sale. | Checkout revalidates its open register shift in the transaction; shift calculation and close run in one transaction. | Fixed/tested |
| P1 | Receipt-linked returns could cumulatively refund more than the original line. | Prior refund total is checked against the original payable line. | Fixed/tested |
| P1 | Purchase receiving could duplicate or over-receive an order. | Order state, line identity, and remaining quantity are verified inside the transaction. | Fixed/tested |
| P1 | Receipt, label, test-print and setup flows exposed JAZZ FASHION/sample identity and a default owner PIN. | Printed brand comes from configured company. Setup is blank and requires company, store, register, location, owner identity and matching PIN. | Fixed/analyzed/tested |
| P1 | An inaccessible data folder could show a blank startup screen. | Startup presents a clear French permission/recovery view without moving data. The failure path was manually launched and inspected. | Fixed/manually verified |

## Financial, stock, cash, and backup evidence

- The suite verifies atomic sale/line/payment/movement/audit writes and idempotency against a duplicate pay click.
- The cash lifecycle test verifies opening 100.000 + pay-in 50.000 - pay-out 20.000 = expected/actual close 130.000 with zero difference. A second open shift and a double-close are rejected.
- Service tests verify sale stock deduction, sellable return restoration, damaged return routing, exchanges, SKU/barcode uniqueness, product edits with audited stock movements, and historical sale protection after archive.
- Negative stock is rejected under the configured `BLOCK` policy. The current store policy is a business/configuration decision and was not changed during audit.
- The backup test creates a persistent SQLite database, writes its schema, produces an atomic snapshot, then checks it is nonempty and contains essential tables. It does not restore over a live client database.

## What was executed

`flutter pub get`, `flutter analyze`, all 60 tests, macOS debug and release builds, release-bundle signature verification, normal macOS launch to the French login screen, inaccessible-data-directory launch to the friendly recovery UI, and real file-backed backup creation/validation.

The codebase was also reviewed for routes, services, schema/migrations, money representation, transactions, localization/RTL wiring, printer/scanner abstractions, imports, roles, paths, Windows files, release configuration and development identifiers.

## Remaining limitations

| Priority | Limitation | Tomorrow's safe action |
| --- | --- | --- |
| P1 | Hardware uses fake defaults. Real device transport/configuration was not found or tested. | Connect the actual receipt/label printer, drawer and scanner onsite and run their test actions before promising physical output. Sale data remains committed if printing fails. |
| P1 | Windows cannot be built/run from this macOS host. | Build/rehearse with the repository's Windows release workflow on Windows before Windows delivery. |
| P1 | Backup creation is validated; a restore round-trip was not performed against client-like data. | Rehearse restore only against a copied test data folder, never the only client database. |
| P1 | Negative stock warning/block behavior depends on store policy. | Set policy to BLOCK unless the client explicitly allows backorders; never reset negative stock merely to remove a display. |
| P2 | Bundle ID/copyright retain `com.example`; no custom notarization workflow was available. | Plan a signed/notarized uniquely identified distribution with deliberate data migration. |
| P2 | No complete manual matrix of every screen at 1280x720, 1366x768, 1440x900 and 1920x1080 in all locales was possible without client data/credentials. | Use French for financial demo; screen-check Arabic/English navigation before showing dense modules. |
| P2 | No client DB, physical devices, scanner timing, printer disconnect, or product-image filesystem was modified/tested. | Keep the first demo dataset controlled and run peripheral checks before live use. |

## Exact safe demo/install procedure

1. On the target machine, create a permanently writable user data folder. If `JAZZPOS_DATA_DIR` is set, point it there before first launch; never use a temporary folder.
2. For an upgrade, close the old app and copy the complete existing data folder first. Do not change the bundle identifier or run fresh setup against the existing database.
3. Start the final app. On a new install, fill every setup field with the actual client business identity and create a unique owner PIN.
4. In Settings, verify storage health and create a backup. Confirm a timestamped backup record appears and copy it off the machine.
5. Connect each real peripheral. Run receipt/label/drawer tests and scan a known barcode into checkout. If a device has not been integrated, demonstrate completed data and preview only.
6. Create a controlled product with unique SKU/barcode and stock 10. Confirm grid/search.
7. Open one cash shift with 100.000 TND. Sell one unit, preferably with a small cart discount. Confirm receipt preview, stock 9, and report values.
8. Return that receipt line once. Confirm stock 10, refund equals the payable line, and the financial report does not show a negative net value.
9. Receive a small purchase quantity once; confirm one stock increase and that a repeated receipt cannot duplicate stock.
10. Close the shift. Compare expected cash to opening + cash sales - cash refunds + pay-ins - pay-outs, then show the Z report.
11. Create a second backup, close normally, reopen, and verify product, stock, receipts, return and closed shift.

Do not demonstrate live restore against the only client data folder, physical printing that has not been configured, or Windows delivery from this macOS artifact.

