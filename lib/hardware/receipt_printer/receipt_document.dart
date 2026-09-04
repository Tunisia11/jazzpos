import 'package:jazzpos/core/money/money.dart';

class ReceiptLineItem {
  final String productName;
  final String variantDescription; // e.g. "Black / M"
  final String sku;
  final String barcode;
  final int quantity;
  final Money unitPrice;
  final Money total;
  final Money discount;

  const ReceiptLineItem({
    required this.productName,
    required this.variantDescription,
    required this.sku,
    required this.barcode,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.discount = Money.zero,
  });
}

class ReceiptPaymentItem {
  final String method;
  final Money amount;
  final Money tendered;
  final Money change;

  const ReceiptPaymentItem({
    required this.method,
    required this.amount,
    this.tendered = Money.zero,
    this.change = Money.zero,
  });
}

class ReceiptDocument {
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final String? fiscalId;
  final String receiptNumber;
  final DateTime dateTime;
  final String cashierName;
  final String registerCode;
  final List<ReceiptLineItem> lines;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
  final List<ReceiptPaymentItem> payments;
  final String? footerMessage;
  final bool isDuplicate;
  final int paperWidthMm; // 58 or 80

  const ReceiptDocument({
    required this.storeName,
    this.storeAddress,
    this.storePhone,
    this.fiscalId,
    required this.receiptNumber,
    required this.dateTime,
    required this.cashierName,
    required this.registerCode,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.payments,
    this.footerMessage,
    this.isDuplicate = false,
    this.paperWidthMm = 80,
  });
}
