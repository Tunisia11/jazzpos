import 'dart:io';
import 'package:jazzpos/core/constants/app_constants.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'barcode_scanner/barcode_scanner_interface.dart';
import 'barcode_scanner/fake_barcode_scanner.dart';
import 'barcode_scanner/scanner_input_service.dart';
import 'cash_drawer/cash_drawer_interface.dart';
import 'cash_drawer/disabled_cash_drawer.dart';
import 'cash_drawer/fake_cash_drawer.dart';
import 'cash_drawer/printer_kick_cash_drawer.dart';
import 'customer_display/customer_display_interface.dart';
import 'customer_display/disabled_customer_display.dart';
import 'customer_display/fake_customer_display.dart';
import 'customer_display/second_monitor_customer_display.dart';
import 'label_printer/fake_label_printer.dart';
import 'label_printer/label_document.dart';
import 'label_printer/label_printer_interface.dart';
import 'models/hardware_status.dart';
import 'receipt_printer/fake_receipt_printer.dart';
import 'receipt_printer/preview_printer.dart';
import 'receipt_printer/printer_profile.dart';
import 'receipt_printer/receipt_document.dart';
import 'receipt_printer/receipt_printer_interface.dart';
import 'receipt_printer/receipt_rasterizer.dart';
import 'receipt_printer/windows_spooler_printer.dart';
import 'services/hardware_discovery_service.dart';
import 'services/hardware_recommendation_engine.dart';

/// Centralized Hardware Manager coordinating peripheral POS devices.
/// Manages automatic discovery, candidate scoring, dynamic reconnection,
/// zero-hardware mode, and comprehensive diagnostics.
class HardwareManager {
  static final HardwareManager instance = HardwareManager._();
  HardwareManager._();

  late ReceiptPrinter receiptPrinter;
  late LabelPrinter labelPrinter;
  late BarcodeScanner barcodeScanner;
  late CashDrawer cashDrawer;
  late CustomerDisplay customerDisplay;

  final HardwareDiscoveryService discoveryService = HardwareDiscoveryService();

  HardwareDiscoveryReport? latestDiscovery;
  HardwareRecommendationBundle? latestRecommendations;

  bool _isInitialized = false;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  bool get receiptPrinterIsSimulated =>
      receiptPrinter is FakeReceiptPrinter ||
      receiptPrinter is PreviewPrinter ||
      receiptPrinter.connectionType == AppConstants.connSimulated;

  bool get labelPrinterIsSimulated =>
      labelPrinter.connectionType == AppConstants.connSimulated;

  bool get cashDrawerIsSimulated =>
      cashDrawer is FakeCashDrawer || cashDrawer is DisabledCashDrawer;

  bool get scannerIsSimulated => barcodeScanner is FakeBarcodeScanner;

  bool get customerDisplayIsSimulated =>
      customerDisplay is FakeCustomerDisplay ||
      customerDisplay is DisabledCustomerDisplay;

  /// Peripheral statuses
  HardwareStatus get printerStatus {
    if (receiptPrinterIsSimulated) return HardwareStatus.simulated;
    return receiptPrinter.status;
  }

  HardwareStatus get scannerStatus {
    if (barcodeScanner is ScannerInputService) {
      return (barcodeScanner as ScannerInputService).status;
    }
    return scannerIsSimulated ? HardwareStatus.simulated : HardwareStatus.ready;
  }

  HardwareStatus get drawerStatus {
    if (cashDrawer is DisabledCashDrawer) {
      return HardwareStatus.notConfigured;
    }
    if (cashDrawerIsSimulated) {
      return HardwareStatus.simulated;
    }
    return cashDrawer.status;
  }

  HardwareStatus get displayStatus {
    if (customerDisplay is DisabledCustomerDisplay) {
      return HardwareStatus.notConfigured;
    }
    if (customerDisplayIsSimulated) {
      return HardwareStatus.simulated;
    }
    return customerDisplay.status;
  }

  /// Initialize hardware manager on app startup.
  /// Startup sequence: opens immediately with defaults, runs discovery asynchronously.
  void initialize({
    ReceiptPrinter? customReceiptPrinter,
    LabelPrinter? customLabelPrinter,
    BarcodeScanner? customBarcodeScanner,
    CashDrawer? customCashDrawer,
    CustomerDisplay? customCustomerDisplay,
  }) {
    if (_isInitialized) return;

    // Use provided custom or fallback to zero-hardware safe defaults
    receiptPrinter =
        customReceiptPrinter ??
        (Platform.isWindows
            ? WindowsSpoolerPrinter(name: 'Default Receipt Printer')
            : FakeReceiptPrinter());

    labelPrinter = customLabelPrinter ?? FakeLabelPrinter();

    // Barcode scanner: default to universal USB HID / Keyboard Wedge scanner
    barcodeScanner = customBarcodeScanner ?? ScannerInputService();
    barcodeScanner.startListening();

    // Cash drawer: default through printer if printer available
    cashDrawer =
        customCashDrawer ??
        (customReceiptPrinter != null
            ? PrinterKickCashDrawer(printer: receiptPrinter)
            : FakeCashDrawer());

    customerDisplay = customCustomerDisplay ?? FakeCustomerDisplay();

    _isInitialized = true;
    PosLogger.instance.info(
      'Hardware',
      'Hardware Manager initialized. Target OS: ${Platform.operatingSystem}',
    );

    // Asynchronously perform discovery without blocking the cashier startup
    Future.microtask(() => runDiscoveryScan(autoApplyIfHighConfidence: true));
  }

  /// Execute asynchronous discovery scan across the Windows environment.
  Future<void> runDiscoveryScan({
    bool autoApplyIfHighConfidence = false,
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    try {
      final report = await discoveryService.discoverAll();
      latestDiscovery = report;

      final recommendations =
          HardwareRecommendationEngine.generateRecommendations(report);
      latestRecommendations = recommendations;

      if (autoApplyIfHighConfidence) {
        // If high-confidence printer candidate found on Windows, bind spooler printer
        if (recommendations.receiptPrinter != null &&
            recommendations.receiptPrinter!.confidence ==
                RecommendationConfidence.high) {
          final rec = recommendations.receiptPrinter!;
          receiptPrinter = WindowsSpoolerPrinter(
            name: rec.recommendedName,
            profile: rec.printerProfile ?? PrinterProfile.genericWindows,
          );
          await receiptPrinter.connect();

          // If printer has drawer port, connect drawer
          if (rec.printerProfile?.hasDrawerPort ?? true) {
            cashDrawer = PrinterKickCashDrawer(
              name: 'Tiroir ${rec.recommendedName}',
              printer: receiptPrinter,
            );
          }
        }
      }
    } catch (e) {
      PosLogger.instance.warning('Hardware', 'Discovery scan error: $e');
    } finally {
      _isScanning = false;
    }
  }

  /// Apply recommended hardware configuration bundle
  Future<void> applyRecommendations(HardwareRecommendationBundle bundle) async {
    // 1. Printer
    if (bundle.receiptPrinter != null) {
      final rec = bundle.receiptPrinter!;
      receiptPrinter = WindowsSpoolerPrinter(
        name: rec.recommendedName,
        profile: rec.printerProfile ?? PrinterProfile.genericWindows,
      );
      await receiptPrinter.connect();
    }

    // 2. Scanner
    if (barcodeScanner is ScannerInputService) {
      await barcodeScanner.startListening();
    } else {
      barcodeScanner = ScannerInputService();
      await barcodeScanner.startListening();
    }

    // 3. Drawer
    if (bundle.cashDrawer.transport == 'THROUGH_PRINTER') {
      cashDrawer = PrinterKickCashDrawer(
        name: bundle.cashDrawer.recommendedName,
        printer: receiptPrinter,
      );
    } else if (bundle.cashDrawer.transport == 'DISABLED') {
      cashDrawer = const DisabledCashDrawer();
    }

    // 4. Customer display
    if (bundle.customerDisplay.transport == 'SECOND_MONITOR') {
      customerDisplay = SecondMonitorCustomerDisplay(
        name: bundle.customerDisplay.recommendedName,
      );
    } else if (bundle.customerDisplay.transport == 'DISABLED') {
      customerDisplay = const DisabledCustomerDisplay();
    }

    PosLogger.instance.info(
      'Hardware',
      'Applied hardware recommendations: Printer=${receiptPrinter.name}, Scanner=${barcodeScanner.name}, Drawer=${cashDrawer.name}, Display=${customerDisplay.name}',
    );
  }

  /// Whether the system is currently running in Zero-Hardware Mode
  bool get isZeroHardwareMode => receiptPrinter is PreviewPrinter;

  /// Switch completely to Zero-Hardware Mode (for demonstrations and offline installs)
  void enableZeroHardwareMode() {
    receiptPrinter = PreviewPrinter();
    cashDrawer = const DisabledCashDrawer();
    customerDisplay = const DisabledCustomerDisplay();
    PosLogger.instance.info('Hardware', 'Switched to Zero-Hardware Mode.');
  }

  /// Reset all peripherals to standard simulated mode
  void initializeSimulatedHardware() {
    receiptPrinter = FakeReceiptPrinter();
    labelPrinter = FakeLabelPrinter();
    cashDrawer = FakeCashDrawer();
    customerDisplay = FakeCustomerDisplay();
    PosLogger.instance.info(
      'Hardware',
      'Re-initialized hardware to standard simulated devices.',
    );
  }

  /// Check and attempt safe auto-reconnection if hardware was marked offline
  Future<void> checkReconnection() async {
    if (receiptPrinter.status == HardwareStatus.offline) {
      final ok = await receiptPrinter.connect();
      if (ok) {
        PosLogger.instance.info(
          'Hardware',
          'Printer auto-reconnected successfully.',
        );
      }
    }
  }

  /// Print comprehensive hardware test receipt
  /// Exercises ASCII, French accents, TND 3-decimals, formatting, barcode, cutter
  Future<void> testReceiptPrinter() async {
    final doc = ReceiptDocument(
      storeName: 'JAZZ POS TEST',
      storeAddress: 'Test Terminal, Avenue Habib Bourguiba, Tunis',
      storePhone: '+216 71 000 000',
      fiscalId: '00012345/A/M/000',
      receiptNumber: 'TEST-0001',
      dateTime: DateTime.now(),
      cashierName: 'Admin',
      registerCode: 'REG-01',
      lines: [
        const ReceiptLineItem(
          productName: 'T-Shirt Basic Coton (Élégant)',
          variantDescription: 'Noir / L (Taille Standard)',
          sku: 'TSH-BLK-L',
          barcode: '200123456789',
          quantity: 2,
          unitPrice: Money.fromMillimes(39900),
          total: Money.fromMillimes(79800),
          discount: Money.fromMillimes(5000),
        ),
      ],
      subtotal: const Money.fromMillimes(84800),
      discount: const Money.fromMillimes(5000),
      tax: const Money.fromMillimes(14200),
      total: const Money.fromMillimes(74800),
      payments: [
        const ReceiptPaymentItem(
          method: 'ESPECES',
          amount: Money.fromMillimes(74800),
          tendered: Money.fromMillimes(80000),
          change: Money.fromMillimes(5200),
        ),
      ],
      footerMessage:
          'Hardware diagnostics test: ASCII, French, TND 3-decimals, Barcode OK!',
    );

    await receiptPrinter.printReceipt(doc);
  }

  /// Specifically test Arabic / Raster fallback rendering
  Future<void> testArabicPrinting() async {
    final testPattern = ReceiptRasterizer.createTestRasterPattern(
      text: 'JAZZ POS ARABIC / RASTER ENGINE',
    );
    final rasterBytes = ReceiptRasterizer.rasterizeImage(testPattern);
    await receiptPrinter.printRaw(rasterBytes);
    PosLogger.instance.info(
      'Hardware',
      'Sent raster test pattern to receipt printer',
    );
  }

  /// Print test label
  Future<void> testLabelPrinter() async {
    const doc = LabelDocument(
      storeName: 'JAZZ POS',
      productName: 'Chemise Slim Coton',
      brandName: 'Jazz Collection',
      color: 'Bleu Ciel',
      size: '42',
      sku: 'CHM-BLU-42',
      barcode: '200987654321',
      price: Money.fromMillimes(89900),
      oldPrice: Money.fromMillimes(120000),
      copies: 1,
    );

    await labelPrinter.printLabel(doc);
  }

  /// Test cash drawer kick
  Future<void> testCashDrawer() async {
    await cashDrawer.openDrawer();
  }

  /// Test customer display
  Future<void> testCustomerDisplay() async {
    await customerDisplay.showWelcome();
  }
}
