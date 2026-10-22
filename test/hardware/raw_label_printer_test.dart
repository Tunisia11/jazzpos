import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/hardware/barcode_scanner/fake_barcode_scanner.dart';
import 'package:tracepos/hardware/hardware_manager.dart';
import 'package:tracepos/hardware/label_printer/label_document.dart';
import 'package:tracepos/hardware/label_printer/raw_label_printer.dart';

const _doc = LabelDocument(
  storeName: 'Trace',
  productName: 'Polo',
  sku: 'POL-1',
  barcode: '200123456789',
  price: Money.fromMillimes(49000),
);

void main() {
  test('sends TSPL bytes through the transport', () async {
    final sent = <Uint8List>[];
    final printer = RawLabelPrinter(
      queueName: 'Zebra',
      transport: LabelTransport.windowsSpooler,
    )..sender = (b) async => sent.add(b);

    await printer.printLabel(_doc);
    await printer.printBatch([_doc, _doc]);

    expect(sent, hasLength(2));
    expect(utf8.decode(sent.first), contains('BARCODE'));
    expect(utf8.decode(sent.last).split('PRINT').length, greaterThan(2));
  });

  test('network transport delivers over TCP', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final data = <int>[];
    final done = <Future<void>>[];
    server.listen((s) => done.add(s.listen(data.addAll).asFuture<void>()));
    final printer = RawLabelPrinter(
      queueName: 'Net',
      transport: LabelTransport.network,
      ipAddress: '127.0.0.1',
      port: server.port,
    );
    expect(await printer.isConnected(), isTrue);
    await printer.printLabel(_doc);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await Future.wait(done);
    expect(utf8.decode(data), contains('200123456789'));
    await server.close();
  });

  test('config is persisted, restored and survives a receipt save', () async {
    final dir = await Directory.systemTemp.createTemp('hw_label_');
    addTearDown(() => dir.delete(recursive: true));

    final hw = HardwareManager.forTesting(configDirectory: dir);
    await hw.saveLabelPrinter(
      'Zebra',
      transport: LabelTransport.network,
      ipAddress: '10.0.0.5',
    );
    expect(hw.labelPrinter, isA<RawLabelPrinter>());
    expect(hw.labelPrinterIsSimulated, isFalse);

    await hw.saveReceiptPrinter('EPSON', transport: 'NETWORK', ipAddress: '10.0.0.6');
    final json = jsonDecode(
      File('${dir.path}/${HardwareManager.kHardwareConfigFile}').readAsStringSync(),
    ) as Map;
    expect(json['labelPrinter']['ipAddress'], '10.0.0.5');

    final fresh = HardwareManager.forTesting(configDirectory: dir)..initialize(customBarcodeScanner: FakeBarcodeScanner());
    expect(fresh.labelPrinter, isA<RawLabelPrinter>());
    expect(fresh.labelPrinter.name, 'Zebra');
  });

  test('rejects an empty name or network without IP', () async {
    final dir = await Directory.systemTemp.createTemp('hw_label2_');
    addTearDown(() => dir.delete(recursive: true));
    final hw = HardwareManager.forTesting(configDirectory: dir);
    expect(() => hw.saveLabelPrinter(' ', transport: LabelTransport.macCups), throwsArgumentError);
    expect(() => hw.saveLabelPrinter('X', transport: LabelTransport.network), throwsArgumentError);
  });
}
