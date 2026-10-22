import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracepos/core/constants/permissions.dart';
import 'package:tracepos/core/constants/roles.dart';
import 'package:tracepos/core/errors/failure.dart';
import 'package:tracepos/data/database/app_database.dart';
import 'package:tracepos/domain/services/auth_service.dart';

void main() {
  test(
    'manager override enforces the permission requested by the action',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final auth = AuthService(db);
      try {
        await auth.createUser(
          username: 'owner',
          displayName: 'Owner',
          role: AppRoles.owner,
          pin: '9876',
        );
        await auth.login(username: 'owner', pin: '9876');
        await auth.createUser(
          username: 'manager',
          displayName: 'Manager',
          role: AppRoles.manager,
          pin: '4567',
        );
        auth.logout();

        await expectLater(
          auth.verifyManagerOverride(
            '4567',
            requiredPermission: AppPermissions.manageUsers,
          ),
          throwsA(isA<AuthException>()),
        );
        final owner = await auth.verifyManagerOverride(
          '9876',
          requiredPermission: AppPermissions.manageUsers,
        );
        expect(owner.role, AppRoles.owner);
      } finally {
        await db.close();
      }
    },
  );

  test('additional users require an authenticated user manager', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final auth = AuthService(db);
    try {
      await auth.createUser(
        username: 'owner',
        displayName: 'Owner',
        role: AppRoles.owner,
        pin: '9876',
      );
      await expectLater(
        auth.createUser(
          username: 'cashier',
          displayName: 'Cashier',
          role: AppRoles.cashier,
          pin: '1235',
        ),
        throwsA(isA<AuthException>()),
      );
      await auth.login(username: 'owner', pin: '9876');
      await auth.createUser(
        username: 'cashier',
        displayName: 'Cashier',
        role: AppRoles.cashier,
        pin: '1235',
      );
      expect(await db.select(db.users).get(), hasLength(2));
    } finally {
      await db.close();
    }
  });
}
