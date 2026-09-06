import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jazzpos/core/platform/environment_diagnostics_service.dart';

/// Screen displayed when JAZZ POS detects an unsupported or legacy operating system
/// (e.g., Windows 7, Windows 8, 32-bit x86). Prevents data corruption.
class UnsupportedOsScreen extends StatelessWidget {
  final EnvironmentDiagnosticReport report;
  final VoidCallback onProceedAnyway;

  const UnsupportedOsScreen({
    super.key,
    required this.report,
    required this.onProceedAnyway,
  });

  @override
  Widget build(BuildContext context) {
    final warningMsg =
        report.compatibilityWarning ??
        'JAZZ POS detected an unsupported operating system (${report.osEdition} ${report.architecture}). '
            'This version of Windows is outside the supported runtime target for this JAZZ POS build. '
            'Do not modify or delete your database. Use a compatible JAZZ POS legacy build or upgrade Windows.';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate
      body: Center(
        child: Container(
          width: 640,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDC2626), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFEF4444),
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Système d\'exploitation non supporté',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Avertissement de compatibilité Windows',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  warningMsg,
                  style: const TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    _InfoRow('Système détecté :', report.osEdition),
                    _InfoRow('Architecture :', report.architecture),
                    _InfoRow(
                      'Version / Build :',
                      '${report.osVersion} (${report.osBuild})',
                    ),
                    _InfoRow('Base de données :', report.dataDirectory),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => exit(0),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF64748B)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Quitter l\'application'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onProceedAnyway,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Continuer malgré tout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
