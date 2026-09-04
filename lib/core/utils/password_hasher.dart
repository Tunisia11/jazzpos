import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographically secure password and PIN hasher.
/// Stores secrets as SHA-256 + 32-byte salt hex strings.
/// Secrets are never stored in plain text.
class PasswordHasher {
  static final _random = Random.secure();

  /// Generate a random 32-byte salt as hex
  static String generateSalt([int length = 32]) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash a plain text PIN or password with a given salt
  static String hashPin(String pin, String saltHex) {
    final saltBytes = utf8.encode(saltHex);
    final pinBytes = utf8.encode(pin);
    final combined = Uint8List(saltBytes.length + pinBytes.length);
    combined.setRange(0, saltBytes.length, saltBytes);
    combined.setRange(saltBytes.length, combined.length, pinBytes);

    // Iterative hashing (PBKDF-like round stretching)
    Digest digest = sha256.convert(combined);
    for (int i = 0; i < 1000; i++) {
      digest = sha256.convert(digest.bytes + pinBytes);
    }
    return digest.toString();
  }

  /// Verify a PIN against stored salt and hash using constant-time comparison
  static bool verifyPin({
    required String pin,
    required String saltHex,
    required String expectedHashHex,
  }) {
    final actualHash = hashPin(pin, saltHex);
    if (actualHash.length != expectedHashHex.length) return false;

    int result = 0;
    for (int i = 0; i < actualHash.length; i++) {
      result |= actualHash.codeUnitAt(i) ^ expectedHashHex.codeUnitAt(i);
    }
    return result == 0;
  }
}
