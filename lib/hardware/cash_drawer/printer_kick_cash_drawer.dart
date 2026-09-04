import '../receipt_printer/receipt_printer_interface.dart';
import 'cash_drawer_interface.dart';

/// Cash drawer triggered via RJ11/RJ12 connector on receipt printer
class PrinterKickCashDrawer implements CashDrawer {
  @override
  final String name;
  final ReceiptPrinter printer;

  PrinterKickCashDrawer({
    this.name = 'Printer-Connected Cash Drawer',
    required this.printer,
  });

  @override
  Future<void> openDrawer() async {
    await printer.openCashDrawer();
  }
}
