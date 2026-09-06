import 'package:jazzpos/hardware/models/hardware_status.dart';
import '../receipt_printer/receipt_printer_interface.dart';
import 'cash_drawer_interface.dart';

/// Cash drawer triggered via RJ11/RJ12 connector on receipt printer
class PrinterKickCashDrawer implements CashDrawer {
  @override
  final String name;

  final ReceiptPrinter printer;

  @override
  final CashDrawerMode mode = CashDrawerMode.throughPrinter;

  bool _isTested = false;

  @override
  bool get isTested => _isTested;

  @override
  HardwareStatus get status =>
      _isTested ? HardwareStatus.ready : HardwareStatus.configured;

  PrinterKickCashDrawer({
    this.name = 'Tiroir connecté à l\'imprimante (RJ11/RJ12)',
    required this.printer,
  });

  @override
  Future<void> openDrawer() async {
    await printer.openCashDrawer();
    _isTested = true;
  }
}
