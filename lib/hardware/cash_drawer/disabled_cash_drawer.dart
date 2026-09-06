import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'cash_drawer_interface.dart';

/// Disabled cash drawer (used in Zero-Hardware mode or manual key drawer setups).
class DisabledCashDrawer implements CashDrawer {
  @override
  final String name = 'Tiroir-caisse désactivé (Manuel)';

  @override
  final CashDrawerMode mode = CashDrawerMode.disabled;

  @override
  final HardwareStatus status = HardwareStatus.notConfigured;

  @override
  final bool isTested = false;

  const DisabledCashDrawer();

  @override
  Future<void> openDrawer() async {
    PosLogger.instance.info(
      'CashDrawer',
      'Cash drawer is disabled. Manual operation required.',
    );
  }
}
