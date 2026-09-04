import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/database_integrity_service.dart';
import 'package:jazzpos/hardware/hardware_manager.dart';
import 'package:jazzpos/hardware/label_printer/label_document.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isBackingUp = false;
  bool _isRunningDiagnostics = false;
  IntegrityReport? _integrityReport;
  List<BackupRecord> _backups = [];
  String? _hardwareStatusMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBackups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    final db = ref.read(databaseProvider);
    final backups = await (db.select(db.backupRecords)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
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
          const SnackBar(content: Text('Sauvegarde SQLite atomique créée avec succès !'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sauvegarde: $e'), backgroundColor: AppTheme.error),
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
          SnackBar(content: Text('Erreur diagnostic: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _testReceiptPrinter() async {
    try {
      final doc = ReceiptDocument(
        storeName: 'JAZZ FASHION - TEST',
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
          ),
        ],
        subtotal: const Money.fromMillimes(49000),
        discount: Money.zero,
        tax: const Money.fromMillimes(7823),
        total: const Money.fromMillimes(49000),
        payments: const [ReceiptPaymentItem(method: 'ESPECES', amount: Money.fromMillimes(49000))],
      );
      await HardwareManager.instance.receiptPrinter.printReceipt(doc);
      setState(() => _hardwareStatusMsg = 'Test Ticket ESC/POS envoyé');
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur ticket: $e');
    }
  }

  Future<void> _testLabelPrinter() async {
    try {
      const doc = LabelDocument(
        storeName: 'JAZZ FASHION',
        productName: 'Chemise Slim Fit Test',
        size: 'L',
        color: 'Bleu',
        sku: 'TST-LBL-01',
        barcode: '2000000000018',
        price: Money.fromMillimes(59000),
      );
      await HardwareManager.instance.labelPrinter.printLabel(doc);
      setState(() => _hardwareStatusMsg = 'Test Étiquette TSPL/ZPL envoyé');
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur étiquette: $e');
    }
  }

  Future<void> _testCashDrawer() async {
    try {
      await HardwareManager.instance.cashDrawer.openDrawer();
      setState(() => _hardwareStatusMsg = 'Impulsion tiroir-caisse RJ11 envoyée');
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur tiroir: $e');
    }
  }

  Future<void> _testCustomerDisplay() async {
    try {
      await HardwareManager.instance.customerDisplay.showWelcome();
      setState(() => _hardwareStatusMsg = 'Message de bienvenue envoyé à l\'afficheur client');
    } catch (e) {
      setState(() => _hardwareStatusMsg = 'Erreur afficheur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Paramètres & Maintenance du Système'),
        backgroundColor: AppTheme.surface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.print), text: 'MATÉRIEL POS'),
            Tab(icon: Icon(Icons.backup), text: 'SAUVEGARDE & INTÉGRITÉ'),
            Tab(icon: Icon(Icons.swap_vert), text: 'IMPORT / EXPORT CSV'),
            Tab(icon: Icon(Icons.info_outline), text: 'SYSTÈME & BOUTIQUE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHardwareTab(),
          _buildBackupTab(),
          _buildImportExportTab(),
          _buildSystemInfoTab(),
        ],
      ),
    );
  }

  Widget _buildHardwareTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hardwareStatusMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _hardwareStatusMsg!.contains('Erreur') ? Colors.red.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(_hardwareStatusMsg!.contains('Erreur') ? Icons.error_outline : Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(_hardwareStatusMsg!, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          const Text('Diagnostics et Tests des Périphériques POSBANK / Windows :', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Row(
            children: [
              _buildDeviceCard(
                title: 'Imprimante Ticket de Caisse',
                subtitle: 'ESC/POS thermique (80mm / 58mm)',
                icon: Icons.receipt_long,
                onTest: _testReceiptPrinter,
                testLabel: 'Imprimer Ticket Test',
              ),
              const SizedBox(width: 16),
              _buildDeviceCard(
                title: 'Imprimante Étiquettes',
                subtitle: 'TSPL / ZPL Code-barres',
                icon: Icons.qr_code,
                onTest: _testLabelPrinter,
                testLabel: 'Imprimer Étiquette Test',
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              _buildDeviceCard(
                title: 'Tiroir-Caisse Électrique',
                subtitle: 'Port RJ11 piloté via ESC/POS',
                icon: Icons.point_of_sale,
                onTest: _testCashDrawer,
                testLabel: 'Tester Éjection Tiroir',
              ),
              const SizedBox(width: 16),
              _buildDeviceCard(
                title: 'Afficheur Client',
                subtitle: 'VFD 2x20 caractères (RS232 / USB)',
                icon: Icons.tv,
                onTest: _testCustomerDisplay,
                testLabel: 'Tester Message VFD',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({required String title, required String subtitle, required IconData icon, required VoidCallback onTest, required String testLabel}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppTheme.primaryLight, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onTest,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF161F2E), foregroundColor: Colors.white),
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
            children: [
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _createBackup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                icon: _isBackingUp
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.backup),
                label: Text(_isBackingUp ? 'SAUVEGARDE EN COURS...' : 'CRÉER UNE SAUVEGARDE (VACUUM INTO)'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _isRunningDiagnostics ? null : _runDiagnostics,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                icon: _isRunningDiagnostics
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.health_and_safety),
                label: const Text('DIAGNOSTIC D\'INTÉGRITÉ SQLITE'),
              ),
            ],
          ),

          if (_integrityReport != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _integrityReport!.isHealthy ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _integrityReport!.isHealthy ? AppTheme.success : AppTheme.error),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_integrityReport!.isHealthy ? Icons.check_circle : Icons.error, color: _integrityReport!.isHealthy ? AppTheme.success : AppTheme.error),
                      const SizedBox(width: 8),
                      Text(
                        _integrityReport!.isHealthy ? 'Base de données saine et intègre (PRAGMA OK)' : 'Anomalies détectées',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _integrityReport!.isHealthy ? AppTheme.success : AppTheme.error),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Ventes: ${_integrityReport!.totalSales} • Articles: ${_integrityReport!.totalProducts} • Mouvements: ${_integrityReport!.totalMovements}'),
                  if (_integrityReport!.issues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._integrityReport!.issues.map((i) => Text('• $i', style: const TextStyle(color: Colors.redAccent))),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Text('Historique des Sauvegardes Locales :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: _backups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Aucune sauvegarde locale pour le moment', style: TextStyle(color: AppTheme.textSecondary))),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _backups.length,
                    separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                    itemBuilder: (context, index) {
                      final b = _backups[index];
                      final sizeMb = (b.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2);
                      final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(b.createdAt);

                      return ListTile(
                        leading: const Icon(Icons.storage, color: AppTheme.primaryLight),
                        title: Text('Sauvegarde du $dateStr', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Fichier: ${b.filePath}\nSHA-256: ${b.checksum.substring(0, 16)}... • Taille: $sizeMb Mo'),
                        trailing: const Icon(Icons.verified, color: AppTheme.success, size: 20),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportExportTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Import & Export de Données Catalogue :', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final service = ref.read(importExportServiceProvider);
                  final csvData = await service.exportCatalogCsv();
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: const Text('Catalogue exporté en CSV'),
                        content: SizedBox(
                          width: 600,
                          height: 300,
                          child: TextField(
                            controller: TextEditingController(text: csvData),
                            maxLines: null,
                            readOnly: true,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
                        ],
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                icon: const Icon(Icons.download),
                label: const Text('EXPORTER CATALOGUE CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Informations Système & Point de Vente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Column(
              children: [
                _InfoRow('Application :', 'JazzPOS Desktop v1.0.0 (Production Build)'),
                Divider(color: AppTheme.border),
                _InfoRow('Moteur de Base de Données :', 'SQLite 3 via Drift (WAL Mode enabled)'),
                Divider(color: AppTheme.border),
                _InfoRow('Devise Principale :', 'Dinar Tunisien (TND - 3 décimales, calculs en millimes entiers)'),
                Divider(color: AppTheme.border),
                _InfoRow('Architecture Cible :', 'Windows 10 / 11 POS (Compatible Terminaux POSBANK)'),
                Divider(color: AppTheme.border),
                _InfoRow('Politique Hors-ligne :', '100% Autonome (Opérations caisse, stocks, tickets garanties hors-ligne)'),
              ],
            ),
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
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
