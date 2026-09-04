import 'package:jazzpos/core/money/money.dart';

/// A line item in the POS sale cart with immutable product snapshot details.
class CartItem {
  final String variantId;
  final String productId;
  final String productName;
  final String variantDescription; // e.g. "BLACK / M"
  final String sku;
  final String barcode;
  final Money unitPrice;
  final Money originalPrice;
  final int quantity;
  final Money lineDiscount;
  final double taxRatePercent;
  final Money unitCost;

  const CartItem({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.variantDescription,
    required this.sku,
    required this.barcode,
    required this.unitPrice,
    required this.originalPrice,
    this.quantity = 1,
    this.lineDiscount = Money.zero,
    this.taxRatePercent = 0.0,
    this.unitCost = Money.zero,
  });

  Money get subtotal => unitPrice * quantity;
  Money get total => subtotal - lineDiscount;
  Money get totalCost => unitCost * quantity;
  Money get grossProfit => total - totalCost;

  Money get taxAmount {
    if (taxRatePercent <= 0) return Money.zero;
    return total.percentageDiscount(taxRatePercent);
  }

  CartItem copyWith({
    String? variantId,
    String? productId,
    String? productName,
    String? variantDescription,
    String? sku,
    String? barcode,
    Money? unitPrice,
    Money? originalPrice,
    int? quantity,
    Money? lineDiscount,
    double? taxRatePercent,
    Money? unitCost,
  }) {
    return CartItem(
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      variantDescription: variantDescription ?? this.variantDescription,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      unitPrice: unitPrice ?? this.unitPrice,
      originalPrice: originalPrice ?? this.originalPrice,
      quantity: quantity ?? this.quantity,
      lineDiscount: lineDiscount ?? this.lineDiscount,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}
