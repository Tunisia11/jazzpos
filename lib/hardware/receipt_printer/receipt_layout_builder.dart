import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:jazzpos/core/money/money.dart';
import 'esc_pos_commands.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';

/// Decoupled builder that formats a [ReceiptDocument] into raw printer byte streams
/// based on the selected [PrinterProfile].
class ReceiptLayoutBuilder {
  /// Converts a [ReceiptDocument] to ESC/POS byte sequence according to [profile].
  static Uint8List buildEscPosBytes(
    ReceiptDocument doc, {
    PrinterProfile profile = PrinterProfile.genericEscPos80,
    bool includeDrawerKick = false,
    bool includeCut = true,
  }) {
    final width = profile.charactersPerLine;
    final bytes = <int>[];

    // 1. Initialize
    bytes.addAll(EscPosCommands.initialize());

    // 2. Optional Drawer Kick at start of printing
    if (includeDrawerKick && profile.hasDrawerPort) {
      bytes.addAll(profile.drawerKickCommand);
    }

    // 3. Header Center & Bold
    bytes.addAll(EscPosCommands.setAlign(1));
    bytes.addAll(EscPosCommands.setBold(true));
    bytes.addAll(
      EscPosCommands.setTextSize(doubleHeight: true, doubleWidth: true),
    );
    bytes.addAll(_encodeString('${doc.storeName}\n'));
    bytes.addAll(
      EscPosCommands.setTextSize(doubleHeight: false, doubleWidth: false),
    );
    bytes.addAll(EscPosCommands.setBold(false));

    if (doc.storeAddress != null) {
      bytes.addAll(_encodeString('${doc.storeAddress}\n'));
    }
    if (doc.storePhone != null) {
      bytes.addAll(_encodeString('Tel: ${doc.storePhone}\n'));
    }
    if (doc.fiscalId != null) {
      bytes.addAll(_encodeString('Matricule Fiscale: ${doc.fiscalId}\n'));
    }
    bytes.addAll(_encodeString('${'=' * width}\n'));

    // 4. Duplicate Banner
    if (doc.isDuplicate) {
      bytes.addAll(EscPosCommands.setAlign(1));
      bytes.addAll(EscPosCommands.setBold(true));
      bytes.addAll(_encodeString('*** DUPLICATA / REPRINT ***\n'));
      bytes.addAll(EscPosCommands.setBold(false));
    }

    // 5. Metadata
    bytes.addAll(EscPosCommands.setAlign(0));
    bytes.addAll(_encodeString('Ticket: ${doc.receiptNumber}\n'));
    final dateStr = DateFormat(
      'dd/MM/yyyy HH:mm:ss',
    ).format(doc.dateTime.toLocal());
    bytes.addAll(_encodeString('Date:   $dateStr\n'));
    bytes.addAll(
      _encodeString(
        'Caisse: ${doc.registerCode} | Caissier: ${doc.cashierName}\n',
      ),
    );
    bytes.addAll(_encodeString('${'-' * width}\n'));

    // 6. Line Items
    for (final line in doc.lines) {
      bytes.addAll(EscPosCommands.setBold(true));
      bytes.addAll(_encodeString('${line.productName}\n'));
      bytes.addAll(EscPosCommands.setBold(false));

      final details =
          '  ${line.variantDescription} (${line.quantity} x ${line.unitPrice.format()})';
      final total = line.total.format();
      final lineStr = EscPosCommands.formatColumns(
        left: details,
        right: total,
        width: width,
      );
      bytes.addAll(_encodeString('$lineStr\n'));

      if (line.discount > Money.zero) {
        final remStr = EscPosCommands.formatColumns(
          left: '  Remise:',
          right: '-${line.discount.format()}',
          width: width,
        );
        bytes.addAll(_encodeString('$remStr\n'));
      }
    }
    bytes.addAll(_encodeString('${'-' * width}\n'));

    // 7. Totals & Discounts
    bytes.addAll(
      _encodeString(
        '${EscPosCommands.formatColumns(left: 'SOUS-TOTAL:', right: doc.subtotal.format(), width: width)}\n',
      ),
    );
    if (doc.discount > Money.zero) {
      bytes.addAll(
        _encodeString(
          '${EscPosCommands.formatColumns(left: 'REMISE:', right: '-${doc.discount.format()}', width: width)}\n',
        ),
      );
    }
    if (doc.tax > Money.zero) {
      bytes.addAll(
        _encodeString(
          '${EscPosCommands.formatColumns(left: 'TVA:', right: doc.tax.format(), width: width)}\n',
        ),
      );
    }

    // Grand Total (Large font)
    bytes.addAll(EscPosCommands.setBold(true));
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: true));
    bytes.addAll(
      _encodeString(
        '${EscPosCommands.formatColumns(left: 'TOTAL:', right: doc.total.format(), width: width)}\n',
      ),
    );
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: false));
    bytes.addAll(EscPosCommands.setBold(false));
    bytes.addAll(_encodeString('${'-' * width}\n'));

    // 8. Payment Breakdown
    for (final p in doc.payments) {
      final pStr = EscPosCommands.formatColumns(
        left: 'Paiement (${p.method}):',
        right: p.amount.format(),
        width: width,
      );
      bytes.addAll(_encodeString('$pStr\n'));
      if (p.tendered > Money.zero) {
        bytes.addAll(
          _encodeString(
            '${EscPosCommands.formatColumns(left: '  Espece:', right: p.tendered.format(), width: width)}\n',
          ),
        );
        bytes.addAll(
          _encodeString(
            '${EscPosCommands.formatColumns(left: '  Rendu:', right: p.change.format(), width: width)}\n',
          ),
        );
      }
    }
    bytes.addAll(_encodeString('${'-' * width}\n'));

    // 9. Barcode
    if (profile.supportsBarcode128 && doc.receiptNumber.isNotEmpty) {
      bytes.addAll(EscPosCommands.setAlign(1));
      bytes.addAll(EscPosCommands.printBarcode128(doc.receiptNumber));
      bytes.addAll(EscPosCommands.feed(1));
    }

    // 10. Footer Message
    bytes.addAll(EscPosCommands.setAlign(1));
    if (doc.footerMessage != null) {
      bytes.addAll(_encodeString('${doc.footerMessage}\n'));
    } else {
      bytes.addAll(_encodeString('Merci de votre visite !\n'));
      bytes.addAll(
        _encodeString('Articles echangeables sous 15 jours sur ticket\n'),
      );
    }

    // 11. Feed & Cut
    bytes.addAll(EscPosCommands.feed(3));
    if (includeCut && profile.hasCutter && profile.cutCommand.isNotEmpty) {
      bytes.addAll(profile.cutCommand);
    }

    return Uint8List.fromList(bytes);
  }

  /// Safe encoding converting accented characters to standard ASCII/PC850 fallback
  static List<int> _encodeString(String text) {
    return utf8.encode(text);
  }
}
