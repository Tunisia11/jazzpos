import 'dart:async';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'barcode_scanner_interface.dart';

class FakeBarcodeScanner implements BarcodeScanner {
  @override
  final String name;

  final _scanController = StreamController<String>.broadcast();

  FakeBarcodeScanner({this.name = 'Simulated USB HID Barcode Scanner'});

  @override
  Stream<String> get onScan => _scanController.stream;

  /// Trigger a programmatic scan event for testing and UI simulation
  void simulateScan(String barcode) {
    PosLogger.instance.info('Scanner', 'Simulated barcode scan: $barcode');
    _scanController.add(barcode.trim());
  }

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}
}
