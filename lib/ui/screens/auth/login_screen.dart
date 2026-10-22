import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracepos/core/localization/app_localizations.dart';
import 'package:tracepos/core/localization/locale_provider.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/logging/startup_tracker.dart';
import 'package:tracepos/core/sound/sound_effect_service.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/providers/app_providers.dart';
import 'package:tracepos/providers/auth_provider.dart';
import 'package:tracepos/ui/theme/app_design_tokens.dart';
import 'package:tracepos/ui/widgets/numpad.dart';
import 'package:tracepos/ui/widgets/startup_recovery_widget.dart';
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
  StartupStatus _startupStatus = StartupStatus.initializing;
  bool _isSetupCompleted = false;
  String? _startupError;
  String? _startupErrorDetails;
  String? _errorMessage;
  Timer? _queryTimeoutTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUsers();
    });
  }

  @override
  void dispose() {
    _queryTimeoutTimer?.cancel();
    _clockTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _startupStatus = StartupStatus.initializing;
      _startupError = null;
      _startupErrorDetails = null;
    });

    StartupTracker.instance.startStage('users_loading');
    _queryTimeoutTimer?.cancel();
    try {
      final db = ref.read(databaseProvider);
      final completer = Completer<List<User>>();
      _queryTimeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Le délai de chargement de la base de données a expiré (5 secondes).',
            ),
          );
        }
      });

      (db.select(db.users)..where((tbl) => tbl.isActive.equals(true)))
          .get()
          .then((users) {
            if (!completer.isCompleted) completer.complete(users);
          })
          .catchError((e, st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          });

      final users = await completer.future;
      _queryTimeoutTimer?.cancel();

      final isCompleted = await ref
          .read(posInitializationServiceProvider)
          .isSetupCompleted();

      if (mounted) {
        setState(() {
          _isSetupCompleted = isCompleted;
          _users = users;
          _startupStatus = StartupStatus.ready;
          if (_users.isNotEmpty) {
            _selectedUser = _users.first;
          }
        });

        StartupTracker.instance.endStage('users_loading', success: true);
        StartupTracker.instance.endStage('first_usable_screen', success: true);

        if (!isCompleted && users.isEmpty) {
          _navigateToSetup();
        }
      }
    } catch (e, st) {
      PosLogger.instance.error(
        'Startup',
        'Database query error during user initialization: $e',
        e,
        st,
      );
      StartupTracker.instance.endStage(
        'users_loading',
        success: false,
        error: e.toString(),
      );

      if (mounted) {
        setState(() {
          _startupStatus = StartupStatus.recoverableError;
          _startupError = e is TimeoutException
              ? e.message
              : 'Erreur d\'accès aux données utilisateur : ${e.toString().split('\n').first}';
          _startupErrorDetails = '$e\n\n$st';
        });
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
      SoundEffectService.instance.playSuccess();
      widget.onLoginSuccess();
    } else {
      SoundEffectService.instance.playError();
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
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('0');
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('1');
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('2');
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('3');
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('4');
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('5');
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('6');
    } else if (key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('7');
    } else if (key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('8');
    } else if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      SoundEffectService.instance.playKeyTap();
      _onNumpadPress('9');
    } else if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      SoundEffectService.instance.playBackspace();
      _onBackspace();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitLogin();
    } else if (key == LogicalKeyboardKey.escape) {
      SoundEffectService.instance.playClear();
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

  // ── Language selector ──────────────────────────────────────────────────────
  Widget _buildLanguageSelector(WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final isAr = currentLocale.languageCode == 'ar';
    final isEn = currentLocale.languageCode == 'en';
    final isFr = currentLocale.languageCode == 'fr';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
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

  // ── Left hero panel ────────────────────────────────────────────────────────
  Widget _buildLeftPanel(AppLocalizations loc) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF7F0), Color(0xFFF7FBFF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + brand
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/trace_logo_mark.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.appTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppDesignTokens.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      loc.posAppSubtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Welcome heading
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
            child: Text(
              loc.welcomeTitle,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppDesignTokens.textPrimary,
                height: 1.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
            child: Text(
              loc.posAppSubtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),

          // Feature bullets
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                _buildFeatureBullet(
                  Icons.bolt,
                  'Ventes rapides',
                  'Un encaissement fluide',
                ),
                const SizedBox(height: 12),
                _buildFeatureBullet(
                  Icons.bar_chart,
                  'Suivi en temps réel',
                  'Stocks, ventes et rapports',
                ),
                const SizedBox(height: 12),
                _buildFeatureBullet(
                  Icons.security,
                  'Sécurisé',
                  'Vos données sont protégées',
                ),
              ],
            ),
          ),

          // Boutique photo banner
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                ),
                child: Image.asset(
                  'assets/images/login_banner.jpg',
                  width: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppDesignTokens.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppDesignTokens.primary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Right PIN panel ────────────────────────────────────────────────────────
  Widget _buildRightPanel(AppLocalizations loc) {
    final dayStr = DateFormat('EEE, d MMM yyyy', 'fr_FR').format(_now);
    final timeStr = DateFormat('HH:mm').format(_now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Date & time
          Align(
            alignment: Alignment.topRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dayStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // PIN title
          Text(
            _selectedUser != null
                ? loc.pinForUser(_selectedUser!.displayName)
                : loc.enterPin,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppDesignTokens.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Entrez votre code pour accéder au système',
            style: const TextStyle(
              fontSize: 12,
              color: AppDesignTokens.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // PIN dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isFilled = index < _pinBuffer.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? AppDesignTokens.primary : Colors.transparent,
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
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppDesignTokens.danger,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 16),

          // Numpad
          Numpad(
            onKeyPress: _onNumpadPress,
            onBackspace: _onBackspace,
            onClear: _onClear,
            showDecimal: false,
          ),

          const SizedBox(height: 14),

          // CONNEXION button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _submitLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                ),
              ),
              icon: const Icon(Icons.login, size: 18),
              label: Text(
                loc.loginAction.toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // User switcher (if multiple users)
          if (_users.length > 1) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'ou',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final isSelected = user.id == _selectedUser?.id;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedUser = user;
                        _pinBuffer.clear();
                        _errorMessage = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppDesignTokens.primary.withValues(alpha: 0.08)
                            : AppDesignTokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
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
                            radius: 14,
                            backgroundColor: isSelected
                                ? AppDesignTokens.primary
                                : AppDesignTokens.border,
                            child: Text(
                              user.displayName.isNotEmpty
                                  ? user.displayName.substring(0, 1).toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppDesignTokens.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isSelected
                                        ? AppDesignTokens.primary
                                        : AppDesignTokens.textPrimary,
                                  ),
                                ),
                                Text(
                                  _localizedRole(user.role, loc).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: AppDesignTokens.primary,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Setup wizard link
          if (!_isSetupCompleted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _navigateToSetup,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppDesignTokens.border),
                  foregroundColor: AppDesignTokens.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined, size: 15),
                label: Text(
                  loc.setupWizardButton,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_startupStatus == StartupStatus.initializing) {
      return const Scaffold(
        backgroundColor: AppDesignTokens.canvas,
        body: Center(
          child: CircularProgressIndicator(color: AppDesignTokens.primary),
        ),
      );
    }

    if (_startupStatus == StartupStatus.recoverableError ||
        _startupStatus == StartupStatus.fatalError) {
      return StartupRecoveryWidget(
        errorMessage: _startupError,
        technicalDetails: _startupErrorDetails,
        onRetry: _loadUsers,
        onClose: () => exit(0),
      );
    }

    final loc = context.loc;

    // ── No users configured ──────────────────────────────────────────────────
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
                  Image.asset(
                    'assets/images/trace_logo_mark.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
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
                    style: const TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _navigateToSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppDesignTokens.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDesignTokens.radiusInput),
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

    // ── Main login layout ────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: SafeArea(
          child: Stack(
            children: [
              // Language selector top-right
              PositionedDirectional(
                top: 20,
                end: 20,
                child: _buildLanguageSelector(ref),
              ),

              // Centered card
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Container(
                    width: 1032,
                    height: 696,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 40,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Left hero panel (55%)
                        Expanded(
                          flex: 55,
                          child: _buildLeftPanel(loc),
                        ),

                        // Divider
                        Container(
                          width: 1,
                          color: AppDesignTokens.border,
                        ),

                        // Right PIN panel (45%)
                        Expanded(
                          flex: 45,
                          child: SingleChildScrollView(
                            child: _buildRightPanel(loc),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom status bar
              PositionedDirectional(
                bottom: 12,
                start: 20,
                end: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Trace POS version
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/trace_logo_mark.png',
                          width: 16,
                          height: 16,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Trace POS  v1.0.0',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),

                    // Center: Virex logo
                    Image.asset(
                      'assets/images/virex_logo.png',
                      height: 22,
                      fit: BoxFit.contain,
                    ),

                    // Right: System status
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppDesignTokens.success,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Système opérationnel',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppDesignTokens.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
