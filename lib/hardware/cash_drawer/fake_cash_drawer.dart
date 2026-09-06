import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'cash_drawer_interface.dart';

class FakeCashDrawer implements CashDrawer {
  @override
  final String name;
  @override
  final CashDrawerMode mode = CashDrawerMode.throughPrinter;
  @override
  final HardwareStatus status = HardwareStatus.simulated;
  @override
  bool isTested = true;
  int openCount = 0;

  FakeCashDrawer({this.name = 'Simulated Cash Drawer'});

  @override
  Future<void> openDrawer() async {
    openCount++;
    PosLogger.instance.info(
      'CashDrawer',
      'Cash drawer popped open (Simulated)',
    );
  }
}
