import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'numpad.dart';

/// Modal dialog requesting manager authorization PIN without logging out the cashier
class ManagerOverrideDialog extends ConsumerStatefulWidget {
  final String actionTitle;
  final String? reason;

  const ManagerOverrideDialog({
    super.key,
    required this.actionTitle,
    this.reason,
  });

  static Future<User?> show(BuildContext context, {required String actionTitle, String? reason}) {
    return showDialog<User>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManagerOverrideDialog(actionTitle: actionTitle, reason: reason),
    );
  }

  @override
  ConsumerState<ManagerOverrideDialog> createState() => _ManagerOverrideDialogState();
}

class _ManagerOverrideDialogState extends ConsumerState<ManagerOverrideDialog> {
  final StringBuffer _pinBuffer = StringBuffer();
  String? _error;
  bool _isLoading = false;

  void _onKeyPress(String digit) {
    if (_pinBuffer.length < 6) {
      setState(() {
        _pinBuffer.write(digit);
        _error = null;
      });
      if (_pinBuffer.length >= 4) {
        _attemptOverride();
      }
    }
  }

  void _onBackspace() {
    if (_pinBuffer.isNotEmpty) {
      setState(() {
        final current = _pinBuffer.toString();
        _pinBuffer.clear();
        _pinBuffer.write(current.substring(0, current.length - 1));
        _error = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _pinBuffer.clear();
      _error = null;
    });
  }

  Future<void> _attemptOverride() async {
    final pin = _pinBuffer.toString();
    if (pin.length < 4) return;

    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final manager = await authService.verifyManagerOverride(pin);
      if (mounted) {
        Navigator.of(context).pop(manager);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Code PIN responsable invalide';
          _pinBuffer.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinLength = _pinBuffer.length;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, color: AppTheme.warning, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Autorisation Responsable Requise',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.actionTitle,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (widget.reason != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.reason!,
                style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),

            // PIN Indicator Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final filled = index < pinLength;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.primary : const Color(0xFF334155),
                    border: Border.all(color: AppTheme.border, width: 1.5),
                  ),
                );
              }),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],

            const SizedBox(height: 20),

            // Touch Numpad
            Numpad(
              onKeyPress: _onKeyPress,
              onBackspace: _onBackspace,
              onClear: _onClear,
              showDecimal: false,
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
