import 'package:jazzpos/hardware/models/hardware_status.dart';

enum CashDrawerMode {
  disabled('DISABLED'),
  throughPrinter('THROUGH_PRINTER'),
  serial('SERIAL'),
  custom('CUSTOM');

  final String value;
  const CashDrawerMode(this.value);

  static CashDrawerMode fromString(String? val) {
    if (val == null) return CashDrawerMode.disabled;
    return CashDrawerMode.values.firstWhere(
      (m) => m.value.toUpperCase() == val.toUpperCase(),
      orElse: () => CashDrawerMode.disabled,
    );
  }

  String get labelFr {
    switch (this) {
      case CashDrawerMode.disabled:
        return 'Désactivé';
      case CashDrawerMode.throughPrinter:
        return 'Via Imprimante (RJ11/12)';
      case CashDrawerMode.serial:
        return 'Port Série (COM)';
      case CashDrawerMode.custom:
        return 'Personnalisé';
    }
  }
}

abstract class CashDrawer {
  String get name;
  CashDrawerMode get mode => CashDrawerMode.disabled;
  HardwareStatus get status => HardwareStatus.notConfigured;
  bool get isTested => false;
  Future<void> openDrawer();
}
