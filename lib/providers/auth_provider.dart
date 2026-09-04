import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/auth_service.dart';
import 'app_providers.dart';

class AuthState {
  final UserSession? session;
  final bool isLocked;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.session,
    this.isLocked = false,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isAuthenticated => session != null;
  User? get user => session?.user;

  bool hasPermission(String permission) {
    if (session == null) return false;
    return session!.hasPermission(permission);
  }

  AuthState copyWith({
    UserSession? session,
    bool? isLocked,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      session: session ?? this.session,
      isLocked: isLocked ?? this.isLocked,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService authService;

  AuthNotifier(this.authService) : super(const AuthState());

  Future<bool> login(String username, String pin) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final session = await authService.login(username: username, pin: pin);
      state = state.copyWith(
        session: session,
        isLocked: false,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void lock() {
    if (state.isAuthenticated) {
      state = state.copyWith(isLocked: true);
    }
  }

  Future<bool> unlock(String pin) async {
    final ok = await authService.unlockWithPin(pin);
    if (ok) {
      state = state.copyWith(isLocked: false);
      return true;
    }
    return false;
  }

  void logout() {
    authService.logout();
    state = const AuthState();
  }

  Future<User?> verifyManagerOverride(String managerPin) async {
    try {
      return await authService.verifyManagerOverride(managerPin);
    } catch (_) {
      return null;
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  return AuthNotifier(ref.watch(authServiceProvider));
});
