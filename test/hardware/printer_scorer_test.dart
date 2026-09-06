import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_candidate.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_scorer.dart';

void main() {
  group('PrinterScorer Candidate Evaluation', () {
    test(
      'disqualifies virtual and non-POS printers with score 0 and excluded confidence',
      () {
        final virtualPrinters = [
          (
            name: 'Microsoft Print to PDF',
            driver: 'Microsoft Print To PDF',
            port: 'PORTPROMPT:',
          ),
          (
            name: 'Microsoft XPS Document Writer',
            driver: 'Microsoft XPS Document Writer v4',
            port: 'PORTPROMPT:',
          ),
          (
            name: 'OneNote (Desktop)',
            driver: 'Send to Microsoft OneNote 16 Driver',
            port: 'nul:',
          ),
          (name: 'Fax', driver: 'Microsoft Shared Fax Driver', port: 'SHRFAX:'),
          (
            name: 'Foxit PDF Editor Printer',
            driver: 'Foxit PDF Editor Printer Driver',
            port: 'Foxit Port:',
          ),
        ];

        for (final printer in virtualPrinters) {
          final evaluated = PrinterScorer.evaluate(
            name: printer.name,
            driverName: printer.driver,
            portName: printer.port,
          );
          expect(
            evaluated.score,
            0,
            reason: 'Printer ${printer.name} should have score 0',
          );
          expect(evaluated.confidence, equals(PrinterConfidence.excluded));
          expect(PrinterScorer.isVirtualPrinter(printer.name), isTrue);
        }
      },
    );

    test('awards high score to POS brand thermal printers', () {
      final posPrinters = [
        (
          name: 'POSBANK A7 Receipt Printer',
          driver: 'POSBANK A7',
          port: 'USB001',
          isDefault: true,
        ),
        (
          name: 'EPSON TM-T20III Receipt',
          driver: 'EPSON TM-T20III',
          port: 'ESDPRT001',
          isDefault: false,
        ),
        (
          name: 'BIXOLON SRP-350plusIII',
          driver: 'BIXOLON SRP-350plusIII',
          port: 'USB002',
          isDefault: false,
        ),
        (
          name: 'Citizen CT-S310II Thermal Receipt',
          driver: 'Citizen CT-S310II',
          port: 'COM3',
          isDefault: false,
        ),
      ];

      for (final printer in posPrinters) {
        final evaluated = PrinterScorer.evaluate(
          name: printer.name,
          driverName: printer.driver,
          portName: printer.port,
          isDefault: printer.isDefault,
        );
        expect(
          evaluated.score,
          greaterThanOrEqualTo(70),
          reason: '${printer.name} should score >= 70, got ${evaluated.score}',
        );
        expect(evaluated.isReceiptPrinterCandidate, isTrue);
      }
    });

    test(
      'default POS printer scores higher than non-default identical printer',
      () {
        final defaultPrinter = PrinterScorer.evaluate(
          name: 'POS-80 Series',
          driverName: 'POS-80',
          portName: 'USB001',
          isDefault: true,
        );
        final nonDefaultPrinter = PrinterScorer.evaluate(
          name: 'POS-80 Series',
          driverName: 'POS-80',
          portName: 'USB001',
          isDefault: false,
        );

        expect(defaultPrinter.score, greaterThan(nonDefaultPrinter.score));
        expect(defaultPrinter.score - nonDefaultPrinter.score, equals(10));
      },
    );

    test('online state yields higher score than paused state', () {
      final onlinePrinter = PrinterScorer.evaluate(
        name: 'POS Thermal Printer',
        driverName: 'Generic / Text Only',
        portName: 'USB001',
        isOnline: true,
        isPaused: false,
      );
      final pausedPrinter = PrinterScorer.evaluate(
        name: 'POS Thermal Printer',
        driverName: 'Generic / Text Only',
        portName: 'USB001',
        isOnline: true,
        isPaused: true,
      );

      expect(onlinePrinter.score, greaterThan(pausedPrinter.score));
      expect(onlinePrinter.score - pausedPrinter.score, equals(10));
    });

    test('sorts candidate list in descending score order', () {
      final candidates = [
        PrinterScorer.evaluate(
          name: 'Microsoft Print to PDF',
          driverName: 'Microsoft Print To PDF',
          portName: 'PORTPROMPT:',
        ),
        PrinterScorer.evaluate(
          name: 'Generic Text Only',
          driverName: 'Generic / Text Only',
          portName: 'LPT1',
        ),
        PrinterScorer.evaluate(
          name: 'POSBANK Apexa Printer',
          driverName: 'POSBANK Apexa',
          portName: 'USB001',
          isDefault: true,
        ),
        PrinterScorer.evaluate(
          name: 'EPSON TM-T88VI',
          driverName: 'EPSON TM-T88VI',
          portName: 'USB002',
          isDefault: false,
        ),
      ];

      final ranked = PrinterScorer.rankCandidates(candidates);

      expect(ranked.first.name, equals('POSBANK Apexa Printer'));
      expect(ranked.last.name, equals('Microsoft Print to PDF'));
      expect(ranked.last.score, equals(0));
    });
  });
}
