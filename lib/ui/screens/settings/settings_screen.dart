import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/localization/app_localizations_delegate.dart';
import 'package:jazzpos/core/localization/locale_provider.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/core/platform/windows_startup.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/core/platform/export_diagnostic_report_service.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'hardware_setup_wizard.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/common/app_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isBackingUp = false;
  bool _isRunningDiagnostics = false;
  bool _isImporting = false;
  bool _isExporting = false;
  IntegrityReport? _integrityReport;
  List<BackupRecord> _backups = [];
  String? _hardwareStatusMsg;
  bool _autoStartEnabled = false;
  Map<String, bool>? _storageHealth;

  Future<String> _companyNameForTestPrint() async {
    final db = ref.read(databaseProvider);
    final company = await (db.select(db.companies)..limit(1)).getSingleOrNull();
    return company?.name.trim().isNotEmpty == true
        ? company!.name.trim()
        : 'JAZZ POS';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBackups();
    _checkAutoStart();
    _checkStorageHealth();
  }

  Future<void> _checkAutoStart() async {
    if (Platform.isWindows) {
      final enabled = await WindowsStartup.isAutoStartEnabled();
      if (mounted) setState(() => _autoStartEnabled = enabled);
    }
  }

  Future<void> _checkStorageHealth() async {
    final health = await AppPaths.instance.verifyStorageHealth();
    if (mounted) setState(() => _storageHealth = health);
  }

  Future<void> _toggleAutoStart(bool enable) async {
    if (enable) {
      await WindowsStartup.enableAutoStart();
    } else {
      await WindowsStartup.disableAutoStart();
    }
    await _checkAutoStart();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    final db = ref.read(databaseProvider);
    final backups = await (db.select(
      db.backupRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    if (mounted) setState(() => _backups = backups);
  }

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      await backupService.createLocalBackup();
      await _loadBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.backupSuccess),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _runDiagnostics() async {
    setState(() => _isRunningDiagnostics = true);
    try {
      final integrityService = ref.read(databaseIntegrityServiceProvider);
      final report = await integrityService.runDiagnostics();
      if (mounted) {
        setState(() {
          _integrityReport = report;
          _isRunningDiagnostics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRunningDiagnostics = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportCatalog() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final csv = await ref
          .read(importExportServiceProvider)
          .exportCatalogCsv();
      final date = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final location = await getSaveLocation(
        suggestedName: 'jazzpos-catalog-$date.csv',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        name: 'jazzpos-catalog-$date.csv',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Catalogue exporté : ${location.path}'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $error'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importCatalog() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (file == null) return;
      final service = ref.read(importExportServiceProvider);
      final preview = await service.previewCsvImport(await file.readAsString());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aperçu de l’importation'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${preview.totalRows} ligne(s) analysée(s)'),
                Text('${preview.validRows} valide(s)'),
                Text('${preview.invalidRows} rejetée(s)'),
                if (preview.invalidRows > 0) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Erreurs :',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...preview.previews
                      .where((row) => !row.isValid)
                      .take(5)
                      .map(
                        (row) => Text(
                          'Ligne ${row.rowNumber} : ${row.errorMessage}',
                        ),
                      ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: preview.validRows == 0
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('Importer ${preview.validRows} ligne(s)'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final user = ref.read(authNotifierProvider).user;
      if (user == null) throw StateError('Utilisateur non connecté.');
      final db = ref.read(databaseProvider);
      final store = await (db.select(db.stores)..limit(1)).getSingleOrNull();
      if (store == null) throw StateError('Aucun magasin configuré.');
      await service.commitImport(
        preview: preview,
        fileName: file.name,
        actorId: user.id,
        storeId: store.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${preview.validRows} ligne(s) importée(s).'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.loc.error}: $error'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _testReceiptPrinter() async {
    try {
      final companyName = await _companyNameForTestPrint();
      final doc = ReceiptDocument(
        storeName: '$companyName - TEST',
        receiptNumber: 'TEST-PRINT',
        dateTime: DateTime.now(),
        cashierName: 'Administrateur',
        registerCode: 'REG-01',
        lines: const [
          ReceiptLineItem(
            productName: 'Article Test Impression',
            variantDescription: 'Noir / L',
            sku: 'TST-001',
            barcode: '1234567890123',
            quantity: 1,
            unitPrice: Money.fromMillimes(49000),
            total: Money.fromMillimes(49000),
            discount: Money.zero,
          ),
        ],
        subtotal: const Money.fromMillimes(49000),
        discount: Money.zero,
        tax: Money.zero,
        total: const Money.fromMillimes(49000),
        payments: const [
          ReceiptPaymentItem(
            method: 'ESPECES',
            amount: Money.fromMillimes(49000),
            tendered: Money.fromMillimes(50000),
            change: Money.fromMillimes(1000),
          ),
        ],
      );

      await HardwareManager.instance.receiptPrinter.printReceipt(doc);
      setState(
        () => _hardwareStatusMsg =
            HardwareManager.instance.receiptPrinterIsSimulated
            ? 'SIMULATION : aperçu ticket généré, aucune impression physique'
            : 'Ticket de caisse test envoyé à l’imprimante physique',
      );
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur ticket: $e');
    }
  }

  Future<void> _testLabelPrinter() async {
    try {
      final companyName = await _companyNameForTestPrint();
      final doc = LabelDocument(
        storeName: companyName,
        productName: 'Polo Piqué Noir',
        size: 'L',
        sku: 'POLO-BLK-L',
        barcode: '200123456789',
        price: const Money.fromMillimes(59000),
        widthMm: 40,
        heightMm: 30,
        copies: 1,
      );
      await HardwareManager.instance.labelPrinter.printLabel(doc);
      setState(
        () => _hardwareStatusMsg =
            HardwareManager.instance.labelPrinterIsSimulated
            ? 'SIMULATION : étiquette générée, aucune impression physique'
            : 'Étiquette test envoyée à l’imprimante physique',
      );
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur étiquette: $e');
    }
  }

  Future<void> _testCashDrawer() async {
    try {
      await HardwareManager.instance.cashDrawer.openDrawer();
      setState(
        () =>
            _hardwareStatusMsg = HardwareManager.instance.cashDrawerIsSimulated
            ? 'SIMULATION : aucun tiroir physique n’a été ouvert'
            : context.loc.drawerKickSuccess,
      );
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur tiroir: $e');
    }
  }

  Future<void> _testCustomerDisplay() async {
    try {
      await HardwareManager.instance.customerDisplay.showWelcome();
      setState(
        () => _hardwareStatusMsg =
            HardwareManager.instance.customerDisplayIsSimulated
            ? 'SIMULATION : aucun afficheur client physique n’a été piloté'
            : 'Message envoyé à l\'afficheur physique',
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
          SnackBar(
            content: Text('Erreur lors de l\'export du diagnostic : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    }
  }

  void _toggleZeroHardwareMode(bool enabled) {
    setState(() {
      if (enabled) {
        HardwareManager.instance.enableZeroHardwareMode();
        _hardwareStatusMsg =
            'Mode Zéro-Matériel activé (Aperçu à l\'écran sans erreur).';
      } else {
        HardwareManager.instance.initializeSimulatedHardware();
        _hardwareStatusMsg = 'Mode standard réactivé.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          context.loc.settingsTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        backgroundColor: AppDesignTokens.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppDesignTokens.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: AppDesignTokens.primary,
                labelColor: AppDesignTokens.primary,
                unselectedLabelColor: AppDesignTokens.textSecondary,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.language, size: 20),
                    text: context.loc.tabGeneral,
                  ),
                  Tab(
                    icon: const Icon(Icons.print, size: 20),
                    text: context.loc.tabHardware,
                  ),
                  Tab(
                    icon: const Icon(Icons.backup, size: 20),
                    text: context.loc.tabBackup,
                  ),
                  Tab(
                    icon: const Icon(Icons.swap_vert, size: 20),
                    text: context.loc.tabImportExport,
                  ),
                ],
              ),
              const Divider(height: 1, color: AppDesignTokens.border),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralAndLanguageTab(),
          _buildHardwareTab(),
          _buildBackupTab(),
          _buildImportExportTab(),
        ],
      ),
    );
  }

  Widget _buildGeneralAndLanguageTab() {
    final currentLocale = ref.watch(localeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Language Selection Card
          Text(
            context.loc.languageSection,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignTokens.space12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.selectLanguage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppDesignTokens.space16),
                Row(
                  children: [
                    _buildLanguageOption(
                      title: 'Français',
                      subtitle: 'Français (Tunisie)',
                      code: 'fr',
                      flag: '🇫🇷',
                      isSelected: currentLocale.languageCode == 'fr',
                    ),
                    const SizedBox(width: AppDesignTokens.space16),
                    _buildLanguageOption(
                      title: 'العربية',
                      subtitle: 'عربي (RTL كامل)',
                      code: 'ar',
                      flag: '🇹🇳',
                      isSelected: currentLocale.languageCode == 'ar',
                    ),
                    const SizedBox(width: AppDesignTokens.space16),
                    _buildLanguageOption(
                      title: 'English',
                      subtitle: 'English (US/UK)',
                      code: 'en',
                      flag: '🇬🇧',
                      isSelected: currentLocale.languageCode == 'en',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDesignTokens.space24),

          // 2. System & Hardware diagnostics
          const Text(
            'Informations Système & Point de Vente',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignTokens.space12),
          AppCard(
            child: Column(
              children: [
                const _InfoRow(
                  'Application :',
                  'JazzPOS Desktop v1.0.0 (Production)',
                ),
                const Divider(color: AppDesignTokens.border),
                const _InfoRow(
                  'Moteur de Base de Données :',
                  'SQLite 3 via Drift (WAL Mode, Schema v2)',
                ),
                const Divider(color: AppDesignTokens.border),
                const _InfoRow(
                  'Devise Principale :',
                  'Dinar Tunisien (TND - 3 décimales, millimes entiers)',
                ),
                const Divider(color: AppDesignTokens.border),
                const _InfoRow(
                  'Architecture Cible :',
                  'Windows 10/11 IoT & macOS POS',
                ),
                const Divider(color: AppDesignTokens.border),
                _InfoRow(
                  'Base de Données Locale :',
                  AppPaths.instance.databaseFilePath,
                ),
                const Divider(color: AppDesignTokens.border),
                _InfoRow(
                  'Dossier Sauvegardes :',
                  AppPaths.instance.backupsDir.path,
                ),
                if (_storageHealth != null) ...[
                  const Divider(color: AppDesignTokens.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Santé Stockage / Permissions :',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                        Text(
                          _storageHealth!.values.every((v) => v)
                              ? 'TOUS DOSSIERS ACCESSIBLES EN ÉCRITURE (OK)'
                              : 'ERREUR PERMISSION DOSSIER',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _storageHealth!.values.every((v) => v)
                                ? AppDesignTokens.success
                                : AppDesignTokens.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (Platform.isWindows) ...[
                  const Divider(color: AppDesignTokens.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Démarrage automatique Windows :',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                            Text(
                              'Lancer JAZZ POS automatiquement au démarrage du terminal caisse',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppDesignTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _autoStartEnabled,
                          onChanged: (val) => _toggleAutoStart(val),
                          activeThumbColor: AppDesignTokens.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required String title,
    required String subtitle,
    required String code,
    required String flag,
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          await ref.read(localeProvider.notifier).setLocale(Locale(code));
        },
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(AppDesignTokens.space16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppDesignTokens.primary.withValues(alpha: 0.08)
                : AppDesignTokens.surface,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(
              color: isSelected
                  ? AppDesignTokens.primary
                  : AppDesignTokens.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: AppDesignTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? AppDesignTokens.primary
                            : AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppDesignTokens.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHardwareTab() {
    final hw = HardwareManager.instance;
    final isZeroHw = hw.isZeroHardwareMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Automated Wizard & Diagnostics Hub Card
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
              border: Border.all(
                color: AppDesignTokens.primary.withValues(alpha: 0.3),
              ),
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
                      child: const Icon(
                        Icons.auto_fix_high,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assistant de Détection & Configuration Automatique',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Inspecte l\'environnement Windows, identifie automatiquement le Spooler d\'impression, les ports COM/USB, le tiroir-caisse et l\'afficheur client, puis applique la meilleure configuration sans modification de code source.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppDesignTokens.textSecondary,
                            ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusInput,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.settings_suggest, size: 18),
                      label: const Text(
                        'Lancer l\'Assistant (Automatic Setup)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportDiagnosticReport,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppDesignTokens.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        side: const BorderSide(color: AppDesignTokens.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusInput,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text(
                        'Exporter Rapport de Diagnostic (.json)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Zero-Hardware Mode Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isZeroHw
                  ? AppDesignTokens.warningBg
                  : AppDesignTokens.surface,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(
                color: isZeroHw
                    ? AppDesignTokens.warning
                    : AppDesignTokens.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isZeroHw ? Icons.science : Icons.devices,
                  color: isZeroHw
                      ? AppDesignTokens.warningText
                      : AppDesignTokens.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Zéro-Matériel (Démonstration & Hors-Ligne)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isZeroHw
                              ? AppDesignTokens.warningText
                              : AppDesignTokens.textPrimary,
                        ),
                      ),
                      Text(
                        isZeroHw
                            ? 'Actif : Les tickets s\'ouvrent en aperçu interactif. Aucune tentative physique bloquante.'
                            : 'Inactif : Connexion et impression vers les périphériques matériels réels configurés.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isZeroHw
                              ? AppDesignTokens.warningText
                              : AppDesignTokens.textSecondary,
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
                    : _hardwareStatusMsg!.contains('SIMULATION') ||
                          _hardwareStatusMsg!.contains('Zéro-Matériel')
                    ? AppDesignTokens.warningBg
                    : AppDesignTokens.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.radiusInput,
                ),
                border: Border.all(
                  color: _hardwareStatusMsg!.contains('Erreur')
                      ? AppDesignTokens.danger.withValues(alpha: 0.3)
                      : _hardwareStatusMsg!.contains('SIMULATION') ||
                            _hardwareStatusMsg!.contains('Zéro-Matériel')
                      ? AppDesignTokens.warning
                      : AppDesignTokens.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hardwareStatusMsg!.contains('Erreur')
                        ? Icons.error_outline
                        : _hardwareStatusMsg!.contains('SIMULATION') ||
                              _hardwareStatusMsg!.contains('Zéro-Matériel')
                        ? Icons.science_outlined
                        : Icons.check_circle,
                    color: _hardwareStatusMsg!.contains('Erreur')
                        ? AppDesignTokens.danger
                        : _hardwareStatusMsg!.contains('SIMULATION') ||
                              _hardwareStatusMsg!.contains('Zéro-Matériel')
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
                            : _hardwareStatusMsg!.contains('SIMULATION') ||
                                  _hardwareStatusMsg!.contains('Zéro-Matériel')
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

          const Text(
            'État des Périphériques Configurés :',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              _buildDeviceCard(
                title: context.loc.printerThermal,
                subtitle: hw.receiptPrinterIsSimulated
                    ? 'MODE SIMULÉ — aperçu à l\'écran'
                    : '${hw.receiptPrinter.name} (${hw.receiptPrinter.connectionType})',
                status: hw.printerStatus,
                icon: Icons.receipt_long,
                onTest: _testReceiptPrinter,
                testLabel: context.loc.testPrinter,
              ),
              const SizedBox(width: 16),
              _buildDeviceCard(
                title: context.loc.printerLabel,
                subtitle: hw.labelPrinterIsSimulated
                    ? 'MODE SIMULÉ — aucune imprimante physique'
                    : hw.labelPrinter.name,
                status: hw.labelPrinterIsSimulated
                    ? HardwareStatus.simulated
                    : HardwareStatus.ready,
                icon: Icons.qr_code,
                onTest: _testLabelPrinter,
                testLabel: context.loc.testLabelPrinter,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              _buildDeviceCard(
                title: 'Tiroir-Caisse Électrique',
                subtitle: hw.cashDrawerIsSimulated
                    ? 'MODE SIMULÉ — commande non envoyée'
                    : '${hw.cashDrawer.name} (${hw.cashDrawer.mode.labelFr})',
                status: hw.drawerStatus,
                icon: Icons.point_of_sale,
                onTest: _testCashDrawer,
                testLabel: context.loc.testCashDrawer,
              ),
              const SizedBox(width: 16),
              _buildDeviceCard(
                title: context.loc.customerDisplay,
                subtitle: hw.customerDisplayIsSimulated
                    ? 'MODE SIMULÉ — aucun afficheur piloté'
                    : '${hw.customerDisplay.name} (${hw.customerDisplay.mode.labelFr})',
                status: hw.displayStatus,
                icon: Icons.tv,
                onTest: _testCustomerDisplay,
                testLabel: context.loc.testCustomerDisplay,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Barcode Scanner Card
          Row(
            children: [
              _buildDeviceCard(
                title: 'Douchette Code-barres USB',
                subtitle:
                    'Mode Clavier virtuel (HID Keyboard Wedge, <80ms avec Entrée)',
                status: hw.scannerStatus,
                icon: Icons.barcode_reader,
                onTest: () {
                  setState(() {
                    _hardwareStatusMsg =
                        'Scanner actif en écoute continue sur toutes les saisies clavier.';
                  });
                },
                testLabel: 'Écoute Active',
              ),
              const SizedBox(width: 16),
              const Spacer(),
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
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: status.color.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    status.labelFr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: status.color,
                    ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusInput,
                    ),
                  ),
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

  Widget _buildBackupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.backupDatabase,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sauvegarde SQLite atomique avec VACUUM INTO garantissant zéro corruption',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _createBackup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusInput,
                    ),
                  ),
                ),
                icon: _isBackingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.backup),
                label: Text(
                  _isBackingUp
                      ? context.loc.processing
                      : context.loc.backupDatabase,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.databaseIntegrity,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const Text(
                    'PRAGMA integrity_check & foreign_key_check',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isRunningDiagnostics ? null : _runDiagnostics,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.surfaceElevated,
                  foregroundColor: AppDesignTokens.textPrimary,
                  elevation: 0,
                  side: const BorderSide(color: AppDesignTokens.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusInput,
                    ),
                  ),
                ),
                icon: _isRunningDiagnostics
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppDesignTokens.textPrimary,
                        ),
                      )
                    : const Icon(Icons.health_and_safety),
                label: Text(context.loc.runDiagnostics),
              ),
            ],
          ),

          if (_integrityReport != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _integrityReport!.isHealthy
                    ? AppDesignTokens.success.withValues(alpha: 0.08)
                    : AppDesignTokens.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                border: Border.all(
                  color: _integrityReport!.isHealthy
                      ? AppDesignTokens.success
                      : AppDesignTokens.danger,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _integrityReport!.isHealthy
                            ? Icons.check_circle
                            : Icons.error,
                        color: _integrityReport!.isHealthy
                            ? AppDesignTokens.success
                            : AppDesignTokens.danger,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _integrityReport!.isHealthy
                            ? context.loc.diagnosticsPass
                            : 'Anomalies détectées dans la base de données',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _integrityReport!.isHealthy
                              ? AppDesignTokens.successText
                              : AppDesignTokens.dangerText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ventes : ${_integrityReport!.totalSales} | '
                    'Articles : ${_integrityReport!.totalProducts} | '
                    'Variantes : ${_integrityReport!.totalVariants} | '
                    'Mouvements : ${_integrityReport!.totalMovements} | '
                    'Erreurs : ${_integrityReport!.issues.length} | '
                    'Avertissements : ${_integrityReport!.warnings.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 24),

          const Text(
            'Historique des Sauvegardes Disponibles :',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          if (_backups.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune sauvegarde enregistrée',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _backups.length,
              itemBuilder: (ctx, i) {
                final b = _backups[i];
                final fileName = b.filePath.split(Platform.pathSeparator).last;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusCard,
                    ),
                    border: Border.all(color: AppDesignTokens.border),
                    boxShadow: AppDesignTokens.shadowSm,
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.archive,
                      color: AppDesignTokens.primary,
                    ),
                    title: Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Créée le : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(b.createdAt)} | '
                      'Taille : ${(b.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                      style: const TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'VALIDE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppDesignTokens.successText,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildImportExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Importation et Exportation du Catalogue en CSV',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Format standard UTF-8 avec séparateur point-virgule (;). Compatible Excel et LibreOffice.',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.download,
                        size: 36,
                        color: AppDesignTokens.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.loc.exportCsv,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Exporte l\'intégralité des articles, variantes, prix, stocks et codes-barres vers un fichier CSV.',
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportCatalog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppDesignTokens.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusInput,
                              ),
                            ),
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download),
                          label: Text(context.loc.exportCsv),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.upload,
                        size: 36,
                        color: AppDesignTokens.success,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.loc.importCsv,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Importe de nouveaux articles en lot avec aperçu et validation transactionnelle des doublons.',
                        style: TextStyle(
                          color: AppDesignTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importCatalog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppDesignTokens.success,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusInput,
                              ),
                            ),
                          ),
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_upload),
                          label: Text(context.loc.importCsv),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
