import 'package:drift/drift.dart';
import 'package:jazzpos/core/constants/roles.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/data/database/app_database.dart';

/// Enforces authorization at the business-service boundary.
///
/// UI visibility remains useful for usability, but callers cannot authorize a
/// privileged operation merely by supplying an arbitrary user identifier.
class PermissionGuard {
  const PermissionGuard._();

  static Future<User> requireActiveUser(AppDatabase db, String userId) async {
    final user =
        await (db.select(db.users)..where(
              (table) => table.id.equals(userId) & table.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (user == null) {
      throw const AuthException('Active user authorization is required.');
    }
    return user;
  }

  static Future<User> requirePermission(
    AppDatabase db,
    String userId,
    String permission,
  ) async {
    final user = await requireActiveUser(db, userId);
    if (user.role == AppRoles.owner ||
        AppRoles.defaultPermissionsForRole(user.role).contains(permission)) {
      return user;
    }

    final explicit =
        await (db.select(db.userPermissions)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.permission.equals(permission),
            ))
            .getSingleOrNull();
    if (explicit == null) {
      throw AuthException('Permission required: $permission');
    }
    return user;
  }
}
