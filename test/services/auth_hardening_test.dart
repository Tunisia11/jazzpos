import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/utils/password_hasher.dart';
import 'package:jazzpos/data/database/app_database.dart';
import 'package:jazzpos/domain/services/auth_service.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late AuthService auth;

  // Keep PBKDF2 fast in tests.
  final savedIterations = PasswordHasher.iterations;
  setUpAll(() => PasswordHasher.iterations = 50);
  tearDownAll(() => PasswordHasher.iterations = savedIterations);

  Future<void> insertUser(String id, String name, String role, String hash,
      String salt) async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: id,
          username: name,
          displayName: name,
          role: role,
          pinHash: hash,
          pinSalt: salt,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 10, 21, 12);
    auth = AuthService(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('new hashes are PBKDF2 and verify; wrong PIN fails', () {
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hashPin('4321', salt);
    expect(hash, startsWith('pbkdf2\$50\$'));
    expect(PasswordHasher.verifyPin(pin: '4321', saltHex: salt, expectedHashHex: hash), isTrue);
    expect(PasswordHasher.verifyPin(pin: '4322', saltHex: salt, expectedHashHex: hash), isFalse);
    expect(PasswordHasher.needsRehash(hash), isFalse);
  });

  test('PBKDF2 output is a 32-byte hex digest', () {
    final h = PasswordHasher.hashPin('password', 'salt');
    expect(h.split('\$').last.length, 64);
  });

  test('legacy SHA-256 hash still logs in and is upgraded', () async {
    // Hash produced by the original scheme (1000-round SHA-256 loop).
    const salt = 'aabbcc';
    final legacy = _legacy('1234', salt);
    await insertUser('u1', 'old', 'CASHIER', legacy, salt);

    final session = await auth.login(username: 'old', pin: '1234');
    expect(session.user.pinHash, startsWith('pbkdf2\$'));
    final row = await (db.select(db.users)..where((t) => t.id.equals('u1'))).getSingle();
    expect(row.pinHash, startsWith('pbkdf2\$'));
    expect(PasswordHasher.verifyPin(pin: '1234', saltHex: row.pinSalt, expectedHashHex: row.pinHash), isTrue);
  });

  test('login locks out after 5 wrong PINs and recovers after the delay', () async {
    final salt = PasswordHasher.generateSalt();
    await insertUser('u2', 'cash', 'CASHIER', PasswordHasher.hashPin('1111', salt), salt);

    for (var i = 0; i < 5; i++) {
      await expectLater(auth.login(username: 'cash', pin: '0000'), throwsA(isA<AuthException>()));
    }
    // Even the correct PIN is refused while locked.
    await expectLater(
      auth.login(username: 'cash', pin: '1111'),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Too many'))),
    );
    now = now.add(const Duration(seconds: 31));
    expect((await auth.login(username: 'cash', pin: '1111')).user.id, 'u2');
  });

  test('manager override is throttled after repeated wrong PINs', () async {
    final salt = PasswordHasher.generateSalt();
    await insertUser('m1', 'mgr', 'MANAGER', PasswordHasher.hashPin('9999', salt), salt);
    for (var i = 0; i < 5; i++) {
      await expectLater(auth.verifyManagerOverride('0000'), throwsA(isA<AuthException>()));
    }
    await expectLater(
      auth.verifyManagerOverride('9999'),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Too many'))),
    );
    now = now.add(const Duration(minutes: 1));
    expect((await auth.verifyManagerOverride('9999')).id, 'm1');
  });
}

String _legacy(String pin, String salt) {
  // Mirrors the pre-PBKDF2 scheme exactly.
  final saltBytes = utf8.encode(salt);
  final pinBytes = utf8.encode(pin);
  Digest digest = sha256.convert([...saltBytes, ...pinBytes]);
  for (int i = 0; i < 1000; i++) {
    digest = sha256.convert(digest.bytes + pinBytes);
  }
  return digest.toString();
}
