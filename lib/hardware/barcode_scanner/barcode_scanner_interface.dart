abstract class BarcodeScanner {
  String get name;
  Stream<String> get onScan;

  Future<void> startListening();
  Future<void> stopListening();
}
