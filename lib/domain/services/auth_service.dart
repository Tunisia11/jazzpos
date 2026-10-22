import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/core/constants/permissions.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/core/logging/pos_logger.dart';
import 'package:tracepos/core/utils/id_generator.dart';
import 'package:tracepos/core/utils/password_hasher.dart';
import 'package:tracepos/data/database/app_database.dart';

class UserSession {
  final User user;
  final Set<String> permissions;

  const UserSession({required this.user, required this.permissions});

  bool hasPermission(String permission) {
    if (user.role == AppRoles.owner) return true;
    return permissions.contains(permission);
  }
}

/// Escalating lockout after repeated wrong PINs (in memory, per target).
class _AttemptTracker {
  static const int freeAttempts = 5;
  int failures = 0;
  DateTime? lockedUntil;
}

class AuthService {
  final AppDatabase db;
  final DateTime Function() _clock;
  UserSession? _currentSession;
  final Map<String, _AttemptTracker> _attempts = {};

  AuthService(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const String _lockoutSettingKey = 'auth_lockout_state';
  bool _attemptsLoaded = false;

  /// Lockout state is persisted so restarting the app does not reset it.
  Future<void> _ensureLoaded() async {
    if (_attemptsLoaded) return;
    _attemptsLoaded = true;
    try {
      final row = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(_lockoutSettingKey)))
          .getSingleOrNull();
      if (row == null) return;
      final map = jsonDecode(row.value) as Map<String, dynamic>;
      for (final e in map.entries) {
        final v = e.value as Map<String, dynamic>;
        _attempts[e.key] = _AttemptTracker()
          ..failures = v['f'] as int? ?? 0
          ..lockedUntil = DateTime.tryParse(v['u'] as String? ?? '');
      }
    } catch (e) {
      PosLogger.instance.warning('Auth', 'Could not load lockout state: $e');
    }
  }

  Future<void> _persistAttempts() async {
    try {
      final now = _clock();
      final map = <String, dynamic>{
        for (final e in _attempts.entries)
          if (e.value.failures > 0)
            e.key: {
              'f': e.value.failures,
              if (e.value.lockedUntil != null)
                'u': e.value.lockedUntil!.toIso8601String(),
            },
      };
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _lockoutSettingKey,
              value: jsonEncode(map),
              updatedAt: now,
            ),
          );
    } catch (e) {
      PosLogger.instance.warning('Auth', 'Could not save lockout state: $e');
    }
  }

  /// Throws if [key] is locked out; otherwise returns normally.
  Future<void> _ensureNotLocked(String key) async {
    await _ensureLoaded();
    final until = _attempts[key]?.lockedUntil;
    if (until != null && _clock().isBefore(until)) {
      final secs = until.difference(_clock()).inSeconds + 1;
      throw AuthException(
        'Too many failed attempts. Try again in $secs seconds.',
      );
    }
  }

  Future<void> _recordFailure(String key) async {
    await _ensureLoaded();
    final t = _attempts.putIfAbsent(key, _AttemptTracker.new);
    t.failures++;
    if (t.failures >= _AttemptTracker.freeAttempts) {
      // 30s, 60s, 120s ... capped at 15 minutes.
      final steps = t.failures - _AttemptTracker.freeAttempts;
      final secs = (30 * (1 << (steps > 5 ? 5 : steps))).clamp(30, 900);
      t.lockedUntil = _clock().add(Duration(seconds: secs));
    }
    await _persistAttempts();
  }

  Future<void> _clearFailures(String key) async {
    await _ensureLoaded();
    if (_attempts.remove(key) != null) await _persistAttempts();
  }

  /// Re-hash a PIN with the current scheme after a successful verification.
  Future<User> _upgradeHashIfNeeded(User user, String pin) async {
    if (!PasswordHasher.needsRehash(user.pinHash)) return user;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPin(pin, salt);
    await (db.update(db.users)..where((t) => t.id.equals(user.id))).write(
      UsersCompanion(pinHash: Value(hash), pinSalt: Value(salt)),
    );
    return user.copyWith(pinHash: hash, pinSalt: salt);
  }

  UserSession? get currentSession => _currentSession;
  bool get isAuthenticated => _currentSession != null;

  /// Authenticate user via username and PIN/password
  Future<UserSession> login({
    required String username,
    required String pin,
  }) async {
    final lockKey = 'login:${username.trim().toLowerCase()}';
    await _ensureNotLocked(lockKey);

    final found =
        await (db.select(db.users)..where(
              (tbl) =>
                  tbl.username.equals(username.trim()) &
                  tbl.isActive.equals(true),
            ))
            .getSingleOrNull();

    if (found == null) {
      await _recordFailure(lockKey);
      throw const AuthException('Invalid username or PIN');
    }

    final isValid = PasswordHasher.verifyPin(
      pin: pin,
      saltHex: found.pinSalt,
      expectedHashHex: found.pinHash,
    );

    if (!isValid) {
      await _recordFailure(lockKey);
      PosLogger.instance.warning(
        'Auth',
        'Failed login attempt for user: $username',
      );
      throw const AuthException('Invalid username or PIN');
    }
    await _clearFailures(lockKey);
    final user = await _upgradeHashIfNeeded(found, pin);

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
    final lockKey = 'unlock:${user.id}';
    await _ensureNotLocked(lockKey);
    final ok = PasswordHasher.verifyPin(
      pin: pin,
      saltHex: user.pinSalt,
      expectedHashHex: user.pinHash,
    );
    if (ok) {
      await _clearFailures(lockKey);
    } else {
      await _recordFailure(lockKey);
    }
    return ok;
  }

  /// Manager override verification without logging out cashier
  /// Returns the manager's User record if valid and authorized
  Future<User> verifyManagerOverride(
    String managerPin, {
    String requiredPermission = '',
  }) async {
    const lockKey = 'manager-override';
    await _ensureNotLocked(lockKey);
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
        if (requiredPermission.isNotEmpty) {
          final storedPermissions = await (db.select(
            db.userPermissions,
          )..where((table) => table.userId.equals(mgr.id))).get();
          final permissions = AppRoles.defaultPermissionsForRole(mgr.role)
            ..addAll(storedPermissions.map((row) => row.permission));
          if (mgr.role != AppRoles.owner &&
              !permissions.contains(requiredPermission)) {
            continue;
          }
        }
        await _clearFailures(lockKey);
        PosLogger.instance.info(
          'Auth',
          'Manager override approved by: ${mgr.displayName} (${mgr.role})',
        );
        return _upgradeHashIfNeeded(mgr, managerPin);
      }
    }

    await _recordFailure(lockKey);
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
    final setupSetting = await (db.select(db.appSettings)
          ..where((tbl) => tbl.key.equals('setup_completed')))
        .getSingleOrNull();
    final isSetupCompleted = setupSetting?.value == 'true';

    if (isSetupCompleted) {
      if (_currentSession == null ||
          !_currentSession!.hasPermission(AppPermissions.manageUsers)) {
        throw const AuthException(
          'User management permission is required to create an account.',
        );
      }
    } else {
      // During initial bootstrap (before setup completion):
      // An administrative user can be provisioned. If an administrative user
      // already exists, unauthenticated creation is blocked.
      final existingAdmins = await (db.select(db.users)
            ..where((tbl) =>
                tbl.role.equals(AppRoles.owner) |
                tbl.role.equals(AppRoles.manager)))
          .get();
      if (existingAdmins.isNotEmpty &&
          (_currentSession == null ||
              !_currentSession!.hasPermission(AppPermissions.manageUsers))) {
        throw const AuthException(
          'User management permission is required to create an account.',
        );
      }
    }
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

  /// Retrieve all users ordered by username
  Future<List<User>> getAllUsers() async {
    return await (db.select(db.users)
          ..orderBy([(t) => OrderingTerm.asc(t.username)]))
        .get();
  }

  /// Update user profile details (display name, role, active status)
  Future<void> updateUser({
    required String userId,
    required String displayName,
    required String role,
    bool? isActive,
  }) async {
    final companion = UsersCompanion(
      displayName: Value(displayName.trim()),
      role: Value(role),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    );
    await (db.update(db.users)..where((tbl) => tbl.id.equals(userId)))
        .write(companion);
    PosLogger.instance.info('Auth', 'Updated user $userId: $displayName ($role)');
  }

  /// Reset or change a user's PIN with fresh salt and hash
  Future<void> resetUserPin({
    required String userId,
    required String newPin,
  }) async {
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPin(newPin, salt);
    final companion = UsersCompanion(
      pinHash: Value(hash),
      pinSalt: Value(salt),
      updatedAt: Value(DateTime.now()),
    );
    await (db.update(db.users)..where((tbl) => tbl.id.equals(userId)))
        .write(companion);
    PosLogger.instance.info('Auth', 'Reset PIN for user $userId');
  }

  /// Toggle user active/inactive status
  Future<void> toggleUserActive(String userId, bool isActive) async {
    final companion = UsersCompanion(
      isActive: Value(isActive),
      updatedAt: Value(DateTime.now()),
    );
    await (db.update(db.users)..where((tbl) => tbl.id.equals(userId)))
        .write(companion);
    PosLogger.instance.info('Auth', 'Toggled active status for user $userId to $isActive');
  }

  /// Delete a user and associated permissions
  Future<void> deleteUser(String userId) async {
    await db.transaction(() async {
      await (db.delete(db.userPermissions)
            ..where((tbl) => tbl.userId.equals(userId)))
          .go();
      await (db.delete(db.users)..where((tbl) => tbl.id.equals(userId))).go();
    });
    PosLogger.instance.info('Auth', 'Deleted user $userId');
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
