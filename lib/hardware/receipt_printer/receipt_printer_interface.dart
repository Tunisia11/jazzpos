import 'receipt_document.dart';

abstract class ReceiptPrinter {
  String get name;
  String get connectionType;

  Future<bool> connect();
  Future<bool> isConnected();
  Future<void> printReceipt(ReceiptDocument document);
  Future<void> openCashDrawer();
  Future<void> cutPaper();
  Future<void> disconnect();
}
