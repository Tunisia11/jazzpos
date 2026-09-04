import 'label_document.dart';

abstract class LabelPrinter {
  String get name;
  String get connectionType;

  Future<bool> connect();
  Future<bool> isConnected();
  Future<void> printLabel(LabelDocument document);
  Future<void> printBatch(List<LabelDocument> documents);
  Future<void> disconnect();
}
