import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/common/app_card.dart';
import 'package:tracepos/core/logging/pos_logger.dart';

class OwnerSyncView extends ConsumerStatefulWidget {
  const OwnerSyncView({super.key});

  @override
  ConsumerState<OwnerSyncView> createState() => _OwnerSyncViewState();
}

class _OwnerSyncViewState extends ConsumerState<OwnerSyncView> {
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isTesting = false;
  bool _enabled = false;
  String _url = '';
  int _pending = 0;
  int _synced = 0;
  int _failed = 0;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _loadSyncData();
  }

  Future<void> _loadSyncData() async {
    setState(() => _isLoading = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      final config = await syncService.getCloudConfig();
      final stats = await syncService.getSyncStats();

      if (mounted) {
        setState(() {
          _enabled = config.enabled;
          _url = config.url;
          _pending = stats.pending;
          _synced = stats.synced;
          _failed = stats.failed;
          _lastSyncAt = stats.lastSyncAt;
          _isLoading = false;
        });
      }
    } catch (e) {
      PosLogger.instance.warning('owner_sync_view', 'Ignored error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      final res = await syncService.syncNow();
      await _loadSyncData();
      if (mounted) {
        if (res.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: ${res.error}'),
              backgroundColor: AppDesignTokens.danger,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synchro réussie: ${res.pushed} envoyé(s), ${res.pulled} mis à jour.'),
              backgroundColor: AppDesignTokens.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final sw = Stopwatch()..start();
    try {
      final syncService = ref.read(syncServiceProvider);
      final ok = await syncService.testConnection();
      sw.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Connecté à Supabase (${sw.elapsedMilliseconds} ms)'
                  : 'Échec de la connexion à Supabase.',
            ),
            backgroundColor: ok ? AppDesignTokens.success : AppDesignTokens.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur test: $e'), backgroundColor: AppDesignTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      padding: const EdgeInsets.all(AppDesignTokens.space16),
      children: [
        // Cloud Connection Status Hero Card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_enabled ? AppDesignTokens.success : AppDesignTokens.textMuted).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _enabled ? Icons.cloud_done : Icons.cloud_off,
                      color: _enabled ? AppDesignTokens.success : AppDesignTokens.textMuted,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _enabled ? 'Synchronisation Cloud Active' : 'Synchronisation Cloud Désactivée',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _url.isNotEmpty ? _url : 'Aucun projet Supabase configuré',
                          style: const TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppDesignTokens.border),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Dernière synchronisation :', style: TextStyle(fontSize: 12, color: AppDesignTokens.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _lastSyncAt != null ? DateFormat('dd/MM/yyyy HH:mm:ss').format(_lastSyncAt!) : 'Jamais',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Metrics Grid
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'En attente',
                value: '$_pending',
                icon: Icons.hourglass_empty,
                color: _pending > 0 ? AppDesignTokens.warningText : AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'Synchronisés',
                value: '$_synced',
                icon: Icons.check_circle_outline,
                color: AppDesignTokens.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'Échecs',
                value: '$_failed',
                icon: Icons.error_outline,
                color: _failed > 0 ? AppDesignTokens.danger : AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Action Buttons
        ElevatedButton.icon(
          onPressed: _isSyncing ? null : _triggerSync,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppDesignTokens.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
          ),
          icon: _isSyncing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
          label: Text(_isSyncing ? 'Synchronisation en cours...' : 'Synchroniser maintenant'),
        ),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: _isTesting ? null : _testConnection,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppDesignTokens.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput)),
          ),
          icon: _isTesting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering),
          label: const Text('Tester la connexion Supabase'),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 11, color: AppDesignTokens.textSecondary)),
        ],
      ),
    );
  }
}
