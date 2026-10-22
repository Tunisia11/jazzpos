import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/core/platform/export_diagnostic_report_service.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/label_printer/label_document.dart';
import 'package:tracepos/hardware/label_printer/raw_label_printer.dart';
import 'package:tracepos/hardware/models/hardware_status.dart';
import 'package:tracepos/hardware/receipt_printer/printer_candidate.dart';
import 'package:tracepos/hardware/receipt_printer/printer_profile.dart';
import 'package:tracepos/hardware/receipt_printer/printer_queue_policy.dart';
import 'package:tracepos/hardware/services/hardware_discovery_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/ui/screens/settings/hardware_setup_wizard.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_card.dart';
import 'package:tracepos/core/logging/pos_logger.dart';

class HardwareDiagnosticsTab extends ConsumerStatefulWidget {
  const HardwareDiagnosticsTab({super.key});

  @override
  ConsumerState<HardwareDiagnosticsTab> createState() => _HardwareDiagnosticsTabState();
}

class _HardwareDiagnosticsTabState extends ConsumerState<HardwareDiagnosticsTab> {
  List<PrinterCandidate> _discoveredPrinters = [];
  String? _selectedPrinterQueue;
  bool _isLoadingPrinters = false;
  bool _isSavingPrinter = false;
  late int _paperWidth;
  late bool _cutterEnabled;
  late bool _drawerEnabled;
  late int _drawerPin;

  // Connection mode: 'SPOOLER' or 'NETWORK'
  String _printerConnectionType = 'SPOOLER';
  final TextEditingController _networkIpController =
      TextEditingController(text: '192.168.1.100');
  final TextEditingController _networkPortController =
      TextEditingController(text: '9100');
  bool _isTestingNetworkConnection = false;

  String? _hardwareStatusMsg;

  // Live scanner state
  StreamSubscription<String>? _scannerSub;
  String _liveScannedBarcode = '';
  DateTime? _lastScanTimestamp;

  @override
  void initState() {
    super.initState();
    final hw = HardwareManager.instance;
    final profile = hw.receiptPrinter.profile;
    _paperWidth = profile.paperWidthMm;
    _cutterEnabled = profile.hasCutter;
    _drawerEnabled = hw.drawerEnabled;
    _drawerPin = profile.drawerKickCommand.length >= 3 ? profile.drawerKickCommand[2] : 0;

    if (hw.configuredTransport == 'NETWORK') {
      _printerConnectionType = 'NETWORK';
      if (hw.configuredNetworkIp != null && hw.configuredNetworkIp!.isNotEmpty) {
        _networkIpController.text = hw.configuredNetworkIp!;
      }
      if (hw.configuredNetworkPort != null) {
        _networkPortController.text = hw.configuredNetworkPort!.toString();
      }
    }

    _refreshPrinters();

    // Listen to barcode scanner stream in real-time
    _scannerSub = hw.barcodeScanner.onScan.listen((code) {
      if (mounted) {
        setState(() {
          _liveScannedBarcode = code;
          _lastScanTimestamp = DateTime.now();
          _hardwareStatusMsg = 'Code-barres reçu avec succès : $code (${code.length} car.)';
        });
      }
    });
  }

  @override
  void dispose() {
    _networkIpController.dispose();
    _networkPortController.dispose();
    _scannerSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshPrinters() async {
    setState(() => _isLoadingPrinters = true);
    try {
      final discovery = HardwareDiscoveryService();
      final printers = (await discovery.discoverPrinters())
          .where((p) => !PrinterQueuePolicy.isVirtual(p.name))
          .toList();
      final hw = HardwareManager.instance;
      await hw.receiptPrinter.isConnected();
      final configured = hw.configuredReceiptPrinterName;
      if (mounted) {
        setState(() {
          _discoveredPrinters = printers;
          if (configured != null && configured.isNotEmpty) {
            _selectedPrinterQueue = configured;
          } else if (_selectedPrinterQueue == null && printers.isNotEmpty) {
            _selectedPrinterQueue = printers.first.name;
          }
        });
      }
    } catch (e) {
      PosLogger.instance.warning('hardware_diagnostics_tab', 'Ignored error: $e');
      // Ignored
    } finally {
      if (mounted) setState(() => _isLoadingPrinters = false);
    }
  }

  Future<void> _testNetworkPing() async {
    final ip = _networkIpController.text.trim();
    final port = int.tryParse(_networkPortController.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer une adresse IP valide.'),
          backgroundColor: AppDesignTokens.danger,
        ),
      );
      return;
    }
    setState(() => _isTestingNetworkConnection = true);
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      stopwatch.stop();
      await socket.close();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connexion réussie à $ip:$port (${stopwatch.elapsedMilliseconds} ms) !'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        setState(() {
          _hardwareStatusMsg = 'Test réseau réussi : $ip:$port répond en ${stopwatch.elapsedMilliseconds} ms';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de la connexion à $ip:$port : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
        setState(() {
          _hardwareStatusMsg = 'Échec test réseau ($ip:$port) : $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isTestingNetworkConnection = false);
    }
  }

  Future<void> _saveAndActivatePrinter() async {
    if (_printerConnectionType == 'NETWORK') {
      final ip = _networkIpController.text.trim();
      final port = int.tryParse(_networkPortController.text.trim()) ?? 9100;
      if (ip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez entrer une adresse IP valide pour l\'imprimante réseau.'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
        return;
      }
      setState(() => _isSavingPrinter = true);
      try {
        await HardwareManager.instance.saveReceiptPrinter(
          'Network ($ip:$port)',
          transport: 'NETWORK',
          ipAddress: ip,
          port: port,
          profile: PrinterProfile.custom(
            name: 'ESC/POS Network $_paperWidth mm',
            paperWidthMm: _paperWidth,
            charactersPerLine: _paperWidth == 58 ? 32 : 48,
            hasCutter: _cutterEnabled,
            hasDrawerPort: _drawerEnabled,
            drawerKickCommand: [0x1B, 0x70, _drawerPin, 0x19, 0xFA],
          ),
          drawerEnabled: _drawerEnabled,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imprimante réseau $ip:$port enregistrée et activée.'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
          setState(() {
            _hardwareStatusMsg = 'Imprimante réseau active : $ip:$port';
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur activation imprimante réseau : $e'), backgroundColor: AppDesignTokens.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isSavingPrinter = false);
      }
      return;
    }

    if (_selectedPrinterQueue == null || _selectedPrinterQueue!.trim().isEmpty) return;
    if (PrinterQueuePolicy.isVirtual(_selectedPrinterQueue!)) return;
    final candidate = _discoveredPrinters.where((p) => p.name == _selectedPrinterQueue).firstOrNull;
    if (PrinterQueuePolicy.looksLikeLabel('${_selectedPrinterQueue!} ${candidate?.driverName ?? ''}')) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Imprimante d’étiquettes probable'),
          content: const Text('Cette imprimante semble destinée aux étiquettes, pas aux tickets. Confirmez uniquement si son mode ESC/POS est compatible avec les tickets.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer cette imprimante')),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    setState(() => _isSavingPrinter = true);
    try {
      final transport = Platform.isMacOS ? 'MACOS_CUPS' : 'WINDOWS_SPOOLER';
      await HardwareManager.instance.saveReceiptPrinter(
        _selectedPrinterQueue!.trim(),
        transport: transport,
        profile: PrinterProfile.custom(
          name: 'ESC/POS $_paperWidth mm',
          paperWidthMm: _paperWidth,
          charactersPerLine: _paperWidth == 58 ? 32 : 48,
          hasCutter: _cutterEnabled,
          hasDrawerPort: _drawerEnabled,
          drawerKickCommand: [0x1B, 0x70, _drawerPin, 0x19, 0xFA],
        ),
        drawerEnabled: _drawerEnabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File d\'impression "$_selectedPrinterQueue" enregistrée et activée.'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
        setState(() {
          _hardwareStatusMsg = 'Imprimante active enregistrée : $_selectedPrinterQueue';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur activation imprimante : $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPrinter = false);
    }
  }

  Future<void> _testReceiptPrinter() async {
    try {
      final boutiqueService = ref.read(boutiqueSettingsServiceProvider);
      final settings = await boutiqueService.loadSettings();

      await HardwareManager.instance.testReceiptPrinter(
        storeName: settings.name,
        barcode: _liveScannedBarcode.isNotEmpty ? _liveScannedBarcode : '200123456789',
      );

      if (mounted) {
        setState(
          () => _hardwareStatusMsg = HardwareManager.instance.receiptPrinterIsSimulated
              ? 'SIMULATION : aperçu ticket généré, aucune impression physique'
              : 'Ticket de caisse test envoyé avec succès à l’imprimante physique.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hardwareStatusMsg = 'Erreur ticket: $e');
      }
    }
  }

  Future<void> _configureLabelPrinter() async {
    var transport = Platform.isWindows
        ? LabelTransport.windowsSpooler
        : Platform.isMacOS
            ? LabelTransport.macCups
            : LabelTransport.network;
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Configurer l’étiqueteuse'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<LabelTransport>(
                  initialValue: transport,
                  decoration: const InputDecoration(labelText: 'Connexion'),
                  items: const [
                    DropdownMenuItem(value: LabelTransport.windowsSpooler, child: Text('Windows (file d’impression)')),
                    DropdownMenuItem(value: LabelTransport.network, child: Text('Réseau (IP)')),
                    DropdownMenuItem(value: LabelTransport.macCups, child: Text('macOS (CUPS)')),
                  ],
                  onChanged: (v) => setLocal(() => transport = v ?? transport),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: transport == LabelTransport.network ? 'Nom' : 'Nom de la file d’impression',
                  ),
                ),
                if (transport == LabelTransport.network) ...[
                  TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: 'Adresse IP')),
                  TextField(controller: portCtrl, decoration: const InputDecoration(labelText: 'Port')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await HardwareManager.instance.saveLabelPrinter(
        nameCtrl.text,
        transport: transport,
        ipAddress: ipCtrl.text,
        port: int.tryParse(portCtrl.text.trim()),
      );
      if (mounted) setState(() => _hardwareStatusMsg = 'Étiqueteuse enregistrée.');
    } catch (e) {
      if (mounted) setState(() => _hardwareStatusMsg = 'Erreur étiqueteuse: $e');
    }
  }

  Future<void> _testLabelPrinter() async {
    if (HardwareManager.instance.labelPrinterIsSimulated) {
      if (mounted) {
        setState(
          () => _hardwareStatusMsg =
              'L\'impression d\'étiquettes n\'est pas configurée (aucune imprimante physique détectée).',
        );
      }
      return;
    }
    try {
      final boutiqueService = ref.read(boutiqueSettingsServiceProvider);
      final settings = await boutiqueService.loadSettings();

      final doc = LabelDocument(
        storeName: settings.name,
        productName: 'Polo Piqué Coton',
        size: 'L',
        sku: 'POL-000001-L',
        barcode: _liveScannedBarcode.isNotEmpty ? _liveScannedBarcode : '200123456789',
        price: const Money.fromMillimes(49000),
        widthMm: 40,
        heightMm: 30,
        copies: 1,
      );
      await HardwareManager.instance.labelPrinter.printLabel(doc);
      if (mounted) {
        setState(() => _hardwareStatusMsg = 'Étiquette test envoyée avec succès à l’imprimante physique.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hardwareStatusMsg = 'Erreur étiquette: $e');
      }
    }
  }

  Future<void> _testCashDrawer() async {
    try {
      await HardwareManager.instance.cashDrawer.openDrawer();
      setState(
        () => _hardwareStatusMsg = HardwareManager.instance.cashDrawerIsSimulated
            ? 'SIMULATION : aucun tiroir physique n’a été ouvert'
            : 'Tiroir-caisse déclenché avec succès !',
      );
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur tiroir: $e');
    }
  }

  Future<void> _testCustomerDisplay() async {
    try {
      await HardwareManager.instance.customerDisplay.showWelcome();
      setState(
        () => _hardwareStatusMsg = HardwareManager.instance.customerDisplayIsSimulated
            ? 'SIMULATION : aucun afficheur client physique piloté'
            : 'Message de bienvenue envoyé à l\'afficheur client physique.',
      );
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur afficheur: $e');
    }
  }

  Future<void> _openHardwareSetupWizard() async {
    await HardwareSetupWizard.show(context);
    if (mounted) {
      setState(() {
        _hardwareStatusMsg = 'Configuration matérielle appliquée avec succès.';
      });
      _refreshPrinters();
    }
  }

  Future<void> _exportDiagnosticReport() async {
    try {
      final path = await ExportDiagnosticReportService.exportReportToFile();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rapport technique exporté avec succès : $path'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'export du diagnostic : $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    }
  }

  void _toggleZeroHardwareMode(bool enabled) {
    setState(() {
      if (enabled) {
        HardwareManager.instance.enableZeroHardwareMode();
        _hardwareStatusMsg = 'Mode Zéro-Matériel activé (Aperçu à l\'écran sans erreur).';
      } else {
        HardwareManager.instance.initializeSimulatedHardware();
        _hardwareStatusMsg = 'Mode standard réactivé.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hw = HardwareManager.instance;
    final isZeroHw = hw.isZeroHardwareMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Automated Wizard & Diagnostic Hub ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppDesignTokens.primary.withValues(alpha: 0.08),
                  AppDesignTokens.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: AppDesignTokens.primary.withValues(alpha: 0.3)),
              boxShadow: AppDesignTokens.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_fix_high, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Assistant de Détection & Diagnostic Matériel',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Scanne les ports USB, le Spooler Windows, les ports COM série, le tiroir-caisse et le lecteur code-barres pour configurer l\'ensemble des périphériques sans manipulation complexe.',
                            style: TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openHardwareSetupWizard,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesignTokens.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                      ),
                      icon: const Icon(Icons.settings_suggest, size: 18),
                      label: const Text('Lancer l\'Assistant (Setup Automatique)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportDiagnosticReport,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppDesignTokens.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        side: const BorderSide(color: AppDesignTokens.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Exporter Rapport Diagnostic (.json)'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 2. Zero-Hardware Mode Switch ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isZeroHw ? AppDesignTokens.warningBg : AppDesignTokens.surface,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: isZeroHw ? AppDesignTokens.warning : AppDesignTokens.border),
            ),
            child: Row(
              children: [
                Icon(
                  isZeroHw ? Icons.science : Icons.devices,
                  color: isZeroHw ? AppDesignTokens.warningText : AppDesignTokens.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Zéro-Matériel (Démonstration & Sans Imprimante)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isZeroHw ? AppDesignTokens.warningText : AppDesignTokens.textPrimary,
                        ),
                      ),
                      Text(
                        isZeroHw
                            ? 'Actif : Les tickets s\'affichent à l\'écran sans bloquer la vente.'
                            : 'Inactif : Envoie les ordres physiques réels aux périphériques configurés.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isZeroHw ? AppDesignTokens.warningText : AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isZeroHw,
                  onChanged: _toggleZeroHardwareMode,
                  activeThumbColor: AppDesignTokens.warning,
                ),
              ],
            ),
          ),

          if (_hardwareStatusMsg != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _hardwareStatusMsg!.contains('Erreur')
                    ? AppDesignTokens.danger.withValues(alpha: 0.12)
                    : _hardwareStatusMsg!.contains('SIMULATION') || _hardwareStatusMsg!.contains('Zéro-Matériel')
                        ? AppDesignTokens.warningBg
                        : AppDesignTokens.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                border: Border.all(
                  color: _hardwareStatusMsg!.contains('Erreur')
                      ? AppDesignTokens.danger.withValues(alpha: 0.3)
                      : _hardwareStatusMsg!.contains('SIMULATION') || _hardwareStatusMsg!.contains('Zéro-Matériel')
                          ? AppDesignTokens.warning
                          : AppDesignTokens.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hardwareStatusMsg!.contains('Erreur')
                        ? Icons.error_outline
                        : _hardwareStatusMsg!.contains('SIMULATION') || _hardwareStatusMsg!.contains('Zéro-Matériel')
                            ? Icons.science_outlined
                            : Icons.check_circle,
                    color: _hardwareStatusMsg!.contains('Erreur')
                        ? AppDesignTokens.danger
                        : _hardwareStatusMsg!.contains('SIMULATION') || _hardwareStatusMsg!.contains('Zéro-Matériel')
                            ? AppDesignTokens.warningText
                            : AppDesignTokens.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hardwareStatusMsg!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _hardwareStatusMsg!.contains('Erreur')
                            ? AppDesignTokens.dangerText
                            : _hardwareStatusMsg!.contains('SIMULATION') || _hardwareStatusMsg!.contains('Zéro-Matériel')
                                ? AppDesignTokens.warningText
                                : AppDesignTokens.successText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── 3. Live Scanner Diagnostic Card ──
          const Text(
            'Test en Direct du Lecteur Code-barres (Douchette USB) :',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
          ),
          const SizedBox(height: 12),
          _buildLiveScannerCard(hw),

          const SizedBox(height: 24),

          // ── 4. Principal Receipt Printer Card ──
          const Text(
            'Imprimante Ticket de Caisse (58mm / 80mm ESC/POS) :',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
          ),
          const SizedBox(height: 12),
          _buildReceiptPrinterCard(hw),

          const SizedBox(height: 24),

          // ── 5. Other Peripherals ──
          const Text(
            'Autres Périphériques Connectés :',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _configureLabelPrinter,
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Configurer l’étiqueteuse (TSPL)'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildDeviceCard(
                title: 'Étiqueteuse Code-barres',
                subtitle: hw.labelPrinterIsSimulated ? 'Non configurée (simulation)' : hw.labelPrinter.name,
                status: hw.labelPrinterStatus,
                icon: Icons.qr_code,
                onTest: _testLabelPrinter,
                testLabel: 'Tester Impression Étiquette',
              ),
              const SizedBox(width: 16),
              _buildDeviceCard(
                title: 'Tiroir-Caisse Électrique',
                subtitle: hw.cashDrawerIsSimulated
                    ? 'Mode simulé'
                    : '${hw.cashDrawer.name} (${hw.cashDrawer.mode.labelFr})',
                status: hw.drawerStatus,
                icon: Icons.point_of_sale,
                onTest: _testCashDrawer,
                testLabel: 'Tester Ouverture Tiroir',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildDeviceCard(
                title: 'Afficheur Client',
                subtitle: hw.customerDisplayIsSimulated
                    ? 'Mode simulé'
                    : '${hw.customerDisplay.name} (${hw.customerDisplay.mode.labelFr})',
                status: hw.displayStatus,
                icon: Icons.tv,
                onTest: _testCustomerDisplay,
                testLabel: 'Tester Afficheur Client',
              ),
              const SizedBox(width: 16),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveScannerCard(HardwareManager hw) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppDesignTokens.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.barcode_reader, color: AppDesignTokens.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Écoute Événementielle Douchette USB (Mode Clavier HID)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppDesignTokens.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hw.scannerStatusDescription,
                      style: TextStyle(
                        fontSize: 12,
                        color: hw.scannerHasReceivedPhysicalScan ? AppDesignTokens.success : AppDesignTokens.textSecondary,
                        fontWeight: hw.scannerHasReceivedPhysicalScan ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hw.scannerHasReceivedPhysicalScan ? AppDesignTokens.successBg : AppDesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hw.scannerHasReceivedPhysicalScan
                        ? AppDesignTokens.success.withValues(alpha: 0.4)
                        : const Color(0xFF93C5FD),
                  ),
                ),
                child: Text(
                  hw.scannerHasReceivedPhysicalScan ? 'SCAN VÉRIFIÉ (OK)' : 'EN ATTENTE DE SCAN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hw.scannerHasReceivedPhysicalScan ? AppDesignTokens.successText : AppDesignTokens.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Dernier code-barres capturé en direct :',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    if (_lastScanTimestamp != null)
                      Text(
                        'Horodatage : ${DateFormat('HH:mm:ss').format(_lastScanTimestamp!)}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _liveScannedBarcode.isNotEmpty
                      ? _liveScannedBarcode
                      : '(Scannez un article avec votre douchette physique ou cliquez sur Simuler ci-dessous)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: _liveScannedBarcode.isNotEmpty ? 22 : 14,
                    fontWeight: FontWeight.bold,
                    color: _liveScannedBarcode.isNotEmpty ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                  ),
                ),
                if (_liveScannedBarcode.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Exactitude : ${_liveScannedBarcode.length} caractères | Zéros initiaux strictement préservés',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _liveScannedBarcode = '';
                    _lastScanTimestamp = null;
                  });
                },
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Effacer'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppDesignTokens.border),
                  foregroundColor: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  hw.barcodeScanner.simulateScan('200123456789');
                },
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text('Simuler Scan Test (200123456789)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.surfaceElevated,
                  foregroundColor: AppDesignTokens.textPrimary,
                  elevation: 0,
                  side: const BorderSide(color: AppDesignTokens.border),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptPrinterCard(HardwareManager hw) {
    final configuredName = hw.configuredReceiptPrinterName;
    final isSimulated = hw.receiptPrinterIsSimulated;
    final isMissing = hw.configuredPrinterIsMissing;
    final statusColor = isSimulated
        ? AppDesignTokens.warningText
        : isMissing
            ? AppDesignTokens.danger
            : AppDesignTokens.success;

    final queueNames = _discoveredPrinters.map((p) => p.name).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppDesignTokens.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.print, color: AppDesignTokens.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      configuredName != null && configuredName.isNotEmpty
                          ? configuredName
                          : 'Aucune imprimante ticket sélectionnée',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppDesignTokens.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSimulated
                          ? 'Mode Simulation actif'
                          : isMissing
                              ? 'File d\'impression Windows introuvable'
                              : 'Prête pour impression ESC/POS directe ($_paperWidth mm)',
                      style: TextStyle(fontSize: 12, color: statusColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isSimulated ? 'SIMULÉE' : isMissing ? 'HORS-LIGNE' : 'CONNECTÉE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: [
              ButtonSegment<String>(
                value: 'SPOOLER',
                icon: const Icon(Icons.usb, size: 16),
                label: Text(Platform.isMacOS ? 'USB / CUPS Local' : 'USB / Spooler Windows'),
              ),
              const ButtonSegment<String>(
                value: 'NETWORK',
                icon: Icon(Icons.wifi, size: 16),
                label: Text('Réseau (Wi-Fi / LAN IP)'),
              ),
            ],
            selected: {_printerConnectionType},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() => _printerConnectionType = newSelection.first);
            },
          ),
          const SizedBox(height: 16),
          if (_printerConnectionType == 'NETWORK') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _networkIpController,
                    decoration: InputDecoration(
                      labelText: 'Adresse IP de l\'imprimante',
                      hintText: '192.168.1.100',
                      prefixIcon: const Icon(Icons.lan_outlined, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _networkPortController,
                    decoration: InputDecoration(
                      labelText: 'Port (9100)',
                      hintText: '9100',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isTestingNetworkConnection ? null : _testNetworkPing,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppDesignTokens.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                    ),
                    icon: _isTestingNetworkConnection
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_ping, size: 18),
                    label: const Text('Tester Ping'),
                  ),
                ),
              ],
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: (_selectedPrinterQueue != null && queueNames.contains(_selectedPrinterQueue))
                  ? _selectedPrinterQueue
                  : (queueNames.isNotEmpty ? queueNames.first : null),
              decoration: InputDecoration(
                labelText: Platform.isMacOS
                    ? 'File d\'impression CUPS détectée (macOS)'
                    : 'File d\'impression Windows détectée (Spooler)',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
              ),
              items: queueNames.map((name) {
                final candidate = _discoveredPrinters.where((p) => p.name == name).firstOrNull;
                final extra = candidate != null ? ' (${candidate.portName})' : (name == configuredName ? ' (Actuelle)' : '');
                return DropdownMenuItem<String>(
                  value: name,
                  child: Text('$name$extra', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedPrinterQueue = val);
              },
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _paperWidth,
                  decoration: const InputDecoration(labelText: 'Largeur du papier'),
                  items: const [
                    DropdownMenuItem(value: 58, child: Text('58 mm (32 colonnes)')),
                    DropdownMenuItem(value: 80, child: Text('80 mm (48 colonnes)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _paperWidth = v);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SwitchListTile(
                  title: const Text('Coupe-papier automatique'),
                  value: _cutterEnabled,
                  activeThumbColor: AppDesignTokens.primary,
                  onChanged: (v) => setState(() => _cutterEnabled = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            title: const Text('Tiroir-caisse connecté au port RJ11/RJ12 de l’imprimante'),
            subtitle: Text(_drawerEnabled ? 'Impulsion envoyée à l\'impression' : 'Non activé'),
            value: _drawerEnabled,
            activeThumbColor: AppDesignTokens.primary,
            onChanged: (v) => setState(() => _drawerEnabled = v),
          ),
          if (_drawerEnabled) ...[
            DropdownButtonFormField<int>(
              initialValue: _drawerPin,
              decoration: const InputDecoration(labelText: 'Broche du tiroir'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Broche 2 (Standard Epson)')),
                DropdownMenuItem(value: 1, child: Text('Broche 5 (Inverse)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _drawerPin = v);
              },
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _isSavingPrinter ? null : _saveAndActivatePrinter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Enregistrer & Activer'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoadingPrinters ? null : _refreshPrinters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesignTokens.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  side: const BorderSide(color: AppDesignTokens.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: _isLoadingPrinters
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Rafraîchir les Imprimantes'),
              ),
              ElevatedButton.icon(
                onPressed: _testReceiptPrinter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Imprimer Ticket Test (Certifié Boutique)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required String title,
    required String subtitle,
    required HardwareStatus status,
    required IconData icon,
    required VoidCallback onTest,
    required String testLabel,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
          border: Border.all(color: AppDesignTokens.border),
          boxShadow: AppDesignTokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppDesignTokens.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppDesignTokens.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: status.color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    status.labelFr,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: status.color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.surfaceElevated,
                  foregroundColor: AppDesignTokens.textPrimary,
                  elevation: 0,
                  side: const BorderSide(color: AppDesignTokens.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(testLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
