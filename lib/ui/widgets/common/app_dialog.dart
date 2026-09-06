import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations_delegate.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';
import 'app_button.dart';

class AppDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String? cancelLabel;
  final String confirmLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool isDestructive;
  final bool isLoading;
  final double maxWidth;
  final IconData? icon;

  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelLabel,
    required this.confirmLabel,
    this.onCancel,
    required this.onConfirm,
    this.isDestructive = false,
    this.isLoading = false,
    this.maxWidth = 480,
    this.icon,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    String? cancelLabel,
    required String confirmLabel,
    VoidCallback? onCancel,
    required VoidCallback onConfirm,
    bool isDestructive = false,
    bool isLoading = false,
    double maxWidth = 480,
    IconData? icon,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        content: content,
        cancelLabel: cancelLabel ?? ctx.loc.cancel,
        confirmLabel: confirmLabel,
        onCancel: onCancel ?? () => Navigator.of(ctx).pop(),
        onConfirm: onConfirm,
        isDestructive: isDestructive,
        isLoading: isLoading,
        maxWidth: maxWidth,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusXl),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppDesignTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 22,
                      color: isDestructive ? AppTheme.danger : AppTheme.primary,
                    ),
                    const SizedBox(width: AppDesignTokens.space12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: AppDesignTokens.space16),

              // Content
              Flexible(child: content),
              const SizedBox(height: AppDesignTokens.space24),

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (cancelLabel != null) ...[
                    AppButton(
                      label: cancelLabel!,
                      variant: AppButtonVariant.outline,
                      onPressed: isLoading
                          ? null
                          : (onCancel ?? () => Navigator.of(context).pop()),
                    ),
                    const SizedBox(width: AppDesignTokens.space12),
                  ],
                  AppButton(
                    label: confirmLabel,
                    variant: isDestructive
                        ? AppButtonVariant.danger
                        : AppButtonVariant.primary,
                    isLoading: isLoading,
                    onPressed: onConfirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
