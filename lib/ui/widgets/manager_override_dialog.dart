import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'numpad.dart';

/// Modal dialog requesting manager authorization PIN without logging out the cashier
class ManagerOverrideDialog extends ConsumerStatefulWidget {
  final String actionTitle;
  final String? reason;
  final String requiredPermission;

  const ManagerOverrideDialog({
    super.key,
    required this.actionTitle,
    this.reason,
    this.requiredPermission = '',
  });

  static Future<User?> show(
    BuildContext context, {
    required String actionTitle,
    String? reason,
    String requiredPermission = '',
  }) {
    return showDialog<User>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManagerOverrideDialog(
        actionTitle: actionTitle,
        reason: reason,
        requiredPermission: requiredPermission,
      ),
    );
  }

  @override
  ConsumerState<ManagerOverrideDialog> createState() =>
      _ManagerOverrideDialogState();
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
    final loc = context.loc;
    final pin = _pinBuffer.toString();
    if (pin.length < 4) return;

    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final manager = await authService.verifyManagerOverride(
        pin,
        requiredPermission: widget.requiredPermission,
      );
      if (mounted) {
        Navigator.of(context).pop(manager);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = loc.managerPinInvalid;
          _pinBuffer.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final pinLength = _pinBuffer.length;

    return Dialog(
      backgroundColor: AppDesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusDialog),
          border: Border.all(color: AppDesignTokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppDesignTokens.warningBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppDesignTokens.warningText,
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.managerOverrideTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppDesignTokens.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.actionTitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppDesignTokens.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.reason != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.reason!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.warningText,
                  fontWeight: FontWeight.w600,
                ),
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
                    color: filled
                        ? AppDesignTokens.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: filled
                          ? AppDesignTokens.primary
                          : AppDesignTokens.border,
                      width: 1.5,
                    ),
                  ),
                );
              }),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppDesignTokens.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
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
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppDesignTokens.textSecondary,
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: AppDesignTokens.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusInput,
                        ),
                      ),
                    ),
                    child: Text(loc.cancel),
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
