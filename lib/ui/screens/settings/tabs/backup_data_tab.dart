import 'package:tracepos/core/logging/pos_logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/core/localization/app_localizations_delegate.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/database_integrity_service.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_card.dart';

class BackupDataTab extends ConsumerStatefulWidget {
  const BackupDataTab({super.key});

  @override
  ConsumerState<BackupDataTab> createState() => _BackupDataTabState();
}

class _BackupDataTabState extends ConsumerState<BackupDataTab> {
  bool _isBackingUp = false;
  bool _isRunningDiagnostics = false;
  bool _isExporting = false;
  bool _isImporting = false;

  IntegrityReport? _integrityReport;
  List<BackupRecord> _backups = [];

  // Cloud Sync State
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();
  bool _cloudSyncEnabled = false;
  bool _isObscureKey = true;
  bool _isTestingCloud = false;
  bool _isSyncingCloud = false;
  bool _isSavingCloud = false;
  int _pendingOutbox = 0;
  int _syncedOutbox = 0;
  int _failedOutbox = 0;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadCloudConfigAndStats();
  }

  @override
  void dispose() {
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadCloudConfigAndStats() async {
    try {
      final syncService = ref.read(syncServiceProvider);
      final config = await syncService.getCloudConfig();
      final stats = await syncService.getSyncStats();
      if (mounted) {
        setState(() {
          _cloudSyncEnabled = config.enabled;
          _supabaseUrlController.text = config.url;
          _supabaseKeyController.text = config.key;
          _pendingOutbox = stats.pending;
          _syncedOutbox = stats.synced;
          _failedOutbox = stats.failed;
          _lastSyncAt = stats.lastSyncAt;
        });
      }
    } catch (e) {
      PosLogger.instance.warning('Settings', 'Could not load sync stats: $e');
    }
  }

  Future<void> _saveCloudConfig() async {
    setState(() => _isSavingCloud = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      await syncService.saveCloudConfig(
        enabled: _cloudSyncEnabled,
        url: _supabaseUrlController.text.trim(),
        key: _supabaseKeyController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration Cloud Supabase enregistrée avec succès.'),
            backgroundColor: AppDesignTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'enregistrement: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingCloud = false);
    }
  }

  Future<void> _testCloudConnection() async {
    setState(() => _isTestingCloud = true);
    final stopwatch = Stopwatch()..start();
    try {
      final syncService = ref.read(syncServiceProvider);
      final ok = await syncService.testConnection(
        url: _supabaseUrlController.text.trim(),
        key: _supabaseKeyController.text.trim(),
      );
      stopwatch.stop();
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connexion Supabase réussie (${stopwatch.elapsedMilliseconds} ms) !'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Échec de la connexion Supabase. Vérifiez l\'URL et la clé API.'),
              backgroundColor: AppDesignTokens.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur test de connexion: $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingCloud = false);
    }
  }

  Future<void> _triggerCloudSyncNow() async {
    setState(() => _isSyncingCloud = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      final res = await syncService.syncNow();
      await _loadCloudConfigAndStats();
      if (mounted) {
        if (res.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur synchronisation : ${res.error}'),
              backgroundColor: AppDesignTokens.danger,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Synchronisation réussie : ${res.pushed} élément(s) envoyé(s), ${res.pulled} article(s) mis à jour.',
              ),
              backgroundColor: AppDesignTokens.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur synchronisation : $e'),
            backgroundColor: AppDesignTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingCloud = false);
    }
  }

  Future<void> _loadBackups() async {
    try {
      final db = ref.read(databaseProvider);
      final backups = await (db.select(db.backupRecords)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();
      if (mounted) setState(() => _backups = backups);
    } catch (e) {
      PosLogger.instance.warning('Settings', 'Could not load backup history: $e');
    }
  }

  /// Returns null if cancelled, '' for an unencrypted backup, else the passphrase.
  Future<String?> _askBackupPassphrase() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiffrer la sauvegarde ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La sauvegarde contient les ventes, clients et codes PIN. '
              'Saisissez un mot de passe (8 caractères min.) pour la chiffrer. '
              'Il n’est enregistré nulle part : s’il est perdu, la sauvegarde '
              'est irrécupérable. Laissez vide pour ne pas chiffrer.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    final passphrase = await _askBackupPassphrase();
    if (passphrase == null) return;
    setState(() => _isBackingUp = true);
    try {
      final backupService = ref.read(backupServiceProvider);
      await backupService.createLocalBackup(passphrase: passphrase);
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
      final csv = await ref.read(importExportServiceProvider).exportCatalogCsv();
      final date = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final location = await getSaveLocation(
        suggestedName: 'catalogue_trace_pos_$date.csv',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Fichiers CSV', extensions: ['csv']),
        ],
      );

      if (location != null) {
        final file = File(location.path);
        await file.writeAsBytes(utf8.encode(csv));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Catalogue exporté avec succès vers ${location.path}'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'exportation: $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importCatalog() async {
    if (_isImporting) return;
    const typeGroup = XTypeGroup(label: 'Fichiers CSV', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _isImporting = true);
    try {
      final bytes = await file.readAsBytes();
      final csvContent = utf8.decode(bytes);
      final preview = await ref.read(importExportServiceProvider).previewCsvImport(csvContent);

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmer l\'importation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Articles trouvés dans le fichier : ${preview.totalRows}'),
              Text('Lignes valides prêtes : ${preview.validRows}'),
              if (preview.invalidRows > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Avertissement : ${preview.invalidRows} erreurs détectées dans le fichier.',
                  style: const TextStyle(color: AppDesignTokens.danger, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppDesignTokens.primary, foregroundColor: Colors.white),
              child: const Text('Importer définitivement'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        final auth = ref.read(authNotifierProvider);
        final db = ref.read(databaseProvider);
        final store = await (db.select(db.stores)..limit(1)).getSingleOrNull();
        final batchId = await ref.read(importExportServiceProvider).commitImport(
              preview: preview,
              fileName: file.name,
              actorId: auth.user?.id ?? 'ADMIN',
              storeId: store?.id ?? 'STORE-01',
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Importation réussie : ${preview.validRows} articles importés (Lot: $batchId).'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur importation : $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 0: Cloud Synchronization (Supabase) ──
          _buildCloudSyncSection(),
          const SizedBox(height: 28),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 20),

          // ── Section 1: Backups & Database Integrity ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.backupDatabase,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sauvegarde SQLite atomique avec VACUUM INTO garantissant zéro corruption',
                    style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _createBackup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignTokens.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: _isBackingUp
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.backup),
                label: Text(_isBackingUp ? context.loc.processing : context.loc.backupDatabase),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.databaseIntegrity,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
                  ),
                  const Text(
                    'PRAGMA integrity_check & foreign_key_check',
                    style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                ),
                icon: _isRunningDiagnostics
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                  color: _integrityReport!.isHealthy ? AppDesignTokens.success : AppDesignTokens.danger,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _integrityReport!.isHealthy ? Icons.check_circle : Icons.error,
                        color: _integrityReport!.isHealthy ? AppDesignTokens.success : AppDesignTokens.danger,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _integrityReport!.isHealthy ? context.loc.diagnosticsPass : 'Anomalies détectées dans la base de données',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _integrityReport!.isHealthy ? AppDesignTokens.successText : AppDesignTokens.dangerText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ventes : ${_integrityReport!.totalSales} | Articles : ${_integrityReport!.totalProducts} | Variantes : ${_integrityReport!.totalVariants} | Mouvements : ${_integrityReport!.totalMovements} | Erreurs : ${_integrityReport!.issues.length} | Avertissements : ${_integrityReport!.warnings.length}',
                    style: const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 20),

          // ── Section 2: CSV Import / Export ──
          const Text(
            'Importation et Exportation du Catalogue (CSV)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Format standard UTF-8 avec séparateur point-virgule (;). Compatible Excel et LibreOffice.',
            style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.download, size: 32, color: AppDesignTokens.primary),
                      const SizedBox(height: 10),
                      Text(
                        context.loc.exportCsv,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppDesignTokens.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Exporte l\'intégralité des articles, variantes, prix, stocks et codes-barres vers un fichier CSV.',
                        style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportCatalog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppDesignTokens.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                          ),
                          icon: _isExporting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.file_download, size: 18),
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
                      const Icon(Icons.upload, size: 32, color: AppDesignTokens.success),
                      const SizedBox(height: 10),
                      Text(
                        context.loc.importCsv,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppDesignTokens.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Importe de nouveaux articles en lot avec aperçu et validation transactionnelle des doublons.',
                        style: TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importCatalog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppDesignTokens.success,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                          ),
                          icon: _isImporting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.file_upload, size: 18),
                          label: Text(context.loc.importCsv),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: AppDesignTokens.border),
          const SizedBox(height: 20),

          // ── Section 3: Backup History ──
          const Text(
            'Historique des Sauvegardes Locales :',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary),
          ),
          const SizedBox(height: 12),

          if (_backups.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucune sauvegarde enregistrée pour le moment', style: TextStyle(color: AppDesignTokens.textSecondary)),
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
                    borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                    border: Border.all(color: AppDesignTokens.border),
                    boxShadow: AppDesignTokens.shadowSm,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.archive, color: AppDesignTokens.primary),
                    title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppDesignTokens.textPrimary)),
                    subtitle: Text(
                      'Créée le : ${DateFormat('dd/MM/yyyy HH:mm:ss').format(b.createdAt)} | Taille : ${(b.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                      style: const TextStyle(color: AppDesignTokens.textSecondary, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'VALIDE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppDesignTokens.successText),
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

  Widget _buildCloudSyncSection() {
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
                child: const Icon(Icons.cloud_sync, color: AppDesignTokens.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Synchronisation Cloud (Supabase)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppDesignTokens.textPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Synchronisation bidirectionnelle : La caisse gère le stock et les ventes, le cloud gère le catalogue et les prix.',
                      style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _cloudSyncEnabled,
                activeThumbColor: AppDesignTokens.primary,
                onChanged: (val) {
                  setState(() => _cloudSyncEnabled = val);
                  _saveCloudConfig();
                },
              ),
            ],
          ),
          if (_cloudSyncEnabled) ...[
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _supabaseUrlController,
                    decoration: InputDecoration(
                      labelText: 'URL du projet Supabase',
                      hintText: 'https://xyzcompany.supabase.co',
                      prefixIcon: const Icon(Icons.cloud_outlined, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _supabaseKeyController,
                    obscureText: _isObscureKey,
                    decoration: InputDecoration(
                      labelText: 'Clé API Supabase (Anon / Service)',
                      prefixIcon: const Icon(Icons.key, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_isObscureKey ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setState(() => _isObscureKey = !_isObscureKey),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Diagnostic Metrics Row
            Row(
              children: [
                _buildSyncMetric(
                  label: 'En attente',
                  value: '$_pendingOutbox',
                  color: _pendingOutbox > 0 ? AppDesignTokens.warningText : AppDesignTokens.textSecondary,
                  icon: Icons.hourglass_top,
                ),
                const SizedBox(width: 12),
                _buildSyncMetric(
                  label: 'Synchronisés',
                  value: '$_syncedOutbox',
                  color: AppDesignTokens.success,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 12),
                _buildSyncMetric(
                  label: 'Échecs',
                  value: '$_failedOutbox',
                  color: _failedOutbox > 0 ? AppDesignTokens.danger : AppDesignTokens.textSecondary,
                  icon: Icons.error_outline,
                ),
                const SizedBox(width: 12),
                _buildSyncMetric(
                  label: 'Dernière synchro',
                  value: _lastSyncAt != null ? DateFormat('HH:mm:ss').format(_lastSyncAt!) : 'Jamais',
                  color: AppDesignTokens.primary,
                  icon: Icons.access_time,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isSavingCloud ? null : _saveCloudConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppDesignTokens.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                  ),
                  icon: _isSavingCloud
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Enregistrer la configuration'),
                ),
                OutlinedButton.icon(
                  onPressed: _isTestingCloud ? null : _testCloudConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppDesignTokens.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    side: const BorderSide(color: AppDesignTokens.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                  ),
                  icon: _isTestingCloud
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 18),
                  label: const Text('Tester la connexion'),
                ),
                ElevatedButton.icon(
                  onPressed: _isSyncingCloud ? null : _triggerCloudSyncNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
                  ),
                  icon: _isSyncingCloud
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 18),
                  label: const Text('Synchroniser maintenant'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSyncMetric({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
          border: Border.all(color: AppDesignTokens.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
