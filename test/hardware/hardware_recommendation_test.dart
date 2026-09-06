import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_profile.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_scorer.dart';
import 'package:jazzpos/hardware/services/hardware_discovery_service.dart';
import 'package:jazzpos/hardware/services/hardware_recommendation_engine.dart';

void main() {
  group('HardwareRecommendationEngine', () {
    test(
      'generates HIGH confidence recommendation for top POS printer and drawer',
      () {
        final discovery = HardwareDiscoveryReport(
          timestamp: DateTime.now(),
          printers: [
            PrinterScorer.evaluate(
              name: 'POSBANK Apexa Printer',
              driverName: 'POSBANK Apexa',
              portName: 'USB001',
              isDefault: true,
            ),
            PrinterScorer.evaluate(
              name: 'Microsoft Print to PDF',
              driverName: 'Microsoft Print To PDF',
              portName: 'PORTPROMPT:',
            ),
          ],
          usbDevices: const [],
          serialPorts: const [],
          displays: const [
            DiscoveredDisplay(
              id: 1,
              width: 1024,
              height: 768,
              dpiScale: 1.0,
              isPrimary: true,
            ),
            DiscoveredDisplay(
              id: 2,
              width: 800,
              height: 600,
              dpiScale: 1.0,
              isPrimary: false,
            ),
          ],
        );

        final recs = HardwareRecommendationEngine.generateRecommendations(
          discovery,
        );

        // Printer
        expect(recs.receiptPrinter, isNotNull);
        expect(
          recs.receiptPrinter!.recommendedName,
          equals('POSBANK Apexa Printer'),
        );
        expect(recs.receiptPrinter!.transport, equals('WINDOWS_SPOOLER'));
        expect(
          recs.receiptPrinter!.confidence,
          equals(RecommendationConfidence.high),
        );
        expect(
          recs.receiptPrinter!.printerProfile,
          equals(PrinterProfile.posbank),
        );

        // Barcode Scanner
        expect(
          recs.barcodeScanner.confidence,
          equals(RecommendationConfidence.high),
        );
        expect(recs.barcodeScanner.transport, equals('KEYBOARD_WEDGE'));

        // Cash Drawer
        expect(recs.cashDrawer.transport, equals('THROUGH_PRINTER'));
        expect(
          recs.cashDrawer.confidence,
          equals(RecommendationConfidence.medium),
        );

        // Customer Display
        expect(recs.customerDisplay.transport, equals('SECOND_MONITOR'));
        expect(
          recs.customerDisplay.confidence,
          equals(RecommendationConfidence.high),
        );
      },
    );

    test('recommends EPSON profile when TM-T printer detected', () {
      final discovery = HardwareDiscoveryReport(
        timestamp: DateTime.now(),
        printers: [
          PrinterScorer.evaluate(
            name: 'EPSON TM-T20II Receipt',
            driverName: 'EPSON TM-T20II',
            portName: 'ESDPRT001',
            isDefault: true,
          ),
        ],
        usbDevices: const [],
        serialPorts: const [],
        displays: const [
          DiscoveredDisplay(
            id: 1,
            width: 1366,
            height: 768,
            dpiScale: 1.0,
            isPrimary: true,
          ),
        ],
      );

      final recs = HardwareRecommendationEngine.generateRecommendations(
        discovery,
      );
      expect(
        recs.receiptPrinter?.printerProfile,
        equals(PrinterProfile.epsonEscPos),
      );
      expect(recs.customerDisplay.transport, equals('DISABLED'));
      expect(
        recs.customerDisplay.confidence,
        equals(RecommendationConfidence.low),
      );
    });

    test('falls back gracefully when no physical POS printers are found', () {
      final discovery = HardwareDiscoveryReport(
        timestamp: DateTime.now(),
        printers: [
          PrinterScorer.evaluate(
            name: 'Microsoft Print to PDF',
            driverName: 'Microsoft Print To PDF',
            portName: 'PORTPROMPT:',
          ),
          PrinterScorer.evaluate(
            name: 'Fax',
            driverName: 'Microsoft Shared Fax Driver',
            portName: 'SHRFAX:',
          ),
        ],
        usbDevices: const [],
        serialPorts: const [],
        displays: const [
          DiscoveredDisplay(
            id: 1,
            width: 1920,
            height: 1080,
            dpiScale: 1.0,
            isPrimary: true,
          ),
        ],
      );

      final recs = HardwareRecommendationEngine.generateRecommendations(
        discovery,
      );

      expect(recs.receiptPrinter, isNull);
      expect(recs.cashDrawer.transport, equals('DISABLED'));
      expect(recs.customerDisplay.transport, equals('DISABLED'));
    });
  });
}
