import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/core/localization/locale_provider.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/manager_override_dialog.dart';
import 'package:jazzpos/ui/widgets/numpad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final FocusNode _keyboardFocusNode = FocusNode();
  final StringBuffer _pinBuffer = StringBuffer();
  String? _errorMessage;

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _onNumpadPress('0');
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      _onNumpadPress('1');
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      _onNumpadPress('2');
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      _onNumpadPress('3');
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      _onNumpadPress('4');
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      _onNumpadPress('5');
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      _onNumpadPress('6');
    } else if (key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7) {
      _onNumpadPress('7');
    } else if (key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8) {
      _onNumpadPress('8');
    } else if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      _onNumpadPress('9');
    } else if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _onBackspace();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitUnlock();
    } else if (key == LogicalKeyboardKey.escape) {
      _onClear();
    }
  }

  void _onNumpadPress(String char) {
    if (_pinBuffer.length < 8) {
      setState(() {
        _pinBuffer.write(char);
        _errorMessage = null;
      });

      if (_pinBuffer.length == 4) {
        _submitUnlock();
      }
    }
  }

  void _onBackspace() {
    if (_pinBuffer.isNotEmpty) {
      setState(() {
        final cur = _pinBuffer.toString();
        _pinBuffer.clear();
        _pinBuffer.write(cur.substring(0, cur.length - 1));
        _errorMessage = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _pinBuffer.clear();
      _errorMessage = null;
    });
  }

  Future<void> _submitUnlock() async {
    final loc = context.loc;
    final pin = _pinBuffer.toString();
    if (pin.isEmpty) return;

    final success = await ref.read(authNotifierProvider.notifier).unlock(pin);
    if (!success && mounted) {
      setState(() {
        _pinBuffer.clear();
        _errorMessage = loc.invalidPin;
      });
    }
  }

  Future<void> _managerOverrideUnlock() async {
    final loc = context.loc;
    final manager = await ManagerOverrideDialog.show(
      context,
      actionTitle: loc.managerOverrideUnlockTitle,
    );

    if (manager != null && mounted) {
      // Force unlock via manager
      ref.read(authNotifierProvider.notifier).unlock(manager.pinHash);
      await ref
          .read(authNotifierProvider.notifier)
          .unlock(_pinBuffer.toString());
      ref.read(authNotifierProvider.notifier).logout();
    }
  }

  String _localizedRole(String role, AppLocalizations loc) {
    switch (role.toLowerCase()) {
      case 'owner':
      case 'admin':
        return loc.roleOwner;
      case 'manager':
        return loc.roleManager;
      case 'inventory':
        return loc.roleInventory;
      case 'cashier':
      default:
        return loc.roleCashier;
    }
  }

  Widget _buildLanguageSelector(WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final isAr = currentLocale.languageCode == 'ar';
    final isEn = currentLocale.languageCode == 'en';
    final isFr = currentLocale.languageCode == 'fr';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppDesignTokens.border),
        boxShadow: AppDesignTokens.shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLangButton(ref, 'fr', 'FR', isFr),
          const SizedBox(width: 4),
          _buildLangButton(ref, 'ar', 'عربي', isAr),
          const SizedBox(width: 4),
          _buildLangButton(ref, 'en', 'EN', isEn),
        ],
      ),
    );
  }

  Widget _buildLangButton(
    WidgetRef ref,
    String code,
    String label,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () => ref.read(localeProvider.notifier).setLocale(Locale(code)),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppDesignTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppDesignTokens.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final auth = ref.watch(authNotifierProvider);
    final user = auth.user;

    final roleStr = user != null ? _localizedRole(user.role, loc) : '';

    return Scaffold(
      backgroundColor: AppDesignTokens.canvas,
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: SafeArea(
          child: Stack(
            children: [
              PositionedDirectional(
                top: 24,
                end: 24,
                child: _buildLanguageSelector(ref),
              ),
              Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 440,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusDialog,
                      ),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowLg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Lock Icon Badge
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: AppDesignTokens.warningBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock,
                            color: AppDesignTokens.warningText,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          loc.screenLocked,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          user != null
                              ? loc.activeSession(user.displayName, roleStr)
                              : loc.screenLocked,
                          style: const TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // PIN indicator dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final isFilled = index < _pinBuffer.length;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled
                                    ? AppDesignTokens.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isFilled
                                      ? AppDesignTokens.primary
                                      : AppDesignTokens.border,
                                  width: 2,
                                ),
                              ),
                            );
                          }),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppDesignTokens.danger,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Numpad
                        Numpad(
                          onKeyPress: _onNumpadPress,
                          onBackspace: _onBackspace,
                          onClear: _onClear,
                          showDecimal: false,
                        ),

                        const SizedBox(height: 20),

                        // Actions
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _submitUnlock,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppDesignTokens.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusInput,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.lock_open, size: 20),
                            label: Text(
                              loc.unlockAction.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: () => ref
                                  .read(authNotifierProvider.notifier)
                                  .logout(),
                              icon: const Icon(
                                Icons.logout,
                                size: 16,
                                color: AppDesignTokens.textSecondary,
                              ),
                              label: Text(
                                loc.switchCashier,
                                style: const TextStyle(
                                  color: AppDesignTokens.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _managerOverrideUnlock,
                              icon: const Icon(
                                Icons.admin_panel_settings,
                                size: 16,
                                color: AppDesignTokens.warningText,
                              ),
                              label: Text(
                                loc.managerEmergencyUnlock,
                                style: const TextStyle(
                                  color: AppDesignTokens.warningText,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
