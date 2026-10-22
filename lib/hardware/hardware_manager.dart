import 'dart:convert';
import 'dart:io';
import 'package:tracepos/core/constants/app_constants.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/core/platform/app_paths.dart';
import 'package:path/path.dart' as p;
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
import 'label_printer/raw_label_printer.dart';
import 'models/hardware_status.dart';
import 'receipt_printer/esc_pos_network_printer.dart';
import 'receipt_printer/fake_receipt_printer.dart';
import 'receipt_printer/preview_printer.dart';
import 'receipt_printer/printer_profile.dart';
import 'receipt_printer/receipt_document.dart';
import 'receipt_printer/receipt_printer_interface.dart';
import 'receipt_printer/receipt_rasterizer.dart';
import 'receipt_printer/mac_cups_printer.dart';
import 'receipt_printer/windows_spooler_printer.dart';
import 'services/hardware_discovery_service.dart';
import 'services/hardware_recommendation_engine.dart';

/// Centralized Hardware Manager coordinating peripheral POS devices.
/// Manages automatic discovery, candidate scoring, dynamic reconnection,
/// zero-hardware mode, and comprehensive diagnostics.
class HardwareManager {
  static final HardwareManager instance = HardwareManager._();
  HardwareManager._() : configDirectory = null, autoDiscover = true;
  HardwareManager.forTesting({required this.configDirectory}) : autoDiscover = false;
  final Directory? configDirectory;
  final bool autoDiscover;
  PrinterProfile? _configuredProfile;
  bool _drawerEnabled = false;
  bool get drawerEnabled => _drawerEnabled;
  String? configLoadError;

  static const String kHardwareConfigFile = 'hardware_config.json';

  late ReceiptPrinter receiptPrinter;
  late LabelPrinter labelPrinter;
  late BarcodeScanner barcodeScanner;
  late CashDrawer cashDrawer;
  late CustomerDisplay customerDisplay;

  final HardwareDiscoveryService discoveryService = HardwareDiscoveryService();

  HardwareDiscoveryReport? latestDiscovery;
  HardwareRecommendationBundle? latestRecommendations;

  String? _configuredReceiptPrinterName;
  Map<String, dynamic>? _configuredLabelPrinter;
  String? _configuredTransport;
  String? _configuredNetworkIp;
  int? _configuredNetworkPort;
  bool _configuredPrinterIsMissing = false;

  String? get configuredReceiptPrinterName => _configuredReceiptPrinterName;
  String? get configuredTransport => _configuredTransport;
  String? get configuredNetworkIp => _configuredNetworkIp;
  int? get configuredNetworkPort => _configuredNetworkPort;
  bool get configuredPrinterIsMissing => _configuredPrinterIsMissing;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  bool get receiptPrinterIsSimulated =>
      receiptPrinter is FakeReceiptPrinter ||
      receiptPrinter is PreviewPrinter ||
      receiptPrinter.connectionType == AppConstants.connSimulated;

  bool get labelPrinterIsSimulated =>
      labelPrinter is FakeLabelPrinter ||
      labelPrinter.connectionType == AppConstants.connSimulated;

  bool get cashDrawerIsSimulated =>
      cashDrawer is FakeCashDrawer || cashDrawer is DisabledCashDrawer;

  bool get scannerIsSimulated => barcodeScanner is FakeBarcodeScanner;

  bool get customerDisplayIsSimulated =>
      customerDisplay is FakeCustomerDisplay ||
      customerDisplay is DisabledCustomerDisplay;

  /// Peripheral statuses with truthful states
  HardwareStatus get printerStatus {
    if (receiptPrinterIsSimulated) return HardwareStatus.simulated;
    if (_configuredPrinterIsMissing) return HardwareStatus.missing;
    return receiptPrinter.status;
  }

  HardwareStatus get labelPrinterStatus {
    if (labelPrinterIsSimulated) return HardwareStatus.notConfigured;
    return HardwareStatus.ready;
  }

  HardwareStatus get scannerStatus {
    if (barcodeScanner is ScannerInputService) {
      return (barcodeScanner as ScannerInputService).status;
    }
    return scannerIsSimulated ? HardwareStatus.simulated : HardwareStatus.ready;
  }

  String get scannerStatusDescription {
    if (barcodeScanner is ScannerInputService) {
      return (barcodeScanner as ScannerInputService).statusText;
    }
    return scannerIsSimulated ? 'Mode simulé' : 'Prêt';
  }

  bool get scannerHasReceivedPhysicalScan {
    if (barcodeScanner is ScannerInputService) {
      return (barcodeScanner as ScannerInputService).hasReceivedPhysicalScan;
    }
    return false;
  }

  String? get scannerLastBarcode {
    if (barcodeScanner is ScannerInputService) {
      return (barcodeScanner as ScannerInputService).lastScannedBarcode;
    }
    return null;
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

  File get _configFile {
    final dir = configDirectory ?? (AppPaths.instance.isInitialized
        ? AppPaths.instance.baseDir
        : Directory.systemTemp);
    return File(p.join(dir.path, kHardwareConfigFile));
  }

  /// Load persisted printer settings on application boot
  void loadPersistedHardwareConfig() {
    try {
      final file = _configFile;
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final saved = json['receiptPrinter'] as Map<String, dynamic>?;
        final label = json['labelPrinter'];
        if (label is Map) _configuredLabelPrinter = Map<String, dynamic>.from(label);
        final name = saved?['queueName'] as String? ?? json['receiptPrinterName'] as String?;
        if (saved != null) {
          final transport = saved['transport'] as String? ?? (Platform.isMacOS ? 'MACOS_CUPS' : 'WINDOWS_SPOOLER');
          if (transport != 'WINDOWS_SPOOLER' && transport != 'MACOS_CUPS' && transport != 'NETWORK') {
            throw const FormatException('Unsupported printer transport');
          }
          _configuredTransport = transport;
          _configuredNetworkIp = saved['ipAddress'] as String?;
          _configuredNetworkPort = saved['port'] as int?;
          _configuredProfile = PrinterProfile.fromJson(Map<String,dynamic>.from(saved['profile'] as Map));
          _drawerEnabled = saved['drawerEnabled'] == true;
        }
        if (name != null && name.trim().isNotEmpty) {
          _configuredReceiptPrinterName = name.trim();
        }
      }
    } catch (e) {
      configLoadError = e.toString();
      PosLogger.instance.warning('Hardware', 'Failed to load $kHardwareConfigFile: $e');
    }
  }

  /// Manually select and persist the active receipt printer.
  Future<void> saveReceiptPrinter(String printerName, {
    String? transport,
    String? ipAddress,
    int? port,
    PrinterProfile? profile,
    bool drawerEnabled = false,
  }) async {
    final clean = printerName.trim();
    if (clean.isEmpty) throw ArgumentError('Printer queue is required');
    final activeTransport = transport ?? 'WINDOWS_SPOOLER';
    final selected = profile ?? (Platform.isMacOS ? PrinterProfile.genericEscPos80 : PrinterProfile.genericWindows);
    if (![58,80].contains(selected.paperWidthMm)) throw ArgumentError('Supported widths: 58/80 mm');
    final file = _configFile;
    final payload = jsonEncode({
      'version':2,
      'receiptPrinter': {
        'queueName':clean,
        'transport':activeTransport,
        if (activeTransport == 'NETWORK') ...{
          'ipAddress': ipAddress?.trim() ?? '192.168.1.100',
          'port': port ?? 9100,
        },
        'paperWidth':selected.paperWidthMm,
        'profile':selected.toJson(),
        'encoding':selected.defaultCodePage,
        'cutterEnabled':selected.hasCutter,
        'drawerEnabled':drawerEnabled && selected.hasDrawerPort,
        'drawerPin':selected.drawerKickCommand.length >= 3 ? selected.drawerKickCommand[2] : null,
      },
      if (_configuredLabelPrinter != null) 'labelPrinter': _configuredLabelPrinter,
      'updatedAt':DateTime.now().toUtc().toIso8601String(),
    });
    // Save before activation; a failed write must reach Settings as an error.
    final staged = File('${file.path}.tmp');
    try {
      await staged.writeAsString(payload, flush:true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
    _configuredReceiptPrinterName = clean;
    _configuredTransport = activeTransport;
    _configuredNetworkIp = ipAddress?.trim();
    _configuredNetworkPort = port;
    _configuredProfile = selected;
    _drawerEnabled = drawerEnabled && selected.hasDrawerPort;
    _configuredPrinterIsMissing = false;
    if (activeTransport == 'NETWORK') {
      receiptPrinter = EscPosNetworkPrinter(
        name: clean,
        ipAddress: ipAddress?.trim() ?? '192.168.1.100',
        port: port ?? 9100,
        profile: selected,
      );
    } else if (activeTransport == 'MACOS_CUPS' || (activeTransport == 'WINDOWS_SPOOLER' && Platform.isMacOS)) {
      receiptPrinter = MacCupsPrinter(name:clean,profile:selected);
    } else if (activeTransport == 'WINDOWS_SPOOLER') {
      receiptPrinter = WindowsSpoolerPrinter(name:clean,profile:selected);
    } else {
      receiptPrinter = FakeReceiptPrinter();
    }
    cashDrawer = _drawerEnabled ? PrinterKickCashDrawer(printer:receiptPrinter) : const DisabledCashDrawer();
    await receiptPrinter.connect();
  }

  LabelPrinter _restoreLabelPrinter() {
    final saved = _configuredLabelPrinter;
    final transport = LabelTransportKey.fromKey(saved?['transport'] as String?);
    final queue = (saved?['queueName'] as String?)?.trim() ?? '';
    if (saved == null || transport == null || queue.isEmpty) {
      return FakeLabelPrinter();
    }
    return RawLabelPrinter(
      queueName: queue,
      transport: transport,
      ipAddress: saved['ipAddress'] as String?,
      port: saved['port'] as int? ?? 9100,
    );
  }

  /// Persist and activate the label printer (TSPL over network, spooler or CUPS).
  Future<void> saveLabelPrinter(
    String queueName, {
    required LabelTransport transport,
    String? ipAddress,
    int? port,
  }) async {
    final clean = queueName.trim();
    if (clean.isEmpty) throw ArgumentError('Label printer name is required');
    if (transport == LabelTransport.network &&
        (ipAddress == null || ipAddress.trim().isEmpty)) {
      throw ArgumentError('Label printer IP address is required');
    }
    final file = _configFile;
    Map<String, dynamic> json = {};
    if (file.existsSync()) {
      try {
        json = Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
      } catch (e) {
        PosLogger.instance.warning('Hardware', 'Config unreadable, rewriting: $e');
      }
    }
    final entry = <String, dynamic>{
      'queueName': clean,
      'transport': transport.key,
      if (transport == LabelTransport.network) ...{
        'ipAddress': ipAddress!.trim(),
        'port': port ?? 9100,
      },
    };
    json['labelPrinter'] = entry;
    json['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final staged = File('${file.path}.tmp');
    try {
      await staged.writeAsString(jsonEncode(json), flush: true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
    _configuredLabelPrinter = entry;
    labelPrinter = _restoreLabelPrinter();
  }

  /// Initialize hardware manager on app startup.
  void initialize({
    ReceiptPrinter? customReceiptPrinter,
    LabelPrinter? customLabelPrinter,
    BarcodeScanner? customBarcodeScanner,
    CashDrawer? customCashDrawer,
    CustomerDisplay? customCustomerDisplay,
  }) {
    if (_isInitialized) return;

    loadPersistedHardwareConfig();

    // 1. Restore configured receipt printer, or custom, or safe default
    if (customReceiptPrinter != null) {
      receiptPrinter = customReceiptPrinter;
    } else if (_configuredReceiptPrinterName != null &&
        _configuredReceiptPrinterName!.isNotEmpty) {
      if (_configuredTransport == 'NETWORK') {
        receiptPrinter = EscPosNetworkPrinter(
          name: _configuredReceiptPrinterName!,
          ipAddress: _configuredNetworkIp ?? '192.168.1.100',
          port: _configuredNetworkPort ?? 9100,
          profile: _configuredProfile ?? PrinterProfile.genericEscPos80,
        );
      } else if (Platform.isMacOS || _configuredTransport == 'MACOS_CUPS') {
        receiptPrinter = MacCupsPrinter(
          name: _configuredReceiptPrinterName!,
          profile: _configuredProfile ?? PrinterProfile.genericEscPos80,
        );
      } else if (Platform.isWindows || _configuredTransport == 'WINDOWS_SPOOLER') {
        receiptPrinter = WindowsSpoolerPrinter(
          name: _configuredReceiptPrinterName!,
          profile: _configuredProfile ?? PrinterProfile.genericWindows,
        );
      } else {
        receiptPrinter = FakeReceiptPrinter();
      }
    } else {
      receiptPrinter = Platform.isWindows
          ? WindowsSpoolerPrinter(name: 'Default Receipt Printer')
          : FakeReceiptPrinter();
    }

    // 2. Label printer
    labelPrinter = customLabelPrinter ?? _restoreLabelPrinter();

    // 3. Barcode scanner
    barcodeScanner = customBarcodeScanner ?? ScannerInputService();
    barcodeScanner.startListening();

    // 4. Cash drawer
    cashDrawer = customCashDrawer ??
        (_drawerEnabled
            ? PrinterKickCashDrawer(printer: receiptPrinter)
            : const DisabledCashDrawer());

    // 5. Customer display
    customerDisplay = customCustomerDisplay ?? FakeCustomerDisplay();

    _isInitialized = true;
    PosLogger.instance.info(
      'Hardware',
      'Hardware Manager initialized. Configured printer: $_configuredReceiptPrinterName. Target OS: ${Platform.operatingSystem}',
    );

    // Asynchronously perform discovery without blocking cashier startup
    if (autoDiscover) Future.microtask(() => runDiscoveryScan());
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

      // Check if user's configured printer is installed in the system
      if (_configuredReceiptPrinterName != null &&
          _configuredReceiptPrinterName!.isNotEmpty) {
        final isPresent = report.printers.any(
          (p) =>
              p.name.trim().toLowerCase() ==
              _configuredReceiptPrinterName!.toLowerCase(),
        );
        if (!isPresent && Platform.isWindows) {
          _configuredPrinterIsMissing = true;
          PosLogger.instance.warning(
            'Hardware',
            'Configured receipt printer "$_configuredReceiptPrinterName" is unavailable on this computer. NOT auto-switching.',
          );
        } else {
          _configuredPrinterIsMissing = false;
        }
      } else if (autoApplyIfHighConfidence) {
        // Only auto-apply if NO printer has been configured by user
        if (recommendations.receiptPrinter != null &&
            recommendations.receiptPrinter!.confidence ==
                RecommendationConfidence.high) {
          final rec = recommendations.receiptPrinter!;
          receiptPrinter = WindowsSpoolerPrinter(
            name: rec.recommendedName,
            profile: rec.printerProfile ?? PrinterProfile.genericWindows,
          );
          await receiptPrinter.connect();

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
    // Persist the same profile and drawer binding used by manual Settings.
    if (bundle.receiptPrinter != null) {
      final rec = bundle.receiptPrinter!;
      await saveReceiptPrinter(rec.recommendedName, profile: rec.printerProfile,
        drawerEnabled: bundle.cashDrawer.transport == 'THROUGH_PRINTER');
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

  /// Print comprehensive hardware test receipt for client installation
  /// Includes exact requirements: Boutique name, Article Test 10.000, TOTAL 10.000, Barcode, Printer test successful
  Future<void> testReceiptPrinter({String? storeName, String? barcode}) async {
    final now = DateTime.now();
    final effectiveStoreName = storeName != null && storeName.isNotEmpty
        ? (storeName.startsWith('Boutique:') ? storeName : 'Boutique: $storeName')
        : 'Boutique: Trace POS Boutique';
    final effectiveBarcode = barcode ?? '200123456789';

    final doc = ReceiptDocument(
      storeName: effectiveStoreName,
      storeAddress: 'Test Terminal — Installation Client',
      storePhone: '+216 71 000 000',
      fiscalId: '00012345/A/M/000',
      receiptNumber: 'TEST-${now.millisecondsSinceEpoch.toString().substring(7)}',
      dateTime: now,
      cashierName: 'Administrateur',
      registerCode: 'REG-01',
      lines: [
        ReceiptLineItem(
          productName: 'Article Test 10.000',
          variantDescription: 'Caractères français: é è à ç ù',
          sku: 'TEST-SKU-001',
          barcode: effectiveBarcode,
          quantity: 1,
          unitPrice: const Money.fromMillimes(10000),
          total: const Money.fromMillimes(10000),
        ),
      ],
      subtotal: const Money.fromMillimes(10000),
      discount: Money.zero,
      tax: const Money.fromMillimes(1900),
      total: const Money.fromMillimes(10000),
      payments: const [
        ReceiptPaymentItem(
          method: 'ESPECES',
          amount: Money.fromMillimes(10000),
          tendered: Money.fromMillimes(10000),
          change: Money.zero,
        ),
      ],
      footerMessage:
          'Printer test successful\nTRACE POS — Installation Boutique Réussie !\nBarcode: $effectiveBarcode\nCaractères accentués: é è à ç ù',
    );

    await receiptPrinter.printReceipt(doc);
  }

  /// Specifically test Arabic / Raster fallback rendering
  Future<void> testArabicPrinting() async {
    final testPattern = ReceiptRasterizer.createTestRasterPattern(
      text: 'TRACE POS ARABIC / RASTER ENGINE',
    );
    final rasterBytes = ReceiptRasterizer.rasterizeImage(testPattern);
    await receiptPrinter.printRaw(rasterBytes);
    PosLogger.instance.info(
      'Hardware',
      'Sent raster test pattern to receipt printer',
    );
  }

  /// Print test label — strictly fails if label printer is simulated in production
  Future<void> testLabelPrinter() async {
    if (labelPrinterIsSimulated) {
      throw Exception(
        'L\'impression d\'étiquettes n\'est pas configurée (aucune imprimante physique détectée).',
      );
    }
    const doc = LabelDocument(
      storeName: 'TRACE POS',
      productName: 'Chemise Slim Coton',
      brandName: 'Trace Collection',
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
    if (drawerStatus == HardwareStatus.notConfigured) throw StateError('Tiroir non configuré');
    await cashDrawer.openDrawer();
  }

  /// Test customer display
  Future<void> testCustomerDisplay() async {
    await customerDisplay.showWelcome();
  }
}
