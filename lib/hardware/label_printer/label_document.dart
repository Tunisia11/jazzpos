import 'package:jazzpos/core/money/money.dart';

class LabelDocument {
  final String storeName;
  final String productName;
  final String? brandName;
  final String? collection;
  final String? size;
  final String? color;
  final String sku;
  final String barcode;
  final String barcodeType; // CODE128, EAN13
  final Money price;
  final Money? oldPrice;
  final int widthMm; // 40, 50, 60
  final int heightMm; // 25, 30, 40
  final int copies;

  const LabelDocument({
    required this.storeName,
    required this.productName,
    this.brandName,
    this.collection,
    this.size,
    this.color,
    required this.sku,
    required this.barcode,
    this.barcodeType = 'CODE128',
    required this.price,
    this.oldPrice,
    this.widthMm = 40,
    this.heightMm = 25,
    this.copies = 1,
  });

  String get variantTag {
    final parts = <String>[];
    if (color != null && color!.isNotEmpty) parts.add(color!);
    if (size != null && size!.isNotEmpty) parts.add(size!);
    return parts.join(' - ');
  }
}
