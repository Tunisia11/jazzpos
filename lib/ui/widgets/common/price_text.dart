import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations_delegate.dart';
import '../../../core/money/money.dart';
import '../../theme/app_theme.dart';

class PriceText extends StatelessWidget {
  final Money? money;
  final double? amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final bool showCurrency;

  const PriceText({
    super.key,
    this.money,
    this.amount,
    this.fontSize = 15,
    this.fontWeight = FontWeight.bold,
    this.color,
    this.showCurrency = true,
  }) : assert(
         money != null || amount != null,
         'Either money or amount must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final effectiveMoney = money ?? Money.fromDouble(amount ?? 0.0);
    final isNegative = effectiveMoney.isNegative;
    final textColor =
        color ?? (isNegative ? AppTheme.danger : AppTheme.textPrimary);

    String formattedText;
    if (showCurrency) {
      try {
        formattedText = context.loc.formatCurrency(
          effectiveMoney.toTndDouble(),
        );
      } catch (_) {
        formattedText = effectiveMoney.format(includeCurrency: true);
      }
    } else {
      formattedText = effectiveMoney.format(includeCurrency: false);
    }

    return Text(
      formattedText,
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
