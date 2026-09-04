import 'dart:async';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'label_document.dart';
import 'label_printer_interface.dart';
import 'tspl_commands.dart';

class FakeLabelPrinter implements LabelPrinter {
  @override
  final String name;
  @override
  final String connectionType = 'SIMULATED';

  bool _connected = true;
  final List<LabelDocument> printedLabels = [];
  final List<String> rawGeneratedCommands = [];

  final _labelStreamController = StreamController<LabelDocument>.broadcast();
  Stream<LabelDocument> get onLabelPrinted => _labelStreamController.stream;

  FakeLabelPrinter({this.name = 'Simulated TSPL/ZPL Label Printer'});

  @override
  Future<bool> connect() async {
    _connected = true;
    PosLogger.instance.info('LabelPrinter', 'Connected to $name (Fake)');
    return true;
  }

  @override
  Future<bool> isConnected() async => _connected;

  @override
  Future<void> printLabel(LabelDocument doc) async {
    if (!_connected) throw Exception('Label printer $name is not connected');

    final tspl = TsplCommands.buildLabel(doc);
    rawGeneratedCommands.add(tspl);
    printedLabels.add(doc);
    _labelStreamController.add(doc);

    PosLogger.instance.info(
      'LabelPrinter',
      'Printed simulated label: ${doc.productName} (${doc.variantTag}), Barcode: ${doc.barcode}, Copies: ${doc.copies}',
    );
  }

  @override
  Future<void> printBatch(List<LabelDocument> docs) async {
    for (final doc in docs) {
      await printLabel(doc);
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }
}
