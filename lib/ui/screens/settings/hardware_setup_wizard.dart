import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/platform/environment_diagnostics_service.dart';
import 'package:jazzpos/core/platform/export_diagnostic_report_service.dart';
import 'package:jazzpos/hardware/barcode_scanner/scanner_input_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

/// Interactive Hardware Setup Wizard enabling 1-click peripheral discovery,
/// recommendations, and testing.
class HardwareSetupWizard extends ConsumerStatefulWidget {
  const HardwareSetupWizard({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: SizedBox(width: 720, child: HardwareSetupWizard()),
      ),
    );
  }

  @override
  ConsumerState<HardwareSetupWizard> createState() =>
      _HardwareSetupWizardState();
}

class _HardwareSetupWizardState extends ConsumerState<HardwareSetupWizard> {
  bool _isScanning = false;
  bool _isApplying = false;
  String? _statusBanner;
  EnvironmentDiagnosticReport? _envReport;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    final envService = ref.read(environmentDiagnosticsServiceProvider);
    final report = await envService.inspectEnvironment();
    if (mounted) {
      setState(() => _envReport = report);
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _isScanning = true;
      _statusBanner = null;
    });
    try {
      await HardwareManager.instance.runDiscoveryScan();
      await _loadDiagnostics();
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusBanner = 'Analyse du matériel terminée avec succès.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusBanner = 'Erreur lors de l\'analyse : $e';
        });
      }
    }
  }

  Future<void> _applyRecommended() async {
    final rec = HardwareManager.instance.latestRecommendations;
    if (rec == null) {
      await _scanAgain();
    }
    final recToApply = HardwareManager.instance.latestRecommendations;
    if (recToApply == null) return;

    setState(() => _isApplying = true);
    try {
      await HardwareManager.instance.applyRecommendations(recToApply);
      if (mounted) {
        setState(() {
          _isApplying = false;
          _statusBanner = 'Configuration recommandée appliquée !';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
          _statusBanner = 'Erreur d\'application : $e';
        });
      }
    }
  }

  Future<void> _testPrinter() async {
    try {
      await HardwareManager.instance.testReceiptPrinter();
      if (mounted) {
        setState(
          () => _statusBanner = 'Ticket de test envoyé à l\'imprimante.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Erreur test ticket : $e');
      }
    }
  }

  Future<void> _testArabicRaster() async {
    try {
      await HardwareManager.instance.testArabicPrinting();
      if (mounted) {
        setState(
          () =>
              _statusBanner = 'Test raster/arabe (GS v 0) envoyé avec succès.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Erreur test raster : $e');
      }
    }
  }

  Future<void> _testDrawer() async {
    try {
      await HardwareManager.instance.testCashDrawer();
      if (mounted) {
        setState(
          () => _statusBanner =
              'Impulsion d\'ouverture envoyée au tiroir-caisse.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Erreur test tiroir : $e');
      }
    }
  }

  Future<void> _testDisplay() async {
    try {
      await HardwareManager.instance.testCustomerDisplay();
      if (mounted) {
        setState(
          () => _statusBanner =
              'Message de bienvenue envoyé à l\'afficheur client.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Erreur test afficheur : $e');
      }
    }
  }

  Future<void> _testScanner() async {
    showDialog(
      context: context,
      builder: (ctx) => _ScannerTestDialog(
        scannerService:
            HardwareManager.instance.barcodeScanner is ScannerInputService
            ? HardwareManager.instance.barcodeScanner as ScannerInputService
            : null,
      ),
    );
  }

  Future<void> _exportReport() async {
    try {
      final path = await ExportDiagnosticReportService.exportReportToFile(
        envReport: _envReport,
      );
      if (path != null && mounted) {
        setState(() => _statusBanner = 'Rapport exporté : $path');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Erreur export : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hw = HardwareManager.instance;
    final env = _envReport;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppDesignTokens.shadowLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.precision_manufacturing,
                    color: AppDesignTokens.primary,
                    size: 26,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'JAZZ POS — Configuration Matériel & Diagnostic',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: AppDesignTokens.textSecondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Status Banner if present
          if (_statusBanner != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _statusBanner!.contains('Erreur')
                    ? AppDesignTokens.dangerBg
                    : AppDesignTokens.successBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusBanner!.contains('Erreur')
                      ? AppDesignTokens.danger
                      : AppDesignTokens.success,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusBanner!.contains('Erreur')
                        ? Icons.error_outline
                        : Icons.check_circle,
                    color: _statusBanner!.contains('Erreur')
                        ? AppDesignTokens.danger
                        : AppDesignTokens.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusBanner!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _statusBanner!.contains('Erreur')
                            ? AppDesignTokens.dangerText
                            : AppDesignTokens.successText,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Peripheral Cards List
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 1. System Card
                  _buildDeviceRow(
                    title: 'Système d\'exploitation',
                    subtitle: env != null
                        ? '${env.osEdition} (${env.architecture}) — RAM: ${env.totalRamMb ?? 'N/A'} MB — Disque: ${env.freeDiskMb ?? 'N/A'} MB libres'
                        : 'Inspection du système en cours...',
                    statusBadge: env?.isSupportedWindows == true
                        ? _StatusBadge(
                            status: HardwareStatus.ready,
                            text: 'READY',
                          )
                        : _StatusBadge(
                            status: HardwareStatus.error,
                            text: 'ATTENTION',
                          ),
                    actions: const [],
                  ),
                  const SizedBox(height: 12),

                  // 2. Receipt Printer
                  _buildDeviceRow(
                    title: 'Imprimante Ticket (Caisse)',
                    subtitle: hw.receiptPrinter.name,
                    statusBadge: _StatusBadge(status: hw.printerStatus),
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _testArabicRaster,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        icon: const Icon(Icons.image, size: 16),
                        label: const Text(
                          'Test Arabe/Raster',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _testPrinter,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text(
                          'Tester',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 3. Barcode Scanner
                  _buildDeviceRow(
                    title: 'Lecteur Code-barres',
                    subtitle: hw.barcodeScanner.name,
                    statusBadge: _StatusBadge(status: hw.scannerStatus),
                    actions: [
                      FilledButton.icon(
                        onPressed: _testScanner,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.qr_code_scanner, size: 16),
                        label: const Text(
                          'Tester',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. Cash Drawer
                  _buildDeviceRow(
                    title: 'Tiroir-Caisse Électrique',
                    subtitle: hw.cashDrawer.name,
                    statusBadge: _StatusBadge(status: hw.drawerStatus),
                    actions: [
                      FilledButton.icon(
                        onPressed:
                            hw.drawerStatus == HardwareStatus.notConfigured
                            ? null
                            : _testDrawer,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.point_of_sale, size: 16),
                        label: const Text(
                          'Tester',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5. Customer Display
                  _buildDeviceRow(
                    title: 'Afficheur Client',
                    subtitle: hw.customerDisplay.name,
                    statusBadge: _StatusBadge(status: hw.displayStatus),
                    actions: [
                      FilledButton.icon(
                        onPressed:
                            hw.displayStatus == HardwareStatus.notConfigured
                            ? null
                            : _testDisplay,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.tv, size: 16),
                        label: const Text(
                          'Tester',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 16),

          // Action Buttons Bar
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isScanning ? null : _scanAgain,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Relancer l\'analyse'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _exportReport,
                icon: const Icon(Icons.file_download),
                label: const Text('Exporter le rapport'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isApplying ? null : _applyRecommended,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Appliquer la recommandation'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceRow({
    required String title,
    required String subtitle,
    required Widget statusBadge,
    required List<Widget> actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppDesignTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    statusBadge,
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final HardwareStatus status;
  final String? text;

  const _StatusBadge({required this.status, this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text ?? status.labelFr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: status.color,
        ),
      ),
    );
  }
}

/// Modal dialog for interactive barcode scanner testing
class _ScannerTestDialog extends StatefulWidget {
  final ScannerInputService? scannerService;
  const _ScannerTestDialog({this.scannerService});

  @override
  State<_ScannerTestDialog> createState() => _ScannerTestDialogState();
}

class _ScannerTestDialogState extends State<_ScannerTestDialog> {
  final List<String> _scannedCodes = [];

  @override
  void initState() {
    super.initState();
    widget.scannerService?.onScan.listen((code) {
      if (mounted) {
        setState(() => _scannedCodes.insert(0, code));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner, color: AppDesignTokens.primary),
          SizedBox(width: 8),
          Text('Test du Lecteur Code-barres'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scannez un article avec votre douchette USB pour vérifier la vitesse et l\'encodage :',
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 160,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppDesignTokens.border),
              ),
              child: _scannedCodes.isEmpty
                  ? const Center(
                      child: Text(
                        'En attente d\'un scan...',
                        style: TextStyle(color: AppDesignTokens.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scannedCodes.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check,
                              color: AppDesignTokens.success,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _scannedCodes[i],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
