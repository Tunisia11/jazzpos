import 'package:jazzpos/core/money/money.dart';

abstract class CustomerDisplay {
  String get name;
  Future<void> showWelcome();
  Future<void> showItem({
    required String productName,
    required Money price,
    required Money total,
  });
  Future<void> showTotal({required Money total, required Money change});
  Future<void> clear();
}
