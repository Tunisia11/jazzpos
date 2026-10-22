# Client handoff retest — 8 September 2026, 05:53–05:57 Tunis

**Verdict: RED for client trading. Several fixes are confirmed, but closing payment now leaves the cart locked. Existing Windows delivery binaries are unchanged.**

This retest assesses the changed working tree, not just the claims in `EMERGENCY_HANDOFF_REPORT.md`. Target remains the client's Windows fashion shop with USB/Bluetooth/network devices. Tests ran on macOS. No physical Windows scanner, receipt printer, label printer or drawer was exercised. Production source was not edited during this retest.

## Results

| Check | Current result |
|---|---|
| `flutter analyze` | PASS — no issues |
| Selected portable application suites, including new `test/domain` and `test/ui` tests | PASS — 141 tests |
| Independent retest probes | 7 passed, **1 failed** |
| Actual payment keypad: repeated decimal keys | PASS — no FormatException |
| Actual payment dialog: close and unlock | **FAIL — StateError; cart remains locked** |
| macOS release compilation | PASS — 56.6 MB application |
| Windows installer and executable | Same SHA-256 as the earlier audit |
| Windows native printing and hardware operation | Not tested |
| Source stability during test execution | No changes to the recorded source/test/native files |

The probe suite deliberately mixes regression expectations for repaired behavior with characterization checks for unresolved behavior. Its seven passes do not mean seven defects were fixed.

Portable-suite command:

```text
flutter test test/hardware test/core test/services test/data test/localization test/qa test/widget_test.dart test/platform test/domain test/ui --reporter expanded
```

Live database tests were not run. Their added Windows/file-existence conditions prevent execution here, but still allow some of them to mutate a developer's live database when those files exist on Windows. They need explicit opt-in and disposable test data before inclusion in an unrestricted release test command.

## Confirmed improvements

- **Exact scanner lookup:** `CartNotifier` now calls `findVariantByExactBarcode`. The independent reproduction that previously added SKU `SKU-123-OTHER` when scanning `123` now correctly returns false and leaves the cart empty. New tests cover leading zeroes, aliases, exact SKU matching and unknown codes.
- **Cart mutation guards:** most cart mutators reject updates when locked/processing, and checkout's barcode callback checks whether its route is current. These are meaningful improvements to the previous background-scan problem. The payment lifecycle defect below prevents full acceptance.
- **Payment decimal input:** the actual widget now survives pressing `.` twice. Existing keypad unit tests mirror the handler in a separate simulator; the independent widget test additionally exercises the real screen.
- **Printer classification:** the earlier Zebra ZD420 example is now excluded from receipt candidates.
- **Label printing honesty:** simulated label printing is explicitly disabled in Label Studio and a warning is shown. This fixes misleading success, but physical label printing is still unavailable.
- **Windows startup:** the source no longer calls `TerminateProcess` to handle a duplicate launch; it retries window activation and exits the second instance. Native Windows runtime behavior remains untested.
- **Windows manifest:** the correctly named `windows/runner/runner.exe.manifest` now exists.
- **Receipt transport:** file-copy submission has been replaced with C# P/Invoke calls to `winspool.drv`, including `WritePrinter` byte-count checking. This is an implementation improvement, not physical printing certification.
- **Queue selection:** Settings now offers manual queue selection and writes a receipt queue name to `hardware_config.json`. Profile/drawer persistence remains incomplete.
- **Image-path test:** the previously failing path-validation test now passes in the 141-test run.

## New confirmed blocker: canceling payment freezes the cart

Evidence: [payment_dialog.dart](/Users/macbookair/tracepos/lib/ui/screens/checkout/widgets/payment_dialog.dart:70).

`dispose()` calls `ref.read(cartNotifierProvider.notifier).unlockCart()`. Riverpod refuses use of this widget ref after disposal starts.

The independent test opens the real payment dialog, keeps its provider container alive, confirms the cart is locked, presses the real decimal key twice, and then clicks the close icon. It records:

```text
Payment close: error=Bad state: Cannot use "ref" after the widget was disposed.; cart.isLocked=true
```

This is a cashier-visible blocker: opening and canceling payment can prevent further scans, quantity edits and cart clearing. The failing test is not an artificial provider-shutdown case: the container remains alive while the modal is closed.

Fix the lock lifetime so it is released safely when the modal closes, including cancellation, navigation, failed checkout and successful checkout. Capture the notifier before disposal or manage the lock around the modal's returned future, and test the actual UI. Also preserve the intended lock while the payment modal remains active after a rejected sale; `CartNotifier.checkout()` currently clears `isLocked` in its catch path.

## Remaining printer and delivery problems

### 1. The available installers are still the previous artifacts

Recomputed hashes match the earlier audit exactly:

| Artifact | SHA-256 |
|---|---|
| `dist/Trace-POS-Setup-x64.exe` | `78c8a38f649e7e6bfa8ce826bd98fafc1a8efab567d2d9d92ceafe31a60b47c5` |
| `dist/Trace-POS-Setup-x64.exe` | `0337822fcb4424852179100950d381c9d52846438d8cc6b072b93cf709060fc7` |
| `build/windows/x64/runner/Release/tracepos.exe` | `07cc4b38d335ccd2b624d9b09e652b9e0857da4a463b6d1249e6e22cc08c5de8` |

Those files do not establish that the new source changes are included. Rebuild on Windows after correcting the remaining blockers, generate new artifact evidence, then install and test that exact build. The emergency report's Windows build/installer PASS claims are not substantiated by new artifacts in this checkout.

### 2. Native receipt submission still needs correction and Windows verification

Evidence: [windows_spooler_printer.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/windows_spooler_printer.dart:123).

The bridge uses `OpenPrinterA`/`StartDocPrinterA`, rather than the Unicode W APIs claimed in the emergency report. `StartDocPrinter` is declared as a bool instead of preserving its job identifier, and completion-call results are ignored.

The PowerShell wrapper calls the C# method, then unconditionally writes `JOB_SUBMITTED`. It has no enclosing error-to-nonzero-exit policy; Dart only checks the process exit code. A failed method invocation followed by successful output can therefore be mistaken for success. This is a source-based risk, not a reproduced Windows print failure. PowerShell documents that `-Command` exit status depends on the last executed command. [Microsoft PowerShell exit behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1).

Names and paths are escaped using doubled backslashes and `\"`, which are not PowerShell string-escaping rules. Shared queue names containing backslashes, and names containing dollar signs or quotes, need literal-safe handling. [Microsoft quoting rules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-7.5).

The status query still considers an empty successful result online. Process timeouts still do not kill the underlying child process. Test missing queue, offline printer, paused queue, failed native submission and uncertain/late delivery on Windows before accepting this path.

### 3. Drawer and printer configuration are only partially restored

Evidence: [hardware_manager.dart](/Users/macbookair/tracepos/lib/hardware/hardware_manager.dart:164).

Only the queue name and timestamp are saved; profile/58 mm width is not. Startup restores `genericWindows`. File write failures are logged and swallowed, after which Settings still reports activation success.

`saveReceiptPrinter()` rebinds the drawer only if it is already a `PrinterKickCashDrawer`. Normal startup without a custom printer initializes a fake drawer. When a saved receipt queue is restored, auto-application is skipped and the fake drawer remains. Thus selecting a real receipt queue does not ensure cash sales physically open the drawer, particularly after restart. These are source-reviewed findings; no drawer was connected.

The manual dropdown includes every discovered queue rather than filtering by receipt eligibility, and its green status does not check actual `HardwareStatus.ready`. Auto-scoring exclusion does not prevent manual assignment of a PDF/label queue.

### 4. Labels, receipt recovery and text rendering are still incomplete

- Real garment-label printing is absent. It is now honestly disabled, so this is a known missing capability rather than a deceptive success message. The client must explicitly accept a separate label workflow if in-app labels are excluded from delivery.
- Receipt and shift-report `PENDING` jobs still have no processor. Historical receipt reconstruction/reprinting remains missing.
- Receipt strings still use `utf8.encode`; the unchanged renderer does not implement the CP858/CP1252 encoding claimed in the new report. The Arabic raster test still ignores its text argument; this was reproduced again.
- The payment screen still produces French layout overflows in the widget probe. They were recorded separately from the dismissal failure.
- Stale Enter acceptance, unfinished-buffer retention across stop/start and unsupported Tab suffix were reproduced again. The shared scanner listener still dispatches under modals; checkout now has a route guard, so the original checkout finding is partially addressed rather than unchanged in full.
- The Windows workflow creates the ZIP but still verifies/uploads `Trace-POS-Setup-x64.exe` while Inno Setup outputs `Trace-POS-Setup-x64.exe`. The naming mismatch remains.

## Decision

The 141 passing tests are reproducible, but the broader statement that all critical blockers are resolved is not. **Do not hand the existing installer to the shop as the repaired release.** First fix payment closing/unlocking, complete and verify receipt/drawer configuration, rebuild the Windows installer, then test the actual scanner and printer against that artifact. If garment-label printing is required inside the POS, it remains a delivery blocker.

Use the physical acceptance checklist in the [original audit](/Users/macbookair/tracepos/release_audit/CLIENT_HANDOFF_AUDIT_2026-09-08.md), with this retest taking precedence for changed findings.

## Evidence

- [Current analysis](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/analyze.log)
- [141-test run](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/tests.log)
- [Independent probe source](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/retest_probes_test.dart)
- [Probe results and payment-close failure](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/probes.log)
- [Release compilation](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/macos-release.log)
- [Source snapshot at retest start](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/source-before.json)
- [Changed hardware files since earlier audit](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-retest/changed-since-audit.json)
