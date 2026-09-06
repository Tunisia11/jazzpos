import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations_delegate.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? searchBar;
  final VoidCallback? onBack;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.searchBar,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = context.isRtl;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignTokens.space20,
        vertical: AppDesignTokens.space12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              icon: Icon(
                isRtl ? Icons.arrow_forward : Icons.arrow_back,
                color: AppTheme.textPrimary,
              ),
              onPressed: onBack,
              tooltip: context.loc.back,
            ),
            const SizedBox(width: AppDesignTokens.space8),
          ],
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(AppDesignTokens.space8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF), // Soft primary blue tint
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Icon(icon, size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: AppDesignTokens.space12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (searchBar != null) ...[
            const SizedBox(width: AppDesignTokens.space16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: searchBar!,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppDesignTokens.space16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppDesignTokens.space8,
                      ),
                      child: a,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
