import 'package:flutter/material.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Widget? header;
  final Widget? footer;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDesignTokens.space16),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppDesignTokens.radiusLg,
    this.boxShadow,
    this.onTap,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);

    if (header != null || footer != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignTokens.space16,
                vertical: AppDesignTokens.space12,
              ),
              child: header!,
            ),
            const Divider(color: AppTheme.border, height: 1),
          ],
          Padding(padding: padding, child: child),
          if (footer != null) ...[
            const Divider(color: AppTheme.border, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignTokens.space16,
                vertical: AppDesignTokens.space12,
              ),
              child: footer!,
            ),
          ],
        ],
      );
    }

    final decoration = BoxDecoration(
      color: backgroundColor ?? AppTheme.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor ?? AppTheme.border, width: 1),
      boxShadow: boxShadow ?? AppDesignTokens.shadowSm,
    );

    if (onTap != null) {
      return Container(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onTap,
            child: content,
          ),
        ),
      );
    }

    return Container(decoration: decoration, child: content);
  }
}
