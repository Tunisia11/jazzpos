import 'dart:math';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

/// Centralized identifier generator for database entities, human-readable
/// ticket numbers, SKUs, and retail barcodes.
class IdGenerator {
  static const _uuid = Uuid();
  static final _random = Random.secure();

  /// Canonical immutable UUID v4
  static String uuid() => _uuid.v4();

  /// Generate human-readable receipt number: REC-YYYYMMDD-XXXXX
  static String receiptNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(90000) + 10000).toString();
    return 'REC-$dateStr-$randomDigits';
  }

  /// Generate return number: RET-YYYYMMDD-XXXXX
  static String returnNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(90000) + 10000).toString();
    return 'RET-$dateStr-$randomDigits';
  }

  /// Generate Purchase Order number: PO-YYYYMMDD-XXXX
  static String poNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(9000) + 1000).toString();
    return 'PO-$dateStr-$randomDigits';
  }

  /// Generate Goods Receipt number: GR-YYYYMMDD-XXXX
  static String goodsReceiptNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(9000) + 1000).toString();
    return 'GR-$dateStr-$randomDigits';
  }

  /// Generate Stock Count number: CNT-YYYYMMDD-XXX
  static String stockCountNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(900) + 100).toString();
    return 'CNT-$dateStr-$randomDigits';
  }

  /// Generate Stock Transfer number: TRF-YYYYMMDD-XXX
  static String stockTransferNumber([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(d);
    final randomDigits = (_random.nextInt(900) + 100).toString();
    return 'TRF-$dateStr-$randomDigits';
  }

  /// Generate standard clothing SKU: e.g. TSH-BLK-M or TSH-000184-BLK-M
  static String generateSku({
    required String productCode,
    String? colorCode,
    String? sizeCode,
    int? sequenceNumber,
  }) {
    final parts = <String>[
      productCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
    ];
    if (sequenceNumber != null) {
      parts.add(sequenceNumber.toString().padLeft(6, '0'));
    }
    if (colorCode != null && colorCode.isNotEmpty) {
      parts.add(colorCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
    }
    if (sizeCode != null && sizeCode.isNotEmpty) {
      parts.add(sizeCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
    }
    return parts.join('-');
  }

  /// Generate internal Code 128 barcode: e.g. "200000012345"
  /// Prefix '200' is standard GS1 in-store restricted distribution
  static String generateInternalBarcode({String prefix = '200'}) {
    final randomDigits = List.generate(9, (_) => _random.nextInt(10)).join();
    return '$prefix$randomDigits';
  }

  /// Generate standard EAN-13 with calculated modulo-10 check digit
  static String generateEan13({String prefix = '200'}) {
    // 12 data digits + 1 check digit
    final data =
        prefix +
        List.generate(12 - prefix.length, (_) => _random.nextInt(10)).join();
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(data[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return '$data$checkDigit';
  }
}
