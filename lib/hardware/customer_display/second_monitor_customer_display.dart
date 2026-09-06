import 'dart:async';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'customer_display_interface.dart';

class CustomerDisplayItemEvent {
  final String productName;
  final Money price;
  final Money total;
  final DateTime timestamp;

  const CustomerDisplayItemEvent({
    required this.productName,
    required this.price,
    required this.total,
    required this.timestamp,
  });
}

class CustomerDisplayTotalEvent {
  final Money total;
  final Money change;
  final DateTime timestamp;

  const CustomerDisplayTotalEvent({
    required this.total,
    required this.change,
    required this.timestamp,
  });
}

/// Second Monitor Customer Display:
/// Broadcasts current item and sale totals to auxiliary customer screens.
class SecondMonitorCustomerDisplay implements CustomerDisplay {
  @override
  final String name;

  final int displayIndex;
  final int width;
  final int height;

  @override
  final CustomerDisplayMode mode = CustomerDisplayMode.secondMonitor;

  @override
  HardwareStatus status = HardwareStatus.ready;

  final _itemController =
      StreamController<CustomerDisplayItemEvent>.broadcast();
  final _totalController =
      StreamController<CustomerDisplayTotalEvent>.broadcast();
  final _welcomeController = StreamController<void>.broadcast();
  final _clearController = StreamController<void>.broadcast();

  Stream<CustomerDisplayItemEvent> get onItem => _itemController.stream;
  Stream<CustomerDisplayTotalEvent> get onTotal => _totalController.stream;
  Stream<void> get onWelcome => _welcomeController.stream;
  Stream<void> get onClear => _clearController.stream;

  SecondMonitorCustomerDisplay({
    this.name = 'Écran Client Secondaire (HDMI / VGA)',
    this.displayIndex = 1,
    this.width = 1920,
    this.height = 1080,
  });

  @override
  Future<void> showWelcome() async {
    _welcomeController.add(null);
    PosLogger.instance.info(
      'CustomerDisplay',
      'Welcome message shown on second monitor',
    );
  }

  @override
  Future<void> showItem({
    required String productName,
    required Money price,
    required Money total,
  }) async {
    _itemController.add(
      CustomerDisplayItemEvent(
        productName: productName,
        price: price,
        total: total,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> showTotal({required Money total, required Money change}) async {
    _totalController.add(
      CustomerDisplayTotalEvent(
        total: total,
        change: change,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> clear() async {
    _clearController.add(null);
  }
}
