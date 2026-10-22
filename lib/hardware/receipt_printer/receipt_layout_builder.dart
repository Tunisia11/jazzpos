import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:tracepos/core/localization/app_localizations.dart';
import 'package:tracepos/core/money/money.dart';
import 'esc_pos_commands.dart';
import 'printer_profile.dart';
import 'receipt_document.dart';

/// Configurable, localized labels for ESC/POS receipt printing.
class ReceiptLabels {
  final String duplicateBanner;
  final String ticket;
  final String date;
  final String register;
  final String cashier;
  final String discount;
  final String subtotal;
  final String tax;
  final String total;
  final String payment;
  final String tendered;
  final String change;
  final String defaultFooterGreeting;
  final String defaultFooterPolicy;

  const ReceiptLabels({
    this.duplicateBanner = '*** DUPLICATA / REPRINT ***',
    this.ticket = 'Ticket',
    this.date = 'Date',
    this.register = 'Caisse',
    this.cashier = 'Caissier',
    this.discount = 'Remise:',
    this.subtotal = 'SOUS-TOTAL:',
    this.tax = 'TVA:',
    this.total = 'TOTAL:',
    this.payment = 'Paiement',
    this.tendered = 'Espece:',
    this.change = 'Rendu:',
    this.defaultFooterGreeting = 'Merci de votre visite !',
    this.defaultFooterPolicy = 'Articles echangeables sous 15 jours sur ticket',
  });

  factory ReceiptLabels.fromLocalizations(AppLocalizations loc) {
    return ReceiptLabels(
      duplicateBanner: loc.receiptDuplicateBanner,
      ticket: loc.receiptTicketLabel,
      date: loc.receiptDateLabel,
      register: loc.receiptRegisterLabel,
      cashier: loc.receiptCashierLabel,
      discount: '${loc.receiptLineDiscount}:',
      subtotal: '${loc.receiptSubtotal}:',
      tax: '${loc.receiptTax}:',
      total: '${loc.receiptTotal}:',
      payment: loc.receiptPaymentMode,
      tendered: '${loc.receiptTendered}:',
      change: '${loc.receiptChange}:',
      defaultFooterGreeting: loc.receiptFooterGreeting,
      defaultFooterPolicy: loc.receiptFooterPolicy,
    );
  }
}

/// Decoupled builder that formats a [ReceiptDocument] into raw printer byte streams
/// based on the selected [PrinterProfile].
class ReceiptLayoutBuilder {
  /// Converts a [ReceiptDocument] to ESC/POS byte sequence according to [profile].
  static Uint8List buildEscPosBytes(
    ReceiptDocument doc, {
    PrinterProfile profile = PrinterProfile.genericEscPos80,
    bool includeDrawerKick = false,
    bool includeCut = true,
    ReceiptLabels labels = const ReceiptLabels(),
  }) {
    final width = profile.charactersPerLine;
    final bytes = <int>[];

    // 1. Initialize
    if (profile.defaultCodePage != 'PC850') throw UnsupportedError('Receipt encoding not supported: ${profile.defaultCodePage}');
    bytes.addAll(EscPosCommands.initialize());
    bytes.addAll([0x1B, 0x74, 2]); // ESC t 2: Epson-compatible PC850; verify device emulation onsite.

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
      bytes.addAll(_encodeString('${labels.duplicateBanner}\n'));
      bytes.addAll(EscPosCommands.setBold(false));
    }

    // 5. Metadata
    bytes.addAll(EscPosCommands.setAlign(0));
    bytes.addAll(_encodeString('${labels.ticket}: ${doc.receiptNumber}\n'));
    final dateStr = DateFormat(
      'dd/MM/yyyy HH:mm:ss',
    ).format(doc.dateTime.toLocal());
    bytes.addAll(_encodeString('${labels.date}:   $dateStr\n'));
    bytes.addAll(
      _encodeString(
        '${labels.register}: ${doc.registerCode} | ${labels.cashier}: ${doc.cashierName}\n',
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
          left: '  ${labels.discount}',
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
        '${EscPosCommands.formatColumns(left: labels.subtotal, right: doc.subtotal.format(), width: width)}\n',
      ),
    );
    if (doc.discount > Money.zero) {
      bytes.addAll(
        _encodeString(
          '${EscPosCommands.formatColumns(left: labels.discount, right: '-${doc.discount.format()}', width: width)}\n',
        ),
      );
    }
    if (doc.tax > Money.zero) {
      bytes.addAll(
        _encodeString(
          '${EscPosCommands.formatColumns(left: labels.tax, right: doc.tax.format(), width: width)}\n',
        ),
      );
    }

    // Grand Total (Large font)
    bytes.addAll(EscPosCommands.setBold(true));
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: true));
    bytes.addAll(
      _encodeString(
        '${EscPosCommands.formatColumns(left: labels.total, right: doc.total.format(), width: width)}\n',
      ),
    );
    bytes.addAll(EscPosCommands.setTextSize(doubleHeight: false));
    bytes.addAll(EscPosCommands.setBold(false));
    bytes.addAll(_encodeString('${'-' * width}\n'));

    // 8. Payment Breakdown
    for (final p in doc.payments) {
      final pStr = EscPosCommands.formatColumns(
        left: '${labels.payment} (${p.method}):',
        right: p.amount.format(),
        width: width,
      );
      bytes.addAll(_encodeString('$pStr\n'));
      if (p.tendered > Money.zero) {
        bytes.addAll(
          _encodeString(
            '${EscPosCommands.formatColumns(left: '  ${labels.tendered}', right: p.tendered.format(), width: width)}\n',
          ),
        );
        bytes.addAll(
          _encodeString(
            '${EscPosCommands.formatColumns(left: '  ${labels.change}', right: p.change.format(), width: width)}\n',
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
      bytes.addAll(_encodeString('${labels.defaultFooterGreeting}\n'));
      bytes.addAll(
        _encodeString('${labels.defaultFooterPolicy}\n'),
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
    const upper = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐└┴┬├─┼ãÃ╚╔╩╦╠═╬¤ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀ÓßÔÒõÕµþÞÚÛÙýÝ¯´­±‗¾¶§÷¸°¨·¹³²■ ';
    return text.runes.map((r) {
      if (r < 128) return r;
      final index = upper.indexOf(String.fromCharCode(r));
      return index < 0 ? 63 : index + 128;
    }).toList();
  }
}
