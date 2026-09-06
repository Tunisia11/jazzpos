import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/core/localization/app_localizations.dart';
import 'package:jazzpos/core/localization/locale_provider.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/providers/app_providers.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';
import 'package:jazzpos/ui/widgets/numpad.dart';
import 'setup_wizard_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final FocusNode _keyboardFocusNode = FocusNode();
  List<User> _users = [];
  User? _selectedUser;
  final StringBuffer _pinBuffer = StringBuffer();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final users = await (db.select(
      db.users,
    )..where((tbl) => tbl.isActive.equals(true))).get();

    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
        if (_users.isNotEmpty) {
          _selectedUser = _users.first;
        }
      });

      // If no users exist at all, offer setup wizard
      if (users.isEmpty) {
        _navigateToSetup();
      }
    }
  }

  void _navigateToSetup() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const SetupWizardScreen()));
    _loadUsers();
  }

  void _onNumpadPress(String char) {
    if (_pinBuffer.length < 8) {
      setState(() {
        _pinBuffer.write(char);
        _errorMessage = null;
      });

      // Auto submit if 4 digits
      if (_pinBuffer.length == 4) {
        _submitLogin();
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

  Future<void> _submitLogin() async {
    final loc = context.loc;
    if (_selectedUser == null) {
      setState(() => _errorMessage = loc.selectUserRequired);
      return;
    }

    final pin = _pinBuffer.toString();
    if (pin.isEmpty) {
      setState(() => _errorMessage = loc.enterPinRequired);
      return;
    }

    final success = await ref
        .read(authNotifierProvider.notifier)
        .login(_selectedUser!.username, pin);

    if (success) {
      widget.onLoginSuccess();
    } else {
      if (mounted) {
        setState(() {
          _pinBuffer.clear();
          _errorMessage = loc.invalidPin;
        });
      }
    }
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
      _submitLogin();
    } else if (key == LogicalKeyboardKey.escape) {
      _onClear();
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

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        body: Center(
          child: CircularProgressIndicator(color: AppDesignTokens.primary),
        ),
      );
    }

    if (_users.isEmpty) {
      return Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        body: Stack(
          children: [
            PositionedDirectional(
              top: 24,
              end: 24,
              child: _buildLanguageSelector(ref),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storefront,
                    size: 80,
                    color: AppDesignTokens.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.welcomeTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.noUsersConfigured,
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _navigateToSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppDesignTokens.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignTokens.radiusInput,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.settings, color: Colors.white),
                    label: Text(
                      loc.launchSetupWizard,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
                    width: 860,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppDesignTokens.surface,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusDialog,
                      ),
                      border: Border.all(color: AppDesignTokens.border),
                      boxShadow: AppDesignTokens.shadowLg,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Side: Store Brand & User Selection
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppDesignTokens.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.checkroom,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'JAZZ POS',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: AppDesignTokens.textPrimary,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        Text(
                                          loc.posAppSubtitle,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppDesignTokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '${loc.selectUser} :',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppDesignTokens.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Users Grid
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 320,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _users.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final user = _users[index];
                                    final isSelected =
                                        user.id == _selectedUser?.id;

                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedUser = user;
                                          _pinBuffer.clear();
                                          _errorMessage = null;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(
                                        AppDesignTokens.radiusInput,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppDesignTokens.primary
                                                    .withValues(alpha: 0.08)
                                              : AppDesignTokens.surface,
                                          borderRadius: BorderRadius.circular(
                                            AppDesignTokens.radiusInput,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppDesignTokens.primary
                                                : AppDesignTokens.border,
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: isSelected
                                                  ? AppDesignTokens.primary
                                                  : AppDesignTokens
                                                        .surfaceElevated,
                                              child: Text(
                                                user.displayName.isNotEmpty
                                                    ? user.displayName
                                                          .substring(0, 1)
                                                          .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : AppDesignTokens
                                                            .textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    user.displayName,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: isSelected
                                                          ? AppDesignTokens
                                                                .primary
                                                          : AppDesignTokens
                                                                .textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    _localizedRole(
                                                      user.role,
                                                      loc,
                                                    ).toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: AppDesignTokens
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              const Icon(
                                                Icons.check_circle,
                                                color: AppDesignTokens.primary,
                                                size: 20,
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _navigateToSetup,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppDesignTokens.border,
                                  ),
                                  foregroundColor:
                                      AppDesignTokens.textSecondary,
                                  minimumSize: const Size(double.infinity, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDesignTokens.radiusInput,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  loc.setupWizardButton,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 32),
                        const VerticalDivider(
                          color: AppDesignTokens.border,
                          width: 1,
                        ),
                        const SizedBox(width: 32),

                        // Right Side: PIN Entry & Numpad
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              Text(
                                _selectedUser != null
                                    ? loc.pinForUser(_selectedUser!.displayName)
                                    : loc.enterPin,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppDesignTokens.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),

                              // PIN Indicator Dots
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(4, (index) {
                                  final isFilled = index < _pinBuffer.length;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
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
                                  textAlign: TextAlign.center,
                                ),
                              ],

                              const SizedBox(height: 20),

                              // Numpad
                              Numpad(
                                onKeyPress: _onNumpadPress,
                                onBackspace: _onBackspace,
                                onClear: _onClear,
                                showDecimal: false,
                              ),

                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _submitLogin,
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
                                  icon: const Icon(Icons.login, size: 20),
                                  label: Text(
                                    loc.loginAction,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
