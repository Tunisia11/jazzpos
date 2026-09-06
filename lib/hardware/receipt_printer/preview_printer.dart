import 'dart:async';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_layout_builder.dart';
import 'receipt_printer_interface.dart';

/// Preview / In-Memory Printer Transport used for Zero-Hardware Mode and demos.
/// Retains printed receipts in memory and emits events for on-screen display.
class PreviewPrinter implements ReceiptPrinter {
  @override
  final String name;

  @override
  final String connectionType = 'SIMULATED';

  @override
  final PrinterProfile profile;

  @override
  HardwareStatus status = HardwareStatus.simulated;

  final List<ReceiptDocument> printedDocuments = [];
  final List<Uint8List> rawPrintJobs = [];

  final _receiptStreamController =
      StreamController<ReceiptDocument>.broadcast();
  Stream<ReceiptDocument> get onReceiptPrinted =>
      _receiptStreamController.stream;

  PreviewPrinter({
    this.name = 'Aperçu Écran Uniquement (Sans Imprimante)',
    this.profile = PrinterProfile.genericEscPos80,
  });

  @override
  HardwareFingerprint get fingerprint => const HardwareFingerprint(
    transport: 'SIMULATED',
    friendlyName: 'Zero-Hardware Preview Printer',
  );

  @override
  Future<bool> connect() async {
    status = HardwareStatus.simulated;
    return true;
  }

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> printReceipt(ReceiptDocument document) async {
    printedDocuments.add(document);
    final rawBytes = ReceiptLayoutBuilder.buildEscPosBytes(
      document,
      profile: profile,
    );
    rawPrintJobs.add(rawBytes);
    _receiptStreamController.add(document);

    PosLogger.instance.info(
      'PreviewPrinter',
      '[Zero-Hardware Mode] Receipt #${document.receiptNumber} stored for on-screen preview.',
    );
  }

  @override
  Future<void> printRaw(Uint8List bytes) async {
    rawPrintJobs.add(bytes);
    PosLogger.instance.info(
      'PreviewPrinter',
      '[Zero-Hardware Mode] Raw ${bytes.length} bytes captured in memory.',
    );
  }

  @override
  Future<void> openCashDrawer() async {
    PosLogger.instance.info(
      'PreviewPrinter',
      '[Zero-Hardware Mode] Cash drawer action simulated (no physical drawer connected).',
    );
  }

  @override
  Future<void> cutPaper() async {
    PosLogger.instance.info(
      'PreviewPrinter',
      '[Zero-Hardware Mode] Paper cut command simulated.',
    );
  }

  @override
  Future<void> disconnect() async {
    status = HardwareStatus.simulated;
  }
}
