import 'dart:typed_data';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';

abstract class ReceiptPrinter {
  String get name;
  String get connectionType; // WINDOWS_SPOOLER, USB, SERIAL, NETWORK, SIMULATED

  PrinterProfile get profile => PrinterProfile.genericWindows;
  HardwareStatus get status => HardwareStatus.notConfigured;
  HardwareFingerprint? get fingerprint => null;

  Future<bool> connect();
  Future<bool> isConnected();
  Future<void> printReceipt(ReceiptDocument document);
  Future<void> printRaw(Uint8List bytes) async {}
  Future<void> openCashDrawer();
  Future<void> cutPaper();
  Future<void> disconnect();
}
