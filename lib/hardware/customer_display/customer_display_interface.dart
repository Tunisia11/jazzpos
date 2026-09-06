import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';

enum CustomerDisplayMode {
  disabled('DISABLED'),
  secondMonitor('SECOND_MONITOR'),
  serial('SERIAL'),
  custom('CUSTOM');

  final String value;
  const CustomerDisplayMode(this.value);

  static CustomerDisplayMode fromString(String? val) {
    if (val == null) return CustomerDisplayMode.disabled;
    return CustomerDisplayMode.values.firstWhere(
      (m) => m.value.toUpperCase() == val.toUpperCase(),
      orElse: () => CustomerDisplayMode.disabled,
    );
  }

  String get labelFr {
    switch (this) {
      case CustomerDisplayMode.disabled:
        return 'Désactivé';
      case CustomerDisplayMode.secondMonitor:
        return 'Écran Secondaire';
      case CustomerDisplayMode.serial:
        return 'Afficheur Série (COM)';
      case CustomerDisplayMode.custom:
        return 'Personnalisé';
    }
  }
}

abstract class CustomerDisplay {
  String get name;
  CustomerDisplayMode get mode => CustomerDisplayMode.disabled;
  HardwareStatus get status => HardwareStatus.notConfigured;

  Future<void> showWelcome();
  Future<void> showItem({
    required String productName,
    required Money price,
    required Money total,
  });
  Future<void> showTotal({required Money total, required Money change});
  Future<void> clear();
}
