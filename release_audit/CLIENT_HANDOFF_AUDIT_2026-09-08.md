# Windows fashion-shop client handoff audit — 8 September 2026

**Verdict: RED — do not certify this version for unattended client trading yet.**

The application compiles on macOS and much of the accounting test coverage passes. The current hardware implementation has release blockers: receipt printing is not connected to a reliable Windows spooler API, label printing is simulated, scanning can add the wrong product and continue behind payment dialogs, and recovery from a missed receipt is incomplete. These are implementation findings, beyond the need for physical device testing.

Target supplied by the owner: Windows fashion shop, with USB, Bluetooth and/or network devices. Exact Windows version, scanner models, printer models, command languages, paper widths and label sizes are unknown. Audit performed on macOS against the current working tree; no Windows terminal or physical scanner/printer was available. Existing application changes were preserved. This audit added this report, evidence logs and isolated characterization probes; it did not repair production code or reset shop data.

## 1. What was verified

| Check | Result | Limit |
|---|---|---|
| `flutter analyze` | PASS: no issues | Static analysis before audit-only probe additions |
| Existing selected test suites | 116 passed, 1 failed | macOS; includes hardware, core, services, database, localization, QA, widget and platform suites |
| New isolated audit probes | 8 passed | PASS means the reported behavior/defect was reproduced, not that it is fixed |
| macOS debug build | PASS earlier in this task | Correctly named entitlements and scheme restored |
| macOS release build | PASS, 56.0 MB app | Does not establish Windows native build/runtime correctness |
| Existing Windows installer/executable checksums | All three match `dist/SHA256SUMS.txt` | No rebuild-to-source provenance demonstrated |
| Windows Authenticode | Certificate tables present | Trust not revalidated on Windows; saved report records a test certificate/untrusted chain |
| Physical scanning, printing, cutter, drawer, Bluetooth pairing | NOT TESTED | No client hardware available |
| Client database, upgrade/restore, power interruption | NOT TESTED | No client data was used for those scenarios |

Existing-suite command:

```text
flutter test test/hardware test/core test/services test/data test/localization test/qa test/widget_test.dart test/platform
```

The failing test is `AppPaths.resolveImagePath rejects path traversal attempts` in `test/services/product_image_service_test.dart:254`. On this Mac, `C:\Windows\System32\cmd.exe` becomes a child path beneath the temporary application directory instead of being rejected. This is a cross-platform validation mismatch; this result does not demonstrate escape from the Mac sandbox or a Windows exploit.

The entire unfiltered test directory was deliberately not executed: `test/installer_data_verification_test.dart:14` addresses a developer's live Windows database and performs `INSERT OR REPLACE` operations. Other live tests hardcode that machine's filesystem. They must be separated from portable CI tests and run only against disposable fixtures.

## 2. Barcode scanning findings

### S1 — P1: unknown scan can silently add the wrong garment

Evidence: [cart_provider.dart](/Users/macbookair/tracepos/lib/providers/cart_provider.dart:90), [catalog_service.dart](/Users/macbookair/tracepos/lib/domain/services/catalog_service.dart:86).

`addItemByBarcode()` invokes the general catalog search and adds its first result. Search tries exact barcodes and aliases, then exact/partial SKU and product text. An unmatched barcode is therefore not reliably rejected.

Reproduced with an in-memory catalog: a product has SKU `SKU-123-OTHER` and barcode `9999999999999`. Scanning `123` reports success and adds that product. In a fashion shop this can charge and decrement the wrong size/color variant. Fix by giving scanner lookup a separate exact barcode/alias path, with an explicit policy for exact SKU input, and rejecting ambiguous or unknown results. Preserve the scanned code as text, including leading zeroes.

### S2 — P1: scans continue behind payment and other dialogs

Evidence: [barcode_scanner_listener.dart](/Users/macbookair/tracepos/lib/ui/widgets/barcode_scanner_listener.dart:26), [checkout_screen.dart](/Users/macbookair/tracepos/lib/ui/screens/checkout/checkout_screen.dart:152), [payment_dialog.dart](/Users/macbookair/tracepos/lib/ui/screens/checkout/widgets/payment_dialog.dart:19).

The scanner subscription dispatches whenever its widget is mounted. Checkout's keyboard shortcuts check whether the route is current, but the barcode callback does not. The audit probe opened a modal and confirmed delivery to the underlying listener. Checkout connects that callback directly to cart mutation.

Payment displays the total captured when the dialog opened, while submission reads the current cart. An extra scan can change the cart without updating the payment amount. The service's payment-equals-total validation should reject an ordinary positive-price mismatch; that does not make the UI workflow safe. Scans arriving during an asynchronous checkout can also modify a cart that is subsequently cleared. Pause/route scans by active workflow and reject cart mutation during submission.

### S3 — P2: stale input and suffix handling cause false or missed scans

Evidence: [scanner_input_service.dart](/Users/macbookair/tracepos/lib/hardware/barcode_scanner/scanner_input_service.dart:80).

The active service accepts Enter/numpad Enter and a minimum of three characters. It checks timing between characters, but not the delay between the final character and Enter. A 250 ms delayed Enter still emitted `123` in the probe. Stop/restart retained and completed the previous unfinished burst. A Tab suffix produced no scan. Keyboard characters also return `false` from the handler, so focused text fields are not isolated from scanner input. Fast human typing is indistinguishable from scanner input in this design.

The older `BarcodeInputAccumulator` tests cover stricter terminal timing, but `HardwareManager` instantiates `ScannerInputService`, which has separate logic. Consolidate the behavior, clear the buffer on focus/mode/lifecycle changes, validate terminator timing and test the actual service with real key events.

Operational requirement today: configure the scanner as a keyboard wedge with Enter suffix, matching the Windows keyboard layout. Bluetooth scanners are compatible with this path only when paired in keyboard mode; serial/SPP, BLE/GATT and HID POS device modes have no dedicated scanner implementation here. Actual pacing, repeated digits, AZERTY mapping, wake-from-sleep and reconnect behavior remain unverified.

### S4 — P2: inventory and returns scanning need separate acceptance

Evidence: [inventory_count_service.dart](/Users/macbookair/tracepos/lib/domain/services/inventory_count_service.dart:97), [returns_exchanges_screen.dart](/Users/macbookair/tracepos/lib/ui/screens/returns/returns_exchanges_screen.dart:255).

Stock count searches exact primary barcode or SKU, but does not search barcode aliases used by checkout. A label may work at checkout and fail during stock count. Counting also reads the old quantity and writes old-plus-one without a surrounding transaction/atomic increment; concurrent callbacks can lose increments. This race is a source finding, not reproduced by the eight probes. Count scans should be serialized or updated atomically.

Returns scanning always searches a receipt number; scanning a replacement garment is not an add-to-exchange action. Train and test that distinction. Dialog routing restrictions should apply to all scanner-consuming screens.

## 3. Receipt, label and drawer findings

### P1 — P1: Windows receipt transport can report success without printing

Evidence: [windows_spooler_printer.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/windows_spooler_printer.dart:102).

The active adapter writes a `.bin` file and runs `cmd /c copy /b file printerName` through PowerShell. The destination is a friendly installed printer name, not an opened Windows printer handle. A bare name is normally interpreted as a file destination; this can create/overwrite a file in a writable working directory or fail in a protected one. The script neither captures a spool job ID nor checks bytes accepted by the print queue, and does not explicitly propagate the nested command's exit status. Physical symptoms depend on the Windows installation; no Windows print was performed here.

Microsoft documents raw queue submission through `OpenPrinter`, `StartDocPrinter` with RAW data, `WritePrinter`, and matching completion/cleanup calls, including verification of the byte count. Implement that supported path and distinguish “queued” from “physically printed.” [Microsoft raw printing reference](https://learn.microsoft.com/en-us/windows/win32/printdocs/sending-data-directly-to-a-printer).

Related failures: an empty successful printer-status query is interpreted as online; the default name `Default Receipt Printer` is not resolved to the actual system default queue. USB/serial adapters ignore process failure results, and `ProcessUtils.safeRun` returns a timeout result without terminating the underlying process. A timeout is not proof that nothing can print later. See [process_utils.dart](/Users/macbookair/tracepos/lib/core/platform/process_utils.dart:15), [esc_pos_usb_printer.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/esc_pos_usb_printer.dart:128), and [esc_pos_serial_printer.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/esc_pos_serial_printer.dart:139).

### P2 — P1: garment-label printing is simulated

Evidence: [hardware_manager.dart](/Users/macbookair/tracepos/lib/hardware/hardware_manager.dart:121), [fake_label_printer.dart](/Users/macbookair/tracepos/lib/hardware/label_printer/fake_label_printer.dart:34), [label_studio_screen.dart](/Users/macbookair/tracepos/lib/ui/screens/labels/label_studio_screen.dart:83).

The only concrete `LabelPrinter` implementation is `FakeLabelPrinter`. It generates TSPL text and stores documents in memory; it sends no bytes to a device. `LabelStudioScreen` still reports that labels were sent. ZPL and TSPL generators exist, but a generator is not a printer connection. There is no label-printer selection in the recommendation bundle.

For this shop, this is a release blocker if in-app price/variant labels are promised. Add a real queue/network/serial transport matched to the printer's command language, explicit simulation messaging, and a print-then-scan acceptance test.

### P3 — P1: printer selection and restart persistence are incomplete

Evidence: [hardware_manager.dart](/Users/macbookair/tracepos/lib/hardware/hardware_manager.dart:189), [hardware_setup_wizard.dart](/Users/macbookair/tracepos/lib/ui/screens/settings/hardware_setup_wizard.dart:78), [hardware_recommendation_engine.dart](/Users/macbookair/tracepos/lib/hardware/services/hardware_recommendation_engine.dart:75).

Applying recommendations creates a `WindowsSpoolerPrinter` in memory. There is no connected save/load path for hardware configuration: the `HardwareDevices` table has no application consumer, and the claimed `config.json` persistence is absent. Startup reruns heuristics. There is no usable manual IP/port/COM/queue/profile editor in this flow. Standalone TCP, USB and serial receipt adapter classes are not selected by the application setup.

The scorer can also mistake a label printer for the receipt printer. Reproduced: a default `Zebra ZD420` / `ZDesigner Thermal Label Printer` on `USB001` scores high and qualifies as a receipt candidate. With both printers installed, auto-application can send ESC/POS to the wrong queue. Require explicit receipt-versus-label assignment and persist it; do not infer protocol from brand alone.

### P4 — P1: failed-print recovery and historical reprinting are incomplete

Evidence: [sale_service.dart](/Users/macbookair/tracepos/lib/domain/services/sale_service.dart:410), [shift_service.dart](/Users/macbookair/tracepos/lib/domain/services/shift_service.dart:377), [receipt_preview_dialog.dart](/Users/macbookair/tracepos/lib/ui/screens/checkout/widgets/receipt_preview_dialog.dart:39).

Sales and shift closure insert `PENDING` print jobs, but no application code consumes them or updates their statuses. Receipt printing is separately invoked from the payment dialog; shift report jobs have no equivalent physical print consumer. `checkReconnection()` exists but has no caller.

Reprinting the current preview builds a duplicate document and records an audit event. No historical sale-to-receipt reconstruction/reprint UI was found; the preview is opened only from the current payment flow. After restart or closing that flow, the claimed history-based recovery is unavailable. Implement persisted job status, deliberate retry handling and historical duplicate reprinting without repeating checkout. Receipt queuing must also account for uncertain printer outcomes to avoid blind duplicate output.

### P5 — P1 for Arabic receipts; P2 otherwise: text rendering is not device-correct

Evidence: [receipt_layout_builder.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/receipt_layout_builder.dart:241), [receipt_rasterizer.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/receipt_rasterizer.dart:58), [hardware_manager.dart](/Users/macbookair/tracepos/lib/hardware/hardware_manager.dart:313).

Every receipt string is UTF-8 encoded, although profiles advertise PC850; no profile code-page selection or Arabic shaping/raster fallback is connected to receipt generation. French accents and Arabic output therefore depend on unsupported assumptions about printer mode. An on-screen Unicode preview does not prove paper rendering.

The “Arabic/raster” test generates borders and a circle. Its `text` argument is unused. The probe produced identical bitmap bytes for Arabic and unrelated English text. This test cannot certify Arabic printing. Render actual shaped text or use a verified printer-specific character encoding, then check paper output with the client.

Additional layout issues: `setTextSize(doubleWidth: true)` emits `0x20`, which Epson defines as triple width; double width is `0x10`. This can unexpectedly wrap store headers. [Epson GS ! reference](https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/gs_exclamation.html), [esc_pos_commands.dart](/Users/macbookair/tracepos/lib/hardware/receipt_printer/esc_pos_commands.dart:20).

Receipt Code 128 uses fixed module width 2 and subset B. The normal 18-character receipt number needs approximately 466 dots before quiet zones, exceeding a common 384-dot 58 mm print area. This is a format calculation, not a physical print measurement; narrow-printer handling must be tested and adapted. Label generators also use fixed coordinates irrespective of chosen label size; ZPL does not use document width/height, and neither generator escapes printer-language delimiters in product text. Print long size/color names and prices on the actual stock, then scan each barcode back.

### P6 — P2: status indicators and drawer controls overstate readiness

Scanner `READY` means that a global keyboard handler was registered, not that a scanner was detected. macOS discovery fabricates a generic USB receipt candidate; manually applying it uses a simulated Windows adapter that can appear ready. Neither proves connected hardware.

Checkout opens the drawer after a cash/mixed sale and avoids doing so for card-only sales, which is appropriate. However, the same broken receipt transport carries printer drawer pulses. Drawer failures are swallowed at payment, and the standalone F10/button path does not check a drawer permission or record an audit event. If manager approval is required for “no sale” opening, implement it. Fake devices returning success must never be accepted as physical test evidence.

## 4. Additional handoff blockers and risks

### R1 — P1: payment keypad can break the payment screen

Evidence: [payment_dialog.dart](/Users/macbookair/tracepos/lib/ui/screens/checkout/widgets/payment_dialog.dart:57), [numpad.dart](/Users/macbookair/tracepos/lib/ui/widgets/numpad.dart:39).

The keypad appends arbitrary decimal keys, and the widget calls strict `Money.parse` while building. The audit reproduced a `FormatException` by pressing `.` twice. More than three fractional digits follows the same unguarded parsing path. Validate input incrementally, keep invalid entry recoverable, and use a safe parse result. The same probe recorded French payment-layout overflows at a 1440×1100 test viewport before typing; the fixed dialog/column widths need focused layout correction and Windows DPI checks.

### R2 — P1 for a fresh build: Windows manifest still has the transferred `.xml` suffix

`windows/runner/CMakeLists.txt:16` references `runner.exe.manifest`, but only `runner.exe.manifest.xml` exists. This is the same transfer problem that broke macOS. Restore the expected name before rebuilding Windows. Existing copied `.exe` files do not prove that this checkout can currently rebuild them.

### R3 — P1: fresh Windows CI/package flow is inconsistent

The installer script outputs `Trace-POS-Setup-x64.exe`. The workflow then requires `Trace-POS-Setup-x64.exe` and `Trace-POS-Windows-x64.zip`, without a step that creates those outputs. It also runs unfiltered tests that depend on a developer's live Windows paths. A fresh runner is not equivalent to the developer's machine. See [.github/workflows/windows_release.yml](/Users/macbookair/tracepos/.github/workflows/windows_release.yml:108), [tracepos_setup.iss](/Users/macbookair/tracepos/windows/installer/tracepos_setup.iss:33).

The local VC++ redistributable source folder is absent; Inno Setup makes bundling conditional on its existence. CI has a download step, but a local installer can omit it. The existing installer's prerequisite contents were not extracted/verified in this audit. Verify clean Windows installation with no previously installed runtime.

### R4 — P1: duplicate launch can terminate a healthy starting instance

Evidence: [main.cpp](/Users/macbookair/tracepos/windows/runner/main.cpp:26).

If the named mutex exists but no window is found yet, startup enumerates and forcibly terminates processes named `tracepos.exe` or `Trace POS.exe`. A healthy first instance may still be initializing. This path can kill it and lose unsaved cashier work; it is not a proven stale-process check. Replace it with bounded waiting/activation and verified ownership. This is source-reviewed, not reproduced on Windows. Existing platform tests do not demonstrate this startup race.

### R5 — P2: release evidence and delivery documents need updating

The three current file hashes match the saved checksums, and their PE certificate tables exist. The saved signing report records `test-simulated`, `Require Signature: False` and an untrusted certificate-chain error while labeling verification as passed. Treat that as test signing, not verified client trust. Windows launch/SmartScreen behavior must be checked on the recipient terminal.

The saved Windows diagnostic dated September 7 contains only OneNote and Microsoft Print to PDF queues, no selected receipt recommendation, and a simulated drawer. It supplies no physical POS printer evidence. Existing documentation claims hardware persistence, historical reprinting and Arabic rendering that current code does not implement. `RELEASE_ARTIFACTS.md` also gives schema version 1 while code uses 2; backup output is now a ZIP package containing the database and images, not just the older documented database file.

## 5. What is working at the software layer

- Checkout service validates nonempty carts, positive quantities, discounts, supported payments and exact applied-payment totals. It checks active cashier/shift/product state and performs sale, line, payment, stock and audit writes in a database transaction.
- Service tests cover same-key checkout deduplication, returns/exchanges, stock movements, shift reconciliation, permissions and catalog variants. These passes are useful evidence for the tested cases, not exhaustive proof of all UI flows.
- Production database connection uses WAL with `synchronous=FULL` by default. Test suites cover creating/validating backup snapshots and rejecting invalid files; client-machine restore and power-loss behavior remain untested.
- Exact primary-barcode and alias search exists in the catalog. Repeated additions increment the same cart variant. The scanner-to-search routing needs the exact-match restriction described above.
- ESC/POS byte generation, raster packing and duplicate banners have passing tests. Virtual PDF/OneNote printers are excluded by the scorer. These are useful building blocks; they do not establish transport delivery or paper quality.
- Sale commit precedes peripheral calls in the payment flow, and print exceptions have a “sale saved” recovery dialog. However, the existing hardware-failure test throws and catches standalone exceptions after calling checkout; it does not drive `PaymentDialog` with failing real adapters. Strengthen that integration coverage before claiming fault tolerance.

## 6. Connection support for this shop

| Device/connection | Current implementation | Handoff status |
|---|---|---|
| USB barcode scanner in keyboard mode | Global keyboard-burst listener | Conditional; fix S1/S2 and test suffix/layout/speed |
| Bluetooth scanner in keyboard mode or keyboard dongle | Same keyboard path, pairing outside app | Conditional; test sleep/reconnect on Windows |
| Scanner in serial/SPP/BLE/vendor HID POS mode | No dedicated reader | Unsupported by current application flow |
| USB receipt printer installed as Windows queue | Active file-copy-based adapter | Blocked until queue transport repaired |
| Network receipt printer installed as Windows queue | Same active adapter | Same blocker |
| Direct TCP receipt printer, usually port 9100 | Adapter exists but not wired into setup | Not an operator-ready supported path |
| Bluetooth receipt printer | No dedicated Bluetooth transport | Depends on a repaired Windows queue or explicitly configured serial path; unverified |
| USB/network/Bluetooth label printer | Simulated label adapter only | Blocked |
| Printer-connected cash drawer | Pulse through selected receipt adapter | Blocked by transport; physical voltage/pin/model test required |

## 7. Release order and client acceptance

Before rebuilding: repair Windows manifest naming and repeatable packaging; implement truthful receipt/label transports and explicit saved device selection; fix exact scanner lookup, modal/submission scan routing and payment decimal input; provide historical receipt recovery. Fix encoding before promising Arabic, and verify the actual French paper output. Address duplicate-launch termination before unattended deployment.

After those fixes, execute the following on a disposable shop dataset on the actual Windows terminal. Record device model, driver, queue name, connection, paper/label dimensions, printer language, build SHA-256, tester and date. An application success message alone is not a pass.

| Step | Required evidence |
|---|---|
| 1. Clean install and launch twice | App opens with required DLLs/runtime; second launch activates the first without killing it |
| 2. Set company, store, register, user and opening float | Correct shop header and currency; usable cashier login and shift |
| 3. Configure receipt and label printers separately | Actual queue names and protocols; no label printer assigned as receipt printer |
| 4. Scan a known garment in every size/color | Correct variant and price, leading zeros retained, exactly one increment per trigger |
| 5. Scan 100 times, including identical digits and rapid repeated scans | Exactly 100 increments; no lost/doubled characters or wrong variant |
| 6. Unknown/damaged barcode and normal keyboard typing | Unknown code rejected; no unrelated cart item selected |
| 7. Scan while payment, search/edit field and manager dialog are open | Only the intended workflow receives input; payment cart/amount remains stable |
| 8. Unplug/replug USB; sleep/wake Bluetooth | Next scan works once, without stale prefix or restart |
| 9. Print receipt with long French names and Arabic if required | Correct accents/shaping, margins, three-decimal TND values, barcode and cutter |
| 10. Print labels at the actual selected dimensions | Correct garment/size/color/price and copies; each paper barcode scans to its exact variant |
| 11. Cash, card and mixed sale | One sale/payment set/stock deduction; correct change; drawer opens only when intended |
| 12. Printer off, paper out, queue paused and network lost | Sale persists once; bounded UI response; honest failure/queued state; no blind duplicate payment |
| 13. Reconnect, restart and reprint historical receipt | Same sale with duplicate marking; no extra sale/payment/stock movements |
| 14. Stock count with aliases and rapid scans | Correct count totals; manager-controlled reconciliation |
| 15. Return/exchange by receipt scan | Correct original sale and size/color exchange; correct refund/cash delta |
| 16. Restart Windows | Same configured devices/profile/width and preserved shop data |
| 17. Close shift and print report | Cash reconciles to opening float + net cash flows; report physically prints |
| 18. Backup and restore on a separate disposable installation | Database and product images restore; counts/totals match; original shop remains untouched |

Until blockers are fixed and the required checks pass, restrict any delivery to a clearly identified supervised demonstration. Do not describe the current package as a certified USB/Bluetooth/network fashion-shop POS.

## 8. Reproducible evidence

- [Analysis log](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/analyze.log)
- [Existing-suite log](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/tests.log)
- [Audit probes](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/audit_probes_test.dart)
- [Audit-probe results](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/audit-probes.log)
- [macOS release-build log](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/macos-release.log)
- [Artifact hashes and manifest checks](/Users/macbookair/tracepos/release_audit/evidence/2026-09-08-hardware/artifact-audit.json)
- [Saved Windows hardware diagnostic](/Users/macbookair/tracepos/release_audit/live_windows_machine_diagnostic.json) — historical, not a current client-device test
- [Saved signing report](/Users/macbookair/tracepos/release_audit/CODE_SIGNING_REPORT.md) — test certificate, not fresh trust validation

Audit probe command:

```text
flutter test release_audit/evidence/2026-09-08-hardware/audit_probes_test.dart --reporter expanded --timeout 30s
```

The probes characterize known defects and will need to be converted to corrected-behavior regression expectations when the fixes are implemented. They are outside the default `test/` suite to avoid treating confirmation of a defect as release acceptance.
