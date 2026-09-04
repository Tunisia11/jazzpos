import 'package:flutter/material.dart';
import 'package:jazzpos/core/money/money.dart';

class MoneyDisplay extends StatelessWidget {
  final Money amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final bool showCurrency;

  const MoneyDisplay({
    super.key,
    required this.amount,
    this.fontSize = 16,
    this.fontWeight = FontWeight.bold,
    this.color,
    this.showCurrency = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? (amount.isNegative ? Colors.redAccent : Colors.white);
    return Text(
      amount.format(includeCurrency: showCurrency),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: textColor,
        fontFamily: 'monospace',
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
