import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'customer_display_interface.dart';

/// Disabled customer display (used when terminal has no customer-facing display).
class DisabledCustomerDisplay implements CustomerDisplay {
  @override
  final String name = 'Afficheur client désactivé';

  @override
  final CustomerDisplayMode mode = CustomerDisplayMode.disabled;

  @override
  final HardwareStatus status = HardwareStatus.notConfigured;

  const DisabledCustomerDisplay();

  @override
  Future<void> showWelcome() async {}

  @override
  Future<void> showItem({
    required String productName,
    required Money price,
    required Money total,
  }) async {}

  @override
  Future<void> showTotal({required Money total, required Money change}) async {}

  @override
  Future<void> clear() async {}
}
