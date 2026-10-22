import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/money/money.dart';
import 'package:tracepos/hardware/models/hardware_status.dart';
import 'package:tracepos/hardware/receipt_printer/mac_cups_printer.dart';
import 'package:tracepos/hardware/receipt_printer/printer_profile.dart';
import 'package:tracepos/hardware/receipt_printer/receipt_document.dart';

void main() {
  group('MacCupsPrinter', () {
    test('initializes with MACOS_CUPS transport and configured profile', () {
      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        profile: PrinterProfile.genericEscPos80,
      );

      expect(printer.name, equals('EPSON_TM_T20III'));
      expect(printer.connectionType, equals('MACOS_CUPS'));
      expect(printer.fingerprint.transport, equals('MACOS_CUPS'));
      expect(printer.fingerprint.friendlyName, equals('EPSON_TM_T20III'));
      expect(printer.status, equals(HardwareStatus.configured));
    });

    test('isConnected sets status ready when lpstat finds queue', () async {
      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        processRunner: (exe, args, {timeout = const Duration(seconds: 4)}) async {
          expect(exe, equals('lpstat'));
          expect(args, contains('EPSON_TM_T20III'));
          return ProcessResult(1, 0, 'printer EPSON_TM_T20III is idle.', '');
        },
      );

      final ok = await printer.isConnected();
      expect(ok, isTrue);
      expect(printer.status, equals(HardwareStatus.ready));
    });

    test('isConnected sets status offline when lpstat reports disabled', () async {
      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        processRunner: (exe, args, {timeout = const Duration(seconds: 4)}) async {
          return ProcessResult(1, 0, 'printer EPSON_TM_T20III is disabled.', '');
        },
      );

      final ok = await printer.isConnected();
      expect(ok, isFalse);
      expect(printer.status, equals(HardwareStatus.offline));
    });

    test('isConnected sets status missing when lpstat reports unknown destination', () async {
      final printer = MacCupsPrinter(
        name: 'GhostPrinter',
        processRunner: (exe, args, {timeout = const Duration(seconds: 4)}) async {
          return ProcessResult(1, 1, '', 'lpstat: Unknown destination "GhostPrinter".');
        },
      );

      final ok = await printer.isConnected();
      expect(ok, isFalse);
      expect(printer.status, equals(HardwareStatus.missing));
    });

    test('printRaw pipes raw bytes to lpr with -P and -l flags', () async {
      List<String>? capturedArgs;
      Uint8List? capturedFileBytes;

      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        processRunner: (exe, args, {timeout = const Duration(seconds: 10)}) async {
          expect(exe, equals('lpr'));
          capturedArgs = args;
          final filePath = args.last;
          capturedFileBytes = await File(filePath).readAsBytes();
          return ProcessResult(1, 0, '', '');
        },
      );

      final testBytes = Uint8List.fromList([0x1B, 0x40, 0x48, 0x65, 0x6C, 0x6C, 0x6F]); // ESC @ Hello
      await printer.printRaw(testBytes);

      expect(capturedArgs, isNotNull);
      expect(capturedArgs, contains('-P'));
      expect(capturedArgs, contains('EPSON_TM_T20III'));
      expect(capturedArgs, contains('-l')); // Raw/literal mode
      expect(capturedFileBytes, equals(testBytes));
      expect(printer.lastPrintJobs.length, equals(1));
    });

    test('printRaw falls back to lp -d -o raw if lpr fails', () async {
      final executed = <String>[];

      final printer = MacCupsPrinter(
        name: 'POS80',
        processRunner: (exe, args, {timeout = const Duration(seconds: 10)}) async {
          executed.add(exe);
          if (exe == 'lpr') {
            return ProcessResult(1, 1, '', 'lpr command failed');
          }
          if (exe == 'lp') {
            expect(args, contains('-d'));
            expect(args, contains('POS80'));
            expect(args, contains('raw'));
            return ProcessResult(2, 0, 'request id is POS80-1 (1 file)', '');
          }
          return ProcessResult(3, 1, '', 'unknown command');
        },
      );

      await printer.printRaw(Uint8List.fromList([1, 2, 3]));
      expect(executed, equals(['lpr', 'lp']));
      expect(printer.status, equals(HardwareStatus.ready));
    });

    test('openCashDrawer sends profile drawer kick pulse to printer', () async {
      Uint8List? dispatchedBytes;

      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        profile: PrinterProfile.custom(
          name: 'Custom',
          paperWidthMm: 80,
          charactersPerLine: 48,
          hasDrawerPort: true,
          drawerKickCommand: [0x1B, 0x70, 0x00, 0x19, 0xFA],
        ),
        processRunner: (exe, args, {timeout = const Duration(seconds: 10)}) async {
          dispatchedBytes = await File(args.last).readAsBytes();
          return ProcessResult(1, 0, '', '');
        },
      );

      await printer.openCashDrawer();
      expect(dispatchedBytes, equals([0x1B, 0x70, 0x00, 0x19, 0xFA]));
    });

    test('cutPaper sends profile cut command to printer', () async {
      Uint8List? dispatchedBytes;

      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        profile: PrinterProfile.custom(
          name: 'Custom',
          paperWidthMm: 80,
          charactersPerLine: 48,
          hasCutter: true,
          cutCommand: [0x1D, 0x56, 0x41, 0x00],
        ),
        processRunner: (exe, args, {timeout = const Duration(seconds: 10)}) async {
          dispatchedBytes = await File(args.last).readAsBytes();
          return ProcessResult(1, 0, '', '');
        },
      );

      await printer.cutPaper();
      expect(dispatchedBytes, equals([0x1D, 0x56, 0x41, 0x00]));
    });

    test('printReceipt compiles receipt document and transmits via CUPS', () async {
      int printCallCount = 0;

      final printer = MacCupsPrinter(
        name: 'EPSON_TM_T20III',
        processRunner: (exe, args, {timeout = const Duration(seconds: 10)}) async {
          printCallCount++;
          return ProcessResult(1, 0, '', '');
        },
      );

      final doc = ReceiptDocument(
        storeName: 'BOUTIQUE TEST',
        storeAddress: 'Tunis, Tunisie',
        receiptNumber: 'REC-001',
        dateTime: DateTime.now(),
        cashierName: 'Mohamed',
        registerCode: 'REG-01',
        lines: [
          const ReceiptLineItem(
            productName: 'Robe en Soie Noir 38',
            variantDescription: 'Noir / 38',
            sku: 'ROBE-001',
            barcode: '123456789012',
            quantity: 1,
            unitPrice: Money.fromMillimes(120000),
            total: Money.fromMillimes(120000),
          ),
        ],
        subtotal: const Money.fromMillimes(120000),
        discount: Money.zero,
        tax: Money.zero,
        total: const Money.fromMillimes(120000),
        payments: [
          const ReceiptPaymentItem(method: 'CASH', amount: Money.fromMillimes(120000)),
        ],
      );

      await printer.printReceipt(doc);
      expect(printCallCount, equals(1));
    });
  });
}
