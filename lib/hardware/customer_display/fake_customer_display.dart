import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'customer_display_interface.dart';

class FakeCustomerDisplay implements CustomerDisplay {
  @override
  final String name;

  String line1 = 'WELCOME TO JAZZ';
  String line2 = 'READY';

  FakeCustomerDisplay({this.name = 'Simulated 2x20 VFD Customer Display'});

  @override
  Future<void> showWelcome() async {
    line1 = 'WELCOME TO JAZZ';
    line2 = 'READY';
    PosLogger.instance.info('CustomerDisplay', 'Display: "$line1" | "$line2"');
  }

  @override
  Future<void> showItem({required String productName, required Money price, required Money total}) async {
    line1 = productName.length > 20 ? productName.substring(0, 20) : productName;
    line2 = '${price.format()} | Tot: ${total.format()}';
    PosLogger.instance.info('CustomerDisplay', 'Display: "$line1" | "$line2"');
  }

  @override
  Future<void> showTotal({required Money total, required Money change}) async {
    line1 = 'TOTAL: ${total.format()}';
    line2 = change > Money.zero ? 'CHANGE: ${change.format()}' : 'THANK YOU!';
    PosLogger.instance.info('CustomerDisplay', 'Display: "$line1" | "$line2"');
  }

  @override
  Future<void> clear() async {
    line1 = '';
    line2 = '';
  }
}
