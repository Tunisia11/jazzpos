import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/utils/id_generator.dart';
import 'package:jazzpos/core/utils/password_hasher.dart';
import 'package:jazzpos/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Database Schema & Invariant Tests', () {
    test('Can create company, store, register and user in database', () async {
      final now = DateTime.now();
      final companyId = IdGenerator.uuid();
      final storeId = IdGenerator.uuid();
      final registerId = IdGenerator.uuid();
      final userId = IdGenerator.uuid();

      await db.into(db.companies).insert(
            CompaniesCompanion.insert(
              id: companyId,
              name: 'Jazz Fashion SARL',
              fiscalId: const Value('1234567/A/M/000'),
              phone: const Value('+216 71 000 000'),
              address: const Value('Avenue Habib Bourguiba, Tunis'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.stores).insert(
            StoresCompanion.insert(
              id: storeId,
              companyId: companyId,
              name: 'Tunis Mall Flagship',
              code: 'STORE-01',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.registers).insert(
            RegistersCompanion.insert(
              id: registerId,
              storeId: storeId,
              name: 'Register 1',
              code: 'REG-01',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hashPin('1234', salt);

      await db.into(db.users).insert(
            UsersCompanion.insert(
              id: userId,
              username: 'admin',
              displayName: 'Store Manager',
              role: 'OWNER',
              pinHash: hash,
              pinSalt: salt,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final users = await db.select(db.users).get();
      expect(users.length, 1);
      expect(users.first.username, 'admin');
      expect(PasswordHasher.verifyPin(pin: '1234', saltHex: salt, expectedHashHex: hash), isTrue);
      expect(PasswordHasher.verifyPin(pin: '9999', saltHex: salt, expectedHashHex: hash), isFalse);
    });

    test('Foreign key enforcement blocks orphan store with nonexistent company', () async {
      final now = DateTime.now();
      expect(
        () async => await db.into(db.stores).insert(
              StoresCompanion.insert(
                id: IdGenerator.uuid(),
                companyId: 'nonexistent-company-id',
                name: 'Bad Store',
                code: 'BAD-01',
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
