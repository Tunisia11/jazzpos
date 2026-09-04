import 'package:jazzpos/core/logging/pos_logger.dart';
import 'cash_drawer_interface.dart';

class FakeCashDrawer implements CashDrawer {
  @override
  final String name;
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
