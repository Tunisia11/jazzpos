import 'package:flutter/material.dart';
import '../theme/app_design_tokens.dart';

class Numpad extends StatelessWidget {
  final ValueChanged<String> onKeyPress;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;
  final bool showDecimal;

  const Numpad({
    super.key,
    required this.onKeyPress,
    required this.onBackspace,
    required this.onClear,
    this.onSubmit,
    this.showDecimal = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(['1', '2', '3']),
        const SizedBox(height: 8),
        _buildRow(['4', '5', '6']),
        const SizedBox(height: 8),
        _buildRow(['7', '8', '9']),
        const SizedBox(height: 8),
        Row(
          children: [
            if (showDecimal)
              Expanded(child: _buildKey('.', () => onKeyPress('.')))
            else
              Expanded(
                child: _buildKey(
                  'C',
                  onClear,
                  backgroundColor: const Color(0xFFFFFBEB),
                  textColor: const Color(0xFFB45309),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(child: _buildKey('0', () => onKeyPress('0'))),
            const SizedBox(width: 8),
            Expanded(child: _buildKey('00', () => onKeyPress('00'))),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKey(
                '⌫',
                onBackspace,
                backgroundColor: const Color(0xFFFEF2F2),
                textColor: const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      children: keys.map((k) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildKey(k, () => onKeyPress(k)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(
    String label,
    VoidCallback onTap, {
    Color? backgroundColor,
    Color? textColor,
  }) {
    final bg = backgroundColor ?? Colors.white;
    final fg = textColor ?? AppDesignTokens.textPrimary;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusMd),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
