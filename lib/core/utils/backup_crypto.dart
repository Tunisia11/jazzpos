import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tracepos/core/errors/failure.dart';

/// Passphrase encryption for backup packages.
///
/// Layout: `TPOSENC1` | salt(16) | nonce(12) | AES-256-GCM ciphertext | tag(16).
/// The key is PBKDF2-HMAC-SHA256 of the passphrase. The passphrase is never
/// stored; losing it means the backup cannot be opened.
class BackupCrypto {
  const BackupCrypto._();

  static const List<int> _magic = [0x54, 0x50, 0x4f, 0x53, 0x45, 0x4e, 0x43, 0x31];
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// Lowered in tests to keep them fast.
  static int iterations = 150000;

  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<SecretKey> _key(String passphrase, List<int> salt) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Future<Uint8List> encrypt(List<int> plain, String passphrase) async {
    if (passphrase.length < 8) {
      throw const ValidationException(
        'Backup passphrase must be at least 8 characters.',
      );
    }
    final algo = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: _saltLen).bytes;
    final nonce = algo.newNonce();
    final box = await algo.encrypt(
      plain,
      secretKey: await _key(passphrase, salt),
      nonce: nonce,
    );
    return Uint8List.fromList([
      ..._magic,
      ...salt,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> decrypt(List<int> data, String passphrase) async {
    if (!isEncrypted(data) ||
        data.length < _magic.length + _saltLen + _nonceLen + _macLen) {
      throw const ValidationException('Not an encrypted backup file.');
    }
    var o = _magic.length;
    final salt = data.sublist(o, o += _saltLen);
    final nonce = data.sublist(o, o += _nonceLen);
    final cipher = data.sublist(o, data.length - _macLen);
    final mac = data.sublist(data.length - _macLen);
    try {
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: await _key(passphrase, salt),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const ValidationException(
        'Wrong passphrase or the backup file is damaged.',
      );
    }
  }
}
