import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/money/money.dart';
import 'package:jazzpos/hardware/models/hardware_fingerprint.dart';
import 'package:jazzpos/hardware/models/hardware_status.dart';
import 'esc_pos_commands.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';
import 'receipt_printer_interface.dart';

class EscPosReceiptPrinter implements ReceiptPrinter {
  @override
  final String name;
  @override
  final String connectionType; // NETWORK, USB, SERIAL
  final String address; // e.g. "192.168.1.200:9100" or "/dev/ttyUSB0"
  final int port;
  @override
  final PrinterProfile profile;
  @override
  final HardwareFingerprint? fingerprint;

  Socket? _socket;
  bool _connected = false;

  EscPosReceiptPrinter({
    required this.name,
    this.connectionType = 'NETWORK',
    required this.address,
    this.port = 9100,
    this.profile = PrinterProfile.genericEscPos80,
    this.fingerprint,
  });

  @override
  HardwareStatus get status =>
      _connected ? HardwareStatus.ready : HardwareStatus.offline;

  @override
  Future<bool> printRaw(Uint8List bytes) async {
    try {
      if (!_connected || _socket == null) {
        final ok = await connect();
        if (!ok) return false;
      }
      _socket!.add(bytes);
      await _socket!.flush();
      return true;
    } catch (e) {
      PosLogger.instance.error(
        'EscPosReceiptPrinter',
        'Failed to send raw bytes',
        e,
      );
      _connected = false;
      return false;
    }
  }

  @override
  Future<bool> connect() async {
    try {
      if (connectionType == 'NETWORK') {
        _socket = await Socket.connect(
          address,
          port,
          timeout: const Duration(seconds: 3),
        );
        _connected = true;
        PosLogger.instance.info(
          'Printer',
          'Connected to ESC/POS network printer at $address:$port',
        );
        return true;
      }
      _connected = true;
      return true;
    } catch (e) {
      _connected = false;
      PosLogger.instance.error(
        'Printer',
        'Failed to connect to ESC/POS printer at $address',
        e,
      );
      return false;
    }
  }

  @override
  Future<bool> isConnected() async => _connected;

  @override
  Future<void> openCashDrawer() async {
    final bytes = EscPosCommands.openCashDrawer();
    await _sendBytes(Uint8List.fromList(bytes));
  }

  @override
  Future<void> cutPaper() async {
    final bytes = EscPosCommands.cutPaper();
    await _sendBytes(Uint8List.fromList(bytes));
  }

  @override
  Future<void> printReceipt(ReceiptDocument doc) async {
    final width = doc.paperWidthMm == 58 ? 32 : 48;
    final bytes = <int>[];

    // Initialize
    bytes.addAll(EscPosCommands.initialize());

    // Header Center & Bold
    bytes.addAll(EscPosCommands.setAlign(1));
    bytes.addAll(EscPosCommands.setBold(true));
    bytes.addAll(
      EscPosCommands.setTextSize(doubleHeight: true, doubleWidth: true),
    );
    bytes.addAll(utf8.encode('${doc.storeName}\n'));
    bytes.addAll(
      EscPosCommands.setTextSize(doubleHeight: false, doubleWidth: false),
    );
    bytes.addAll(EscPosCommands.setBold(false));

    if (doc.storeAddress != null) {
      bytes.addAll(utf8.encode('${doc.storeAddress}\n'));
    }
    if (doc.storePhone != null) {
      bytes.addAll(utf8.encode('Tel: ${doc.storePhone}\n'));
    }
    if (doc.fiscalId != null) {
      bytes.addAll(utf8.encode('Matricule Fiscale: ${doc.fiscalId}\n'));
    }
    bytes.addAll(utf8.encode('${'=' * width}\n'));

    // Align Left
    bytes.addAll(EscPosCommands.setAlign(0));
    if (doc.isDuplicate) {
      bytes.addAll(EscPosCommands.setAlign(1));
      bytes.addAll(EscPosCommands.setBold(true));
      bytes.addAll(utf8.encode('*** DUPLICATA ***\n'));
      bytes.addAll(EscPosCommands.setBold(false));
      bytes.addAll(EscPosCommands.setAlign(0));
    }

    bytes.addAll(utf8.encode('Ticket: ${doc.receiptNumber}\n'));
    bytes.addAll(
      utf8.encode(
        'Date:   ${doc.dateTime.toLocal().toString().split('.')[0]}\n',
      ),
    );
    bytes.addAll(
      utf8.encode(
        'Caisse: ${doc.registerCode} | Caissier: ${doc.cashierName}\n',
      ),
    );
    bytes.addAll(utf8.encode('${'-' * width}\n'));

    // Items
    for (final line in doc.lines) {
      bytes.addAll(EscPosCommands.setBold(true));
      bytes.addAll(utf8.encode('${line.productName}\n'));
      bytes.addAll(EscPosCommands.setBold(false));

      final details =
          '  ${line.variantDescription} (${line.quantity} x ${line.unitPrice.format()})';
      final total = line.total.format();
      final lineStr = EscPosCommands.formatColumns(
        left: details,
        right: total,
        width: width,
      );
      bytes.addAll(utf8.encode('$lineStr\n'));

      if (line.discount > Money.zero) {
        final remStr = EscPosCommands.formatColumns(
          left: '  Remise:',
          right: '-${line.discount.format()}',
          width: width,
        );
        bytes.addAll(utf8.encode('$remStr\n'));
      }
    }
    bytes.addAll(utf8.encode('${'-' * width}\n'));

    // Totals
    bytes.addAll(
      utf8.encode(
        '${EscPosCommands.formatColumns(left: 'SOUS-TOTAL:', right: doc.subtotal.format(), width: width)}\n',
      ),
    );
    if (doc.discount > Money.zero) {
      bytes.addAll(
        utf8.encode(
          '${EscPosCommands.formatColumns(left: 'REMISE:', right: '-${doc.discount.format()}', width: width)}\n',
        ),
      );
    }
    if (doc.tax > Money.zero) {
      bytes.addAll(
        utf8.encode(
          '${EscPosCommands.formatColumns(left: 'TVA:', right: doc.tax.format(), width: width)}\n',
        ),
      );
    }
    bytes.addAll(EscPosCommands.setBold(true));
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: true));
    bytes.addAll(
      utf8.encode(
        '${EscPosCommands.formatColumns(left: 'TOTAL:', right: doc.total.format(), width: width)}\n',
      ),
    );
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: false));
    bytes.addAll(EscPosCommands.setBold(false));
    bytes.addAll(utf8.encode('${'-' * width}\n'));

    // Payments
    for (final p in doc.payments) {
      final pStr = EscPosCommands.formatColumns(
        left: 'Paiement (${p.method}):',
        right: p.amount.format(),
        width: width,
      );
      bytes.addAll(utf8.encode('$pStr\n'));
      if (p.tendered > Money.zero) {
        bytes.addAll(
          utf8.encode(
            '${EscPosCommands.formatColumns(left: '  Espece:', right: p.tendered.format(), width: width)}\n',
          ),
        );
        bytes.addAll(
          utf8.encode(
            '${EscPosCommands.formatColumns(left: '  Rendu:', right: p.change.format(), width: width)}\n',
          ),
        );
      }
    }

    bytes.addAll(utf8.encode('${'-' * width}\n'));

    // Barcode on ticket for quick return scanning!
    bytes.addAll(EscPosCommands.setAlign(1));
    bytes.addAll(EscPosCommands.printBarcode128(doc.receiptNumber));
    bytes.addAll(EscPosCommands.feed(1));

    if (doc.footerMessage != null) {
      bytes.addAll(utf8.encode('${doc.footerMessage}\n'));
    } else {
      bytes.addAll(utf8.encode('Merci de votre visite !\n'));
      bytes.addAll(
        utf8.encode(
          'Articles echangeables sous 15 jours sur presentation du ticket\n',
        ),
      );
    }

    bytes.addAll(EscPosCommands.feed(3));
    bytes.addAll(EscPosCommands.cutPaper());

    await _sendBytes(Uint8List.fromList(bytes));
    PosLogger.instance.info('Printer', 'ESC/POS receipt sent to $name');
  }

  Future<void> _sendBytes(Uint8List data) async {
    if (_socket == null) {
      final ok = await connect();
      if (!ok) throw Exception('Cannot connect to printer $address');
    }
    try {
      _socket!.add(data);
      await _socket!.flush();
    } catch (e) {
      _connected = false;
      try {
        await _socket?.close();
      } catch (_) {}
      _socket = null;
      throw Exception('Printer communication error: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _connected = false;
  }
}
