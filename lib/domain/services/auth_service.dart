import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/logging/pos_logger.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/core/utils/password_hasher.dart';
import 'package:jazzpos/data/database/app_database.dart';

class UserSession {
  final User user;
  final Set<String> permissions;

  const UserSession({required this.user, required this.permissions});

  bool hasPermission(String permission) {
    if (user.role == AppRoles.owner) return true;
    return permissions.contains(permission);
  }
}

class AuthService {
  final AppDatabase db;
  UserSession? _currentSession;

  AuthService(this.db);

  UserSession? get currentSession => _currentSession;
  bool get isAuthenticated => _currentSession != null;

  /// Authenticate user via username and PIN/password
  Future<UserSession> login({
    required String username,
    required String pin,
  }) async {
    final user =
        await (db.select(db.users)..where(
              (tbl) =>
                  tbl.username.equals(username.trim()) &
                  tbl.isActive.equals(true),
            ))
            .getSingleOrNull();

    if (user == null) {
      throw const AuthException('Invalid username or PIN');
    }

    final isValid = PasswordHasher.verifyPin(
      pin: pin,
      saltHex: user.pinSalt,
      expectedHashHex: user.pinHash,
    );

    if (!isValid) {
      PosLogger.instance.warning(
        'Auth',
        'Failed login attempt for user: $username',
      );
      throw const AuthException('Invalid username or PIN');
    }

    // Load permissions
    final permRows = await (db.select(
      db.userPermissions,
    )..where((tbl) => tbl.userId.equals(user.id))).get();
    final permissions = permRows.map((r) => r.permission).toSet();
    // Also include role default permissions
    permissions.addAll(AppRoles.defaultPermissionsForRole(user.role));

    _currentSession = UserSession(user: user, permissions: permissions);
    PosLogger.instance.info(
      'Auth',
      'User logged in: ${user.username} (${user.role})',
    );
    return _currentSession!;
  }

  /// Fast unlock using PIN for the currently locked user session
  Future<bool> unlockWithPin(String pin) async {
    if (_currentSession == null) return false;
    final user = _currentSession!.user;
    return PasswordHasher.verifyPin(
      pin: pin,
      saltHex: user.pinSalt,
      expectedHashHex: user.pinHash,
    );
  }

  /// Manager override verification without logging out cashier
  /// Returns the manager's User record if valid and authorized
  Future<User> verifyManagerOverride(
    String managerPin, {
    String requiredPermission = '',
  }) async {
    final managers =
        await (db.select(db.users)..where(
              (tbl) =>
                  (tbl.role.equals(AppRoles.owner) |
                      tbl.role.equals(AppRoles.manager)) &
                  tbl.isActive.equals(true),
            ))
            .get();

    for (final mgr in managers) {
      final isValid = PasswordHasher.verifyPin(
        pin: managerPin,
        saltHex: mgr.pinSalt,
        expectedHashHex: mgr.pinHash,
      );
      if (isValid) {
        PosLogger.instance.info(
          'Auth',
          'Manager override approved by: ${mgr.displayName} (${mgr.role})',
        );
        return mgr;
      }
    }

    throw const AuthException(
      'Invalid Manager PIN. Override authorization denied.',
    );
  }

  /// Create a new user with secure salted hash
  Future<String> createUser({
    required String username,
    required String displayName,
    required String role,
    required String pin,
    Set<String>? customPermissions,
  }) async {
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPin(pin, salt);
    final userId = IdGenerator.uuid();
    final now = DateTime.now();

    await db.transaction(() async {
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: userId,
              username: username.trim(),
              displayName: displayName.trim(),
              role: role,
              pinHash: hash,
              pinSalt: salt,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final perms =
          customPermissions ?? AppRoles.defaultPermissionsForRole(role);
      for (final p in perms) {
        await db
            .into(db.userPermissions)
            .insert(
              UserPermissionsCompanion.insert(
                id: IdGenerator.uuid(),
                userId: userId,
                permission: p,
              ),
            );
      }
    });

    PosLogger.instance.info('Auth', 'Created user: $username with role: $role');
    return userId;
  }

  void logout() {
    if (_currentSession != null) {
      PosLogger.instance.info(
        'Auth',
        'User logged out: ${_currentSession!.user.username}',
      );
    }
    _currentSession = null;
  }
}
