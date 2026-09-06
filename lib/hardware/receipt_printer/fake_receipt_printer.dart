import 'dart:async';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_printer_interface.dart';

class FakeReceiptPrinter implements ReceiptPrinter {
  @override
  final String name;
  @override
  final String connectionType = 'SIMULATED';
  @override
  PrinterProfile get profile => PrinterProfile.genericEscPos80;
  @override
  HardwareStatus get status => HardwareStatus.simulated;
  @override
  HardwareFingerprint? get fingerprint => null;

  bool _connected = true;
  int drawerOpenCount = 0;
  int paperCutCount = 0;
  final List<ReceiptDocument> printedDocuments = [];
  final List<String> printedTextReceipts = [];

  final _receiptStreamController = StreamController<String>.broadcast();
  Stream<String> get onReceiptPrinted => _receiptStreamController.stream;

  FakeReceiptPrinter({this.name = 'Simulated 80mm ESC/POS Printer'});

  @override
  Future<bool> printRaw(Uint8List bytes) async {
    return true;
  }

  @override
  Future<bool> connect() async {
    _connected = true;
    PosLogger.instance.info('Printer', 'Connected to $name (Fake)');
    return true;
  }

  @override
  Future<bool> isConnected() async => _connected;

  void simulateDisconnect() {
    _connected = false;
    PosLogger.instance.warning('Printer', '$name simulated disconnect');
  }

  void simulateReconnect() {
    _connected = true;
    PosLogger.instance.info('Printer', '$name simulated reconnect');
  }

  @override
  Future<void> openCashDrawer() async {
    if (!_connected) throw Exception('Printer $name is disconnected');
    drawerOpenCount++;
    PosLogger.instance.info(
      'CashDrawer',
      'Cash drawer kick pulse fired via $name',
    );
  }

  @override
  Future<void> cutPaper() async {
    if (!_connected) throw Exception('Printer $name is disconnected');
    paperCutCount++;
    PosLogger.instance.info('Printer', 'Paper cut command sent to $name');
  }

  @override
  Future<void> printReceipt(ReceiptDocument doc) async {
    if (!_connected) {
      throw Exception('Printer $name is not connected or paper out');
    }

    final width = doc.paperWidthMm == 58 ? 32 : 48;
    final buffer = StringBuffer();
    final divider = '=' * width;
    final thinDivider = '-' * width;

    // Header
    buffer.writeln(divider);
    buffer.writeln(_center(doc.storeName.toUpperCase(), width));
    if (doc.storeAddress != null) {
      buffer.writeln(_center(doc.storeAddress!, width));
    }
    if (doc.storePhone != null) {
      buffer.writeln(_center('Tel: ${doc.storePhone}', width));
    }
    if (doc.fiscalId != null) {
      buffer.writeln(_center('Mat. Fiscale: ${doc.fiscalId}', width));
    }
    buffer.writeln(divider);

    if (doc.isDuplicate) {
      buffer.writeln(_center('*** DUPLICATA / REPRINT ***', width));
      buffer.writeln(thinDivider);
    }

    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(doc.dateTime);
    buffer.writeln('Ticket: ${doc.receiptNumber}');
    buffer.writeln('Date:   $dateStr');
    buffer.writeln(
      'Caisse: ${doc.registerCode} | Caissier: ${doc.cashierName}',
    );
    buffer.writeln(thinDivider);

    // Items
    for (final item in doc.lines) {
      buffer.writeln(item.productName);
      buffer.writeln('  [${item.variantDescription}]');
      final qtyAndPrice = '${item.quantity} x ${item.unitPrice.format()}';
      final lineTotal = item.total.format();
      buffer.writeln(_formatTwoCol('  $qtyAndPrice', lineTotal, width));
      if (item.discount > Money.zero) {
        buffer.writeln(
          _formatTwoCol('  Remise:', '-${item.discount.format()}', width),
        );
      }
    }
    buffer.writeln(thinDivider);

    // Totals
    buffer.writeln(_formatTwoCol('SOUS-TOTAL:', doc.subtotal.format(), width));
    if (doc.discount > Money.zero) {
      buffer.writeln(
        _formatTwoCol('REMISE:', '-${doc.discount.format()}', width),
      );
    }
    if (doc.tax > Money.zero) {
      buffer.writeln(_formatTwoCol('TVA:', doc.tax.format(), width));
    }
    buffer.writeln(_formatTwoCol('TOTAL:', doc.total.format(), width));
    buffer.writeln(thinDivider);

    // Payments
    for (final p in doc.payments) {
      buffer.writeln(
        _formatTwoCol('Paiement (${p.method}):', p.amount.format(), width),
      );
      if (p.tendered > Money.zero) {
        buffer.writeln(
          _formatTwoCol('  Espèce reçu:', p.tendered.format(), width),
        );
        buffer.writeln(
          _formatTwoCol('  Monnaie rendue:', p.change.format(), width),
        );
      }
    }

    buffer.writeln(thinDivider);
    if (doc.footerMessage != null) {
      buffer.writeln(_center(doc.footerMessage!, width));
    } else {
      buffer.writeln(_center('Merci pour votre visite !', width));
      buffer.writeln(
        _center('Les articles peuvent etre echanges sous 15 jours', width),
      );
    }
    buffer.writeln(_center('||||| ${doc.receiptNumber} |||||', width));
    buffer.writeln(divider);

    final text = buffer.toString();
    printedDocuments.add(doc);
    printedTextReceipts.add(text);
    _receiptStreamController.add(text);

    PosLogger.instance.info(
      'Printer',
      'Successfully printed simulated receipt #${doc.receiptNumber}',
    );
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  String _center(String text, int width) {
    if (text.length >= width) return text;
    final leftPadding = (width - text.length) ~/ 2;
    return ' ' * leftPadding + text;
  }

  String _formatTwoCol(String left, String right, int width) {
    final spaces = width - left.length - right.length;
    if (spaces < 1) return '$left $right';
    return '$left${' ' * spaces}$right';
  }
}
