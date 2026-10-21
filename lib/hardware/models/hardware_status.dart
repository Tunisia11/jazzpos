import 'package:flutter/material.dart';

/// Peripheral hardware status lifecycle states.
enum HardwareStatus {
  notConfigured('NOT_CONFIGURED'),
  scanning('SCANNING'),
  detected('DETECTED'),
  configured('CONFIGURED'),
  connecting('CONNECTING'),
  unknown('UNKNOWN'),
  paused('PAUSED'),
  missing('MISSING'),
  queueExists('QUEUE_EXISTS'),
  ready('READY'),
  offline('OFFLINE'),
  error('ERROR'),
  simulated('SIMULATED'),
  unsupported('UNSUPPORTED');

  final String value;
  const HardwareStatus(this.value);

  static HardwareStatus fromString(String? val) {
    if (val == null) return HardwareStatus.notConfigured;
    return HardwareStatus.values.firstWhere(
      (s) => s.value.toUpperCase() == val.toUpperCase(),
      orElse: () => HardwareStatus.notConfigured,
    );
  }

  bool get isReady => this == HardwareStatus.ready;
  bool get isSimulated => this == HardwareStatus.simulated;
  bool get isOperational => isReady || isSimulated;
  bool get isOffline => this == HardwareStatus.offline;
  bool get hasError => this == HardwareStatus.error;

  String get labelFr {
    switch (this) {
      case HardwareStatus.unknown:
        return 'État inconnu';
      case HardwareStatus.paused:
        return 'File en pause';
      case HardwareStatus.missing:
        return 'File absente';
      case HardwareStatus.queueExists:
        return 'File présente (état physique inconnu)';
      case HardwareStatus.notConfigured:
        return 'Non configuré';
      case HardwareStatus.scanning:
        return 'Détection en cours...';
      case HardwareStatus.detected:
        return 'Détecté';
      case HardwareStatus.configured:
        return 'Configuré';
      case HardwareStatus.connecting:
        return 'Connexion...';
      case HardwareStatus.ready:
        return 'Prêt selon Windows';
      case HardwareStatus.offline:
        return 'Hors ligne';
      case HardwareStatus.error:
        return 'Erreur matériel';
      case HardwareStatus.simulated:
        return 'Simulé (Logiciel)';
      case HardwareStatus.unsupported:
        return 'Non supporté';
    }
  }

  Color get color {
    switch (this) {
      case HardwareStatus.ready:
        return const Color(0xFF16A34A); // Green
      case HardwareStatus.detected:
      case HardwareStatus.configured:
        return const Color(0xFF2563EB); // Blue
      case HardwareStatus.unknown:
      case HardwareStatus.paused:
      case HardwareStatus.queueExists:
      case HardwareStatus.connecting:
      case HardwareStatus.scanning:
        return const Color(0xFFD97706); // Amber
      case HardwareStatus.simulated:
        return const Color(0xFF9333EA); // Purple
      case HardwareStatus.missing:
      case HardwareStatus.offline:
      case HardwareStatus.unsupported:
        return const Color(0xFF64748B); // Slate
      case HardwareStatus.error:
        return const Color(0xFFDC2626); // Red
      case HardwareStatus.notConfigured:
        return const Color(0xFF94A3B8); // Light slate
    }
  }
}
