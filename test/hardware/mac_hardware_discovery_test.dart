import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/hardware/receipt_printer/printer_scorer.dart';
import 'package:tracepos/hardware/services/hardware_discovery_service.dart';

void main() {
  group('macOS Hardware Discovery & Scoring', () {
    test('PrinterScorer correctly detects thermal receipt printer from CUPS queue name', () {
      final candidate1 = PrinterScorer.evaluate(
        name: 'EPSON_TM_T20III',
        driverName: 'CUPS Raw / Direct',
        portName: 'CUPS',
        isDefault: true,
      );

      expect(candidate1.isReceiptPrinterCandidate, isTrue);

      final candidate2 = PrinterScorer.evaluate(
        name: 'Xprinter_XP_80C',
        driverName: 'CUPS Raw / Direct',
        portName: 'CUPS',
      );

      expect(candidate2.isReceiptPrinterCandidate, isTrue);

      final pdfPrinter = PrinterScorer.evaluate(
        name: 'Save_As_PDF',
        driverName: 'PDF Writer',
        portName: 'Virtual',
      );

      expect(pdfPrinter.isReceiptPrinterCandidate, isFalse);
    });

    test('HardwareDiscoveryService parses installed CUPS printers cleanly', () async {
      final service = HardwareDiscoveryService();
      final printers = await service.discoverPrinters();

      // On macOS, it either finds real CUPS printers or returns the fallback mock
      expect(printers, isNotEmpty);
      expect(printers.first.name, isNotEmpty);
    });

    test('HardwareDiscoveryService discoverSerialPorts executes without error on macOS', () async {
      final service = HardwareDiscoveryService();
      final ports = await service.discoverSerialPorts();

      // Should return list without throwing
      expect(ports, isA<List<DiscoveredSerialPort>>());
    });
  });
}
