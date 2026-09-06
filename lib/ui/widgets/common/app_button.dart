import 'package:flutter/material.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

enum AppButtonVariant { primary, cta, success, danger, outline, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final String? shortcutHint;
  final String? tooltip;
  final double height;
  final EdgeInsetsGeometry? padding;
  final bool isExpanded;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.shortcutHint,
    this.tooltip,
    this.height = AppDesignTokens.buttonHeightMd,
    this.padding,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = AppTheme.primary;
        fg = Colors.white;
        break;
      case AppButtonVariant.cta:
        bg = AppTheme.accentOrange;
        fg = Colors.white;
        break;
      case AppButtonVariant.success:
        bg = AppTheme.success;
        fg = Colors.white;
        break;
      case AppButtonVariant.danger:
        bg = AppTheme.danger;
        fg = Colors.white;
        break;
      case AppButtonVariant.outline:
        bg = Colors.white;
        fg = AppTheme.textPrimary;
        border = const BorderSide(color: AppTheme.border, width: 1);
        break;
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppTheme.textSecondary;
        break;
    }

    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget content = Row(
      mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: AppDesignTokens.space8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: AppDesignTokens.space8),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (shortcutHint != null) ...[
          const SizedBox(width: AppDesignTokens.space8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color:
                  (variant == AppButtonVariant.outline ||
                      variant == AppButtonVariant.ghost)
                  ? const Color(0xFFF3F4F6)
                  : Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: (variant == AppButtonVariant.outline)
                  ? Border.all(color: AppTheme.border)
                  : null,
            ),
            child: Text(
              shortcutHint!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color:
                    (variant == AppButtonVariant.outline ||
                        variant == AppButtonVariant.ghost)
                    ? AppTheme.textSecondary
                    : fg.withValues(alpha: 0.9),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );

    Widget button = SizedBox(
      height: height,
      width: isExpanded ? double.infinity : null,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.4),
          disabledForegroundColor: fg.withValues(alpha: 0.4),
          padding:
              padding ??
              const EdgeInsets.symmetric(
                horizontal: AppDesignTokens.space16,
                vertical: AppDesignTokens.space8,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
            side: border,
          ),
          elevation: 0,
        ),
        onPressed: effectiveOnPressed,
        child: content,
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
