import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jazzpos/core/errors/failure.dart';
import 'package:jazzpos/core/utils/backup_crypto.dart';

void main() {
  setUpAll(() => BackupCrypto.iterations = 1000);

  test('round trip restores the exact bytes', () async {
    final plain = Uint8List.fromList(utf8.encode('sales data ' * 100));
    final enc = await BackupCrypto.encrypt(plain, 'correct horse');
    expect(BackupCrypto.isEncrypted(enc), isTrue);
    expect(utf8.decode(enc, allowMalformed: true), isNot(contains('sales data')));
    expect(await BackupCrypto.decrypt(enc, 'correct horse'), plain);
  });

  test('wrong passphrase and tampering are rejected', () async {
    final enc = await BackupCrypto.encrypt([1, 2, 3, 4, 5], 'passphrase1');
    await expectLater(
      BackupCrypto.decrypt(enc, 'passphrase2'),
      throwsA(isA<ValidationException>()),
    );
    final tampered = Uint8List.fromList(enc)..[enc.length - 20] ^= 0xff;
    await expectLater(
      BackupCrypto.decrypt(tampered, 'passphrase1'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('short passphrase is refused; plain data is not "encrypted"', () async {
    await expectLater(
      BackupCrypto.encrypt([1], 'short'),
      throwsA(isA<ValidationException>()),
    );
    expect(BackupCrypto.isEncrypted([1, 2, 3]), isFalse);
  });
}
