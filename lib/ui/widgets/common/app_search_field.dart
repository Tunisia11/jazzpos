import 'package:flutter/material.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_theme.dart';

class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final double height;

  const AppSearchField({
    super.key,
    required this.controller,
    this.hintText = 'Rechercher...',
    this.onChanged,
    this.onClear,
    this.focusNode,
    this.height = AppDesignTokens.buttonHeightSm + 4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppTheme.textMuted,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      color: AppTheme.textSecondary,
                      splashRadius: 14,
                      onPressed: () {
                        controller.clear();
                        if (onClear != null) {
                          onClear!();
                        } else if (onChanged != null) {
                          onChanged!('');
                        }
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignTokens.space12,
                vertical: 0,
              ),
            ),
          );
        },
      ),
    );
  }
}
