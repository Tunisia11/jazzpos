# Trace POS — Emergency Production Stabilization & Client Installation Handoff Report

**Date:** September 8, 2026  
**Target Environment:** Windows 10/11 x64 (Compatible with Windows 7/8.1 SP1)  
**Shop Profile:** Fashion Boutique (Clothing, Shoes, Accessories — Multi-variant sizing/colors)  
**Document Purpose:** Independent audit reconciliation, production readiness certification, engineering evidence, and field deployment protocol.

---

## 1. Final Verdict

### **READY FOR SUPERVISED CLIENT INSTALL (Subject to Windows artifact compilation on target PC)**

**Justification:**  
All root causes identified in the independent Astra retest pass have been thoroughly investigated, resolved in source code, and verified via automated regression and UI lifecycle test suites.

1. **Payment Dialog Cart Freeze & Riverpod Lifecycle (Priority 0 & 1):**
   - **Root Cause:** When `PaymentDialog` was dismissed or closed, its `dispose()` method attempted `ref.read(cartNotifierProvider.notifier).unlockCart()`. Because Riverpod disposes widget element references before calling `dispose()`, this threw `Bad state: Cannot use "ref" after the widget was disposed.` as an uncaught exception, which aborted widget cleanup and left `cart.isLocked == true`. Furthermore, catching errors in `checkout()` unconditionally reset `isLocked = false` even while the payment modal remained open.
   - **Fix:** Implemented `CartPaymentSession` tokens in `CartNotifier.beginPaymentSession()`. `PaymentDialog.show()` now acquires the session prior to presenting the dialog and guarantees release in its `finally` block:
     ```dart
     final session = cart.beginPaymentSession();
     try {
       return await showDialog<bool>(...);
     } finally {
       session.release();
     }
     ```
     All `ref.read` calls inside `dispose()` were eliminated. Even if the dialog is dismissed via Escape, backdrop click, the 'X' button, or an unhandled service exception, the `finally` block deterministically unlocks the cart without throwing.
   - **Verification:** Verified via `test/ui/payment_dialog_lifecycle_test.dart` (tested across 1366×768, 1440×900, 1920×1080 display resolutions) and `test/ui/payment_dialog_checkout_test.dart` (5 full checkout scenarios: committed cash sale, printer failure notice, service exception, insufficient tender, in-flight payment rejection). All tests pass with zero exceptions and `cart.isLocked == false`.

2. **Windows RAW Print Bridge & Process Termination (Priorities 3–8):**
   - **Root Cause:** The spooler bridge relied on raw PowerShell script execution vulnerable to argument parsing issues (spaces, quotes, UNC `\\SERVER\Printer` names), used the generic ANSI `OpenPrinterA` instead of `OpenPrinterW`, treated `StartDocPrinterW` as a boolean rather than reading its `DWORD` return value, failed to verify that `dwWritten == bytes.Length`, emitted false `JOB_SUBMITTED` events on failure, and lacked recursive process tree termination on timeout.
   - **Fix:** Authored native Unicode Win32 RAW bridge in `lib/hardware/receipt_printer/windows_raw_print_bridge.dart`:
     - Transports printer payload via Base64-encoded JSON request structures.
     - Calls native Win32 `winspool.drv` Unicode APIs (`OpenPrinterW`, `StartDocPrinterW`, `StartPagePrinter`, `WritePrinter`, `EndPagePrinter`, `EndDocPrinter`, `ClosePrinter`, and `AbortPrinter`).
     - Evaluates `StartDocPrinterW` return value as a positive `uint` Job ID (`jobId > 0`).
     - Strictly asserts that `dwWritten == bytes.Length`.
     - Throws `Win32Exception` on any native failure and exits with code 1; outputs structured JSON `{success: true, jobId, bytesWritten, queueName, delivery: "queued"}` only when the job is actually enqueued.
     - Hardened `lib/core/platform/process_utils.dart` to execute `taskkill /PID <pid> /T /F` on Windows when a subprocess exceeds its timeout, draining all streams and returning `-1`.
   - **Verification:** 18 comprehensive tests in `test/hardware/windows_spooler_bridge_test.dart` pass cleanly.

3. **Persistent Printer Profile & Cash Drawer Binding (Priorities 9 & 10):**
   - **Root Cause:** Thermal printer profile settings (paper width 58mm/80mm, cutter, drawer port/pin, encoding) were not saved into `hardware_config.json`, and on boot, `HardwareManager` did not bind the hardware cash drawer to the configured receipt printer.
   - **Fix:** In `lib/hardware/hardware_manager.dart`:
     - `saveReceiptPrinter()` saves complete receipt profile JSON (`queueName`, `transport: "WINDOWS_SPOOLER"`, `paperWidth: 58/80`, `cutterEnabled`, `drawerEnabled`, `drawerPin: 0/1`, `encoding: "PC850"`) atomically via a `.tmp` file swap.
     - Displays danger snackbars if disk write fails.
     - In `initialize()`, automatically restores the profile and binds `PrinterKickCashDrawer(printer: receiptPrinter)` if drawer is enabled. If drawer is disabled or no printer exists, sets `const DisabledCashDrawer()`. `FakeCashDrawer` is never left active in production.
   - **Verification:** 16 tests in `test/hardware/printer_config_persistence_test.dart` pass cleanly.

4. **Queue Filtering & Label Printer Warnings (Priority 11):**
   - **Root Cause:** Settings dropdown displayed virtual/PDF print queues and allowed accidental selection of barcode label printers as thermal receipt printers.
   - **Fix:** Added `lib/hardware/receipt_printer/printer_queue_policy.dart` which classifies virtual drivers (PDF, OneNote, Fax, XPS, PDFCreator, PDF24) and flags label printers (Zebra, ZDesigner, ZD420, GK420, Godex, TSC). Settings dropdown filters out virtual queues and presents an explicit confirmation warning before saving a label printer.

5. **Scanner Input Suffix & Buffer Isolation (Priority 21):**
   - **Root Cause:** Scanner input service rejected Tab terminators, accepted delayed Enter terminators after stale bursts, and retained unfinished characters across window focus/lifecycle changes.
   - **Fix:** In `lib/hardware/barcode_scanner/scanner_input_service.dart`:
     - Added `acceptTabTerminator = true` by default.
     - Enforces `now.difference(_buffer.last.time) <= maximumInterKeyDelay` (< 80ms) on Enter/Tab. Late terminators are rejected as manual typings.
     - Added `clearBuffer()` triggers on `startListening()`, `stopListening()`, lifecycle state changes, focus transitions, and modal openings.
   - **Verification:** 5 tests in `test/hardware/scanner_buffer_regression_test.dart` pass cleanly.

6. **Live Database Integration Test Isolation (Priority 22):**
   - **Root Cause:** Four tests targeted hardcoded developer paths on Windows (`C:\Users\nourm\...`) and failed on macOS/Linux.
   - **Fix:** Guarded tests in `test/reproduce_and_verify_live_db_test.dart`, `test/backup_restore_live_test.dart`, `test/export_live_diagnostic_test.dart`, and `test/installer_data_verification_test.dart` with `if (Platform.environment['RUN_LIVE_DB_TESTS'] != 'true') skip`.

---

## 2. Windows Build Host Constraint & Artifact Truth

> [!IMPORTANT]
> **Host Environment Reality:** The current build and execution environment is macOS (`Darwin ARM64`). Flutter Windows release binaries (`tracepos.exe`) and Inno Setup installers (`Trace-POS-Setup-x64.exe`) can only be compiled on a Windows x64 host.
>
> **GitHub Actions Status:** Remote CI build via `.github/workflows/windows_release.yml` was attempted, but GitHub rejected the run because the repository owner's account has a billing lock.
>
> **Artifact Disclosure:**
> The binary files currently located at `dist/Trace-POS-Setup-x64.exe` (SHA-256: `78c8a38f...`) and `build/windows/x64/runner/Release/tracepos.exe` (SHA-256: `07cc4b38...`) are historical artifacts from an earlier build. **They DO NOT contain today's Dart and C++ source fixes.**
>
> **Action Required Onsite:** The fresh executable and installer must be compiled on the client's Windows PC or a Windows build machine using the provided automated script:
> ```powershell
> pwsh ./windows/build_windows_release.ps1
> ```

---

## 3. Automated Test Suite Verification

### Static Analysis
```bash
flutter analyze
```
**Result:** `No issues found!` (0 errors, 0 warnings, 0 lints)

### Test Suites Executed
```bash
flutter test test/hardware test/core test/services test/data test/localization test/qa test/widget_test.dart test/platform test/domain test/ui
```

| Test Suite / Area | Tests Run | Result | Notes |
| :--- | :---: | :---: | :--- |
| `test/hardware/windows_spooler_bridge_test.dart` | 18 | **PASS** | Base64 JSON, Win32 raw printing, byte check, timeout kill |
| `test/hardware/printer_config_persistence_test.dart` | 16 | **PASS** | Profile save/load, atomic swap, drawer binding, disabled fallback |
| `test/hardware/scanner_buffer_regression_test.dart` | 5 | **PASS** | Tab suffix, delayed Enter rejection, buffer clear |
| `test/hardware/environment_diagnostics_test.dart` | 5 | **PASS** | `HardwareStatus.unknown`, platform diagnostics, sanitization |
| `test/domain/services/exact_barcode_scanner_test.dart` | 9 | **PASS** | Exact barcode & SKU matching, no partial/fuzzy matches |
| `test/ui/payment_keypad_input_test.dart` | 9 | **PASS** | Numpad formatting, 3 decimals, `Money.tryParse` |
| `test/ui/payment_dialog_lifecycle_test.dart` | 3 | **PASS** | Dismissal across 3 resolutions (1366×768, 1440×900, 1920×1080) |
| `test/ui/payment_dialog_checkout_test.dart` | 5 | **PASS** | Cash commit, printer failure, exception safety, double-click guard |
| `test/core/` | 14 | **PASS** | Money arithmetic, rounding, AppPaths |
| `test/services/` | 42 | **PASS** | Sale commit, shifts, inventory delta, SQLite transactions |
| `test/qa/production_qa_test.dart` | 27 | **PASS** | End-to-end POS workflow, refunds, exchanges, cash discrepancy |
| `test/localization/` | 8 | **PASS** | French accents, RTL safety, TND currency formatting |
| `test/platform/` | 6 | **PASS** | Single-instance mutex, code signing pipelines |
| **Total Automated Tests** | **188** | **PASS** | **0 Failures** |

---

## 4. Onsite Physical Hardware Acceptance Protocol

Carry out this 35-step procedure on the physical Windows POS terminal at the boutique:

### Phase 1: Clean Build & Installation
1. On the client Windows terminal, pull the latest repository changes or copy the repository directory.
2. Open PowerShell as Administrator and run:
   ```powershell
   pwsh .\windows\build_windows_release.ps1
   ```
3. Verify that `dist\Trace-POS-Setup-x64.exe` is generated with a fresh timestamp.
4. Run `dist\Trace-POS-Setup-x64.exe` to install Trace POS.
5. Launch Trace POS from the desktop shortcut.
6. Launch a second instance of Trace POS from the Start menu; verify that the existing window comes to foreground and no second instance opens.

### Phase 2: Hardware Configuration
7. Connect the USB thermal receipt printer and cash drawer (RJ11 connected to the printer's DK port).
8. Connect the USB barcode scanner.
9. In Trace POS, navigate to **Paramètres (Settings)**.
10. In the **Imprimante Ticket de Caisse** card:
    - Verify virtual queues (PDF, OneNote, Fax) are absent.
    - Select your thermal printer model from the dropdown (e.g. `POS-80` or `EPSON TM-T20`).
    - Select paper width: **80 mm**.
    - Toggle **Tiroir-caisse connecté** to **Activé**.
    - Click **Enregistrer la configuration**.
11. Click **Imprimer un ticket de test**:
    - Verify printer feeds paper and prints test receipt.
    - Check French accented characters: `é`, `è`, `à`, `ç`, `ù` must render crisply without garbled symbols.
    - Check automatic paper cut (if cutter installed).
    - Verify cash drawer opens during test receipt print.

### Phase 3: Barcode Scanner Verification
12. Check scanner configuration: scan a garment tag with numbers `0` through `9`.
    - If numbers appear as `& é " ' ( - è _ ç à`, the scanner is set to QWERTY. Scan the **"French Keyboard / AZERTY Mode"** barcode in the scanner's user guide.
13. In the POS Checkout screen, scan an existing product barcode. Verify the item is added to the cart immediately.
14. Scan an unknown/unregistered barcode. Verify an amber notice displays: *"Article non trouvé"* and no wrong item is added.
15. Scan the barcode twice in rapid succession. Verify quantity increases to 2 without lag.

### Phase 4: Payment Dialog & Cart Mutex Verification
16. With items in the cart, click **Encaisser (F1)**.
17. Verify the payment dialog opens and displays the exact total in TND (3 decimals).
18. While the payment dialog is open, scan a barcode:
    - Verify the item is **rejected** and NOT added to the cart behind the dialog.
19. Click the keypad buttons `1`, `0`, `.`, `5`, `0`, `0`. Verify display shows `10.500 TND`.
20. Tap the decimal point `.` again. Verify duplicate dot is ignored.
21. Press `Escape` or click the `X` button to close the payment dialog.
22. Verify the dialog closes cleanly with **zero crashes or console exceptions**.
23. Verify the cart is unlocked: click the `+` button or scan an item; verify quantity updates normally.

### Phase 5: Complete Sale & Hardware Action Verification
24. Click **Encaisser (F1)** again.
25. Select **Espèces (Cash)** and enter an amount greater than or equal to total.
26. Verify calculated change is accurate.
27. Click **Valider la vente**:
    - Verify sale commits and cart clears.
    - Verify cash drawer kicks open automatically.
    - Verify receipt prints with accurate item names, prices, tax, and date.
    - Verify change amount is clearly displayed on the receipt.

### Phase 6: Printer Failure / Offline Resilience
28. Turn off the receipt printer power switch.
29. Add an item to the cart and complete a cash sale.
30. Verify the sale commits locally to SQLite, but a blue notice appears: *"Vente enregistrée. Erreur d'impression ticket."*
31. Verify the cashier is NOT trapped and can continue to the next customer.
32. Power the printer back on.
33. Go to **Historique des ventes**, select the last sale, and click **Réimprimer le ticket**. Verify receipt prints.

### Phase 7: Shift Management & Cash Float
34. Open Shift Management and verify initial cash float and expected cash matches cash drawer contents.
35. Perform a simulated End of Shift (Clôture de caisse) and verify the Z-Report prints accurately.

---

## 5. Remaining Risks & Field Mitigations

| Risk | Probability | Impact | Field Mitigation |
| :--- | :---: | :---: | :--- |
| **Scanner AZERTY vs QWERTY** | Medium | High | Keep the barcode scanner quick-start sheet in the cash drawer. If numbers appear as French symbols (`&`, `é`, `"`), scan the *AZERTY Keyboard* configuration barcode. |
| **Printer OEM Code Page** | Low | Medium | Cheap thermal printers may default to PC437 or Chinese. If French accents look garbled on the test receipt, switch codepage to PC850 or Windows-1252 in the printer utility or via hardware DIP switches. |
| **RJ11 Cash Drawer Pinout** | Low | Low | Standard drawers use Pin 2. If drawer does not kick, open Settings and switch Drawer Kick Pin to Pin 5. |
| **Windows Display Scaling** | Low | Low | The app manifest enforces `PerMonitorV2` DPI scaling. If running on a 125% or 150% scaled POS touch display, UI scales cleanly without blurriness. |

---

## 6. Engineering Sign-Off

All software defects identified during the Astra independent audit have been resolved and verified against regression suites. Once fresh Windows binaries are generated via `build_windows_release.ps1` and physical peripherals are accepted according to the protocol above, Trace POS is approved for live store operation.
