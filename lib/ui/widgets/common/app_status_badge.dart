import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../theme/app_design_tokens.dart';

enum AppStatusType {
  inStock,
  lowStock,
  outOfStock,
  negativeStock,
  success,
  warning,
  danger,
  neutral,
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppStatusType type;
  final IconData? icon;
  final bool isCompact;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.icon,
    this.isCompact = false,
  });

  factory AppStatusBadge.forStock({
    required int stock,
    AppLocalizations? loc,
    int minStockAlert = 2,
    String? inStockLabel,
    String? lowStockLabel,
    String? outOfStockLabel,
    String? negativeStockLabel,
    bool isCompact = false,
  }) {
    if (stock < 0) {
      final text =
          negativeStockLabel ??
          (loc != null
              ? '${loc.negativeStock} ($stock)'
              : 'Stock négatif ($stock)');
      return AppStatusBadge(
        label: text,
        type: AppStatusType.negativeStock,
        icon: Icons.warning_amber_rounded,
        isCompact: isCompact,
      );
    } else if (stock == 0) {
      final text =
          outOfStockLabel ??
          (loc != null ? '${loc.outOfStock} (0)' : 'Rupture (0)');
      return AppStatusBadge(
        label: text,
        type: AppStatusType.outOfStock,
        icon: Icons.block,
        isCompact: isCompact,
      );
    } else if (stock <= minStockAlert) {
      final text =
          lowStockLabel ??
          (loc != null ? '${loc.lowStock} ($stock)' : 'Stock faible ($stock)');
      return AppStatusBadge(
        label: text,
        type: AppStatusType.lowStock,
        icon: Icons.info_outline,
        isCompact: isCompact,
      );
    } else {
      final text =
          inStockLabel ??
          (loc != null ? '${loc.inStock} ($stock)' : 'En stock ($stock)');
      return AppStatusBadge(
        label: text,
        type: AppStatusType.inStock,
        icon: Icons.check_circle_outline,
        isCompact: isCompact,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide border;

    switch (type) {
      case AppStatusType.inStock:
      case AppStatusType.success:
        bg = AppDesignTokens.successBg;
        fg = AppDesignTokens.successText;
        border = const BorderSide(color: Color(0xFFA7F3D0));
        break;
      case AppStatusType.lowStock:
      case AppStatusType.warning:
        bg = AppDesignTokens.warningBg;
        fg = AppDesignTokens.warningText;
        border = const BorderSide(color: Color(0xFFFDE68A));
        break;
      case AppStatusType.outOfStock:
      case AppStatusType.danger:
        bg = AppDesignTokens.dangerBg;
        fg = AppDesignTokens.dangerText;
        border = const BorderSide(color: Color(0xFFFECACA));
        break;
      case AppStatusType.negativeStock:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        border = const BorderSide(color: AppDesignTokens.danger, width: 1.2);
        break;
      case AppStatusType.neutral:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
        border = const BorderSide(color: AppDesignTokens.border);
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : AppDesignTokens.space8,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusSm),
        border: Border.fromBorderSide(border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: isCompact ? 11 : 13, color: fg),
            const SizedBox(width: AppDesignTokens.space4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: isCompact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
