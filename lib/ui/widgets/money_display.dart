import 'package:flutter/material.dart';
import 'package:jazzpos/core/money/money.dart';
import 'common/price_text.dart';

class MoneyDisplay extends StatelessWidget {
  final Money amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final bool showCurrency;

  const MoneyDisplay({
    super.key,
    required this.amount,
    this.fontSize = 15,
    this.fontWeight = FontWeight.bold,
    this.color,
    this.showCurrency = true,
  });

  @override
  Widget build(BuildContext context) {
    return PriceText(
      money: amount,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      showCurrency: showCurrency,
    );
  }
}
