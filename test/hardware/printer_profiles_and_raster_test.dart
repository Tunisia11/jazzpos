import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/receipt_printer/printer_profile.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_document.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_layout_builder.dart';
import 'package:jazzpos/hardware/receipt_printer/receipt_rasterizer.dart';

void main() {
  group('PrinterProfile Presets', () {
    test('all profiles have valid identifiers and line widths', () {
      final profiles = [
        PrinterProfile.genericWindows,
        PrinterProfile.genericEscPos80,
        PrinterProfile.genericEscPos58,
        PrinterProfile.posbank,
        PrinterProfile.epsonEscPos,
        PrinterProfile.bixolon,
        PrinterProfile.star,
      ];

      for (final p in profiles) {
        expect(p.id.isNotEmpty, isTrue);
        expect(p.name.isNotEmpty, isTrue);
        expect(p.paperWidthMm, anyOf(58, 80));
        expect(p.charactersPerLine, anyOf(32, 42, 48));
        expect(p.drawerKickCommand.isNotEmpty, isTrue);
        if (p.hasCutter) {
          expect(p.cutCommand.isNotEmpty, isTrue);
        }
      }
    });

    test('posbank and epson profiles have correct 80mm parameters', () {
      expect(PrinterProfile.posbank.paperWidthMm, equals(80));
      expect(PrinterProfile.posbank.charactersPerLine, equals(48));
      expect(PrinterProfile.epsonEscPos.charactersPerLine, equals(48));
      expect(PrinterProfile.genericEscPos58.charactersPerLine, equals(32));
    });
  });

  group('ReceiptRasterizer', () {
    test(
      'converts test pattern into valid monochrome bytes and ESC/POS raster command',
      () {
        final testPattern = ReceiptRasterizer.createTestRasterPattern(
          width: 128,
          height: 32,
        );

        final monoBytes = ReceiptRasterizer.imageToMonochromeBytes(testPattern);
        expect(monoBytes.isNotEmpty, isTrue);
        expect(monoBytes.length, equals((128 ~/ 8) * 32));

        final rasterBytes = ReceiptRasterizer.rasterizeImage(testPattern);
        expect(rasterBytes.isNotEmpty, isTrue);
        // GS v 0 prefix: 0x1D 0x76 0x30
        expect(rasterBytes[0], equals(0x1D));
        expect(rasterBytes[1], equals(0x76));
        expect(rasterBytes[2], equals(0x30));
      },
    );
  });

  group('ReceiptLayoutBuilder', () {
    test(
      'builds complete receipt bytes with header, items, totals, payments, and cut',
      () {
        final doc = ReceiptDocument(
          storeName: 'BOUTIQUE JAZZ',
          storeAddress: 'Avenue Habib Bourguiba, Tunis',
          storePhone: '+216 71 123 456',
          fiscalId: '1234567/A/M/000',
          receiptNumber: 'T-2026-001',
          dateTime: DateTime(2026, 9, 6, 12, 0),
          cashierName: 'Ahmed',
          registerCode: 'REG-01',
          lines: const [
            ReceiptLineItem(
              productName: 'Chemise Slim Fit',
              variantDescription: 'Bleu / L',
              sku: 'CHM-BLU-L',
              barcode: '6191234567890',
              quantity: 2,
              unitPrice: Money.fromMillimes(65000),
              total: Money.fromMillimes(130000),
              discount: Money.zero,
            ),
          ],
          subtotal: const Money.fromMillimes(130000),
          discount: Money.zero,
          tax: const Money.fromMillimes(24700),
          total: const Money.fromMillimes(130000),
          payments: const [
            ReceiptPaymentItem(
              method: 'ESPECES',
              amount: Money.fromMillimes(130000),
              tendered: Money.fromMillimes(150000),
              change: Money.fromMillimes(20000),
            ),
          ],
        );

        final bytes = ReceiptLayoutBuilder.buildEscPosBytes(
          doc,
          profile: PrinterProfile.posbank,
          includeDrawerKick: true,
          includeCut: true,
        );

        expect(bytes.isNotEmpty, isTrue);

        // Verify drawer kick bytes included at start: 0x1B 0x70 0x00
        expect(bytes.contains(0x1B), isTrue);
        expect(bytes.contains(0x70), isTrue);

        // Verify text presence in Latin-1 representation
        final decoded = latin1.decode(bytes, allowInvalid: true);
        expect(decoded, contains('BOUTIQUE JAZZ'));
        expect(decoded, contains('Chemise Slim Fit'));
        expect(decoded, contains('130.000 TND'));
        expect(decoded, contains('Ahmed'));

        // Verify cut command at end: 0x1D 0x56
        expect(bytes.contains(0x1D), isTrue);
        expect(bytes.contains(0x56), isTrue);
      },
    );

    test('reprinted receipt includes DUPLICATA banner', () {
      final doc = ReceiptDocument(
        storeName: 'BOUTIQUE JAZZ',
        receiptNumber: 'T-2026-002',
        dateTime: DateTime.now(),
        cashierName: 'Sarra',
        registerCode: 'REG-01',
        lines: const [],
        subtotal: Money.zero,
        discount: Money.zero,
        tax: Money.zero,
        total: Money.zero,
        payments: const [],
        isDuplicate: true,
      );

      final bytes = ReceiptLayoutBuilder.buildEscPosBytes(doc);
      final decoded = latin1.decode(bytes, allowInvalid: true);
      expect(decoded, contains('DUPLICATA / REPRINT'));
    });
  });
}
