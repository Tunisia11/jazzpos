import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/logging/startup_tracker.dart';
import 'package:jazzpos/core/platform/app_paths.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

enum StartupStatus {
  initializing,
  ready,
  recoverableError,
  fatalError,
}

/// Production recovery screen displayed if startup fails or times out.
/// Eliminates infinite spinners and provides non-destructive recovery actions.
class StartupRecoveryWidget extends StatelessWidget {
  final String title;
  final String? errorMessage;
  final String? technicalDetails;
  final VoidCallback onRetry;
  final VoidCallback? onClose;

  const StartupRecoveryWidget({
    super.key,
    this.title = "Trace POS n'a pas pu terminer le démarrage.",
    this.errorMessage,
    this.technicalDetails,
    required this.onRetry,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final dbPath = AppPaths.instance.isInitialized
        ? AppPaths.instance.databaseFilePath
        : 'Non initialisé';
    final dataDir = AppPaths.instance.isInitialized
        ? AppPaths.instance.baseDir.path
        : 'Non initialisé';
    final displayError = errorMessage ??
        'Le chargement des données a dépassé le délai autorisé ou a rencontré un format inattendu.';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Icon & Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFDC2626),
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Vos données de caisse sont préservées en toute sécurité.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Diagnostic Details Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                            Icons.storage_rounded,
                            'Database:',
                            dbPath,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            Icons.folder_open_rounded,
                            'Data folder:',
                            dataDir,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            Icons.info_outline_rounded,
                            'Error:',
                            displayError,
                            isError: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Action Buttons (Required by Spec)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      children: [
                        // [ Fermer ]
                        OutlinedButton.icon(
                          onPressed: () {
                            if (onClose != null) {
                              onClose!();
                            } else {
                              exit(0);
                            }
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Fermer'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),

                        // [ Ouvrir le dossier de données ]
                        OutlinedButton.icon(
                          onPressed: () => _openDataFolder(dataDir),
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Ouvrir le dossier de données'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side: const BorderSide(color: Color(0xFF94A3B8)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),

                        // [ Diagnostic ]
                        OutlinedButton.icon(
                          onPressed: () => _showDiagnosticDialog(context),
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: const Text('Diagnostic'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppDesignTokens.primary,
                            side: const BorderSide(color: AppDesignTokens.primary),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),

                        // [ Réessayer ]
                        ElevatedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Réessayer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppDesignTokens.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    bool isError = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: isError ? const Color(0xFFDC2626) : const Color(0xFF64748B),
        ),
        const SizedBox(width: 8),
        Text(
          label.padRight(13),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Consolas',
              color: isError ? const Color(0xFFB91C1C) : const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  void _openDataFolder(String path) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        Process.run('open', [path]);
      } else {
        Process.run('xdg-open', [path]);
      }
    } catch (e) {
      PosLogger.instance.warning('Startup', 'Failed to open data folder: $e');
    }
  }

  void _showDiagnosticDialog(BuildContext context) {
    final summary = StartupTracker.instance.getDiagnosticSummary();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.monitor_heart_outlined, color: AppDesignTokens.primary),
            SizedBox(width: 10),
            Text('Diagnostic Système & Démarrage'),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Journal des étapes de démarrage :',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    summary.isNotEmpty ? summary : 'Aucune étape enregistrée.',
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                if (technicalDetails != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Détails techniques :',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: SelectableText(
                      technicalDetails!,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}