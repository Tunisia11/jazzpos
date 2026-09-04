import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/providers/auth_provider.dart';
import 'package:jazzpos/ui/theme/app_theme.dart';
import 'package:jazzpos/ui/widgets/manager_override_dialog.dart';
import 'package:jazzpos/ui/widgets/numpad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final StringBuffer _pinBuffer = StringBuffer();
  String? _errorMessage;

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
    final pin = _pinBuffer.toString();
    if (pin.isEmpty) return;

    final success = await ref.read(authNotifierProvider.notifier).unlock(pin);
    if (!success) {
      setState(() {
        _pinBuffer.clear();
        _errorMessage = 'Code PIN incorrect';
      });
    }
  }

  Future<void> _managerOverrideUnlock() async {
    final manager = await ManagerOverrideDialog.show(
      context,
      actionTitle: 'Déverrouillage d\'urgence de la caisse',
    );

    if (manager != null && mounted) {
      // Force unlock via manager
      ref.read(authNotifierProvider.notifier).unlock(manager.pinHash); // Or direct session state unlock
      // But simpler: just unlock the session
      await ref.read(authNotifierProvider.notifier).unlock(_pinBuffer.toString());
      // If cashier PIN is still unknown, log out to let manager login
      ref.read(authNotifierProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lock Icon Badge
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock, color: AppTheme.warning, size: 36),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Caisse Verrouillée',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Session active : ${user?.displayName ?? "Caissier"} (${user?.role.toUpperCase() ?? ""})',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
                          color: isFilled ? AppTheme.primaryLight : Colors.transparent,
                          border: Border.all(
                            color: isFilled ? AppTheme.primaryLight : AppTheme.border,
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
                      style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.bold),
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
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.lock_open, size: 20),
                      label: const Text('DÉVERROUILLER', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                        icon: const Icon(Icons.logout, size: 16, color: AppTheme.textSecondary),
                        label: const Text('Changer de caissier', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: _managerOverrideUnlock,
                        icon: const Icon(Icons.admin_panel_settings, size: 16, color: AppTheme.warning),
                        label: const Text('Déblocage Manager', style: TextStyle(color: AppTheme.warning, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
