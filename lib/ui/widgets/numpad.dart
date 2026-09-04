import 'package:flutter/material.dart';

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
                child: _buildKey('C', onClear, color: Colors.orange.shade800),
              ),
            const SizedBox(width: 8),
            Expanded(child: _buildKey('0', () => onKeyPress('0'))),
            const SizedBox(width: 8),
            Expanded(child: _buildKey('00', () => onKeyPress('00'))),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKey('⌫', onBackspace, color: Colors.red.shade900),
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

  Widget _buildKey(String label, VoidCallback onTap, {Color? color}) {
    return SizedBox(
      height: 56, // Large touch target for POS terminal
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF334155),
          foregroundColor: Colors.white,
          elevation: 2,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
