import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Salted, stretched PIN/password hasher.
///
/// New hashes use PBKDF2-HMAC-SHA256 and are stored as
/// `pbkdf2$<iterations>$<hex>`. Hashes without that prefix are the legacy
/// SHA-256 loop; they still verify so existing accounts keep working, and
/// callers should re-hash them with [hashPin] after a successful login
/// (see [needsRehash]).
class PasswordHasher {
  static final _random = Random.secure();

  static const String _prefix = 'pbkdf2';

  /// Iteration count for new hashes. Pure-Dart HMAC is slow, so this is a
  /// balance between brute-force cost and login latency on a POS terminal.
  static int iterations = 120000;

  /// Generate a random 32-byte salt as hex
  static String generateSalt([int length = 32]) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash a plain text PIN or password with a given salt (PBKDF2).
  static String hashPin(String pin, String saltHex) {
    return '$_prefix\$$iterations\$${_pbkdf2(pin, saltHex, iterations)}';
  }

  /// True if [storedHash] is a legacy hash or uses fewer iterations than now.
  static bool needsRehash(String storedHash) {
    final parsed = _parse(storedHash);
    return parsed == null || parsed.$1 < iterations;
  }

  /// Verify a PIN against stored salt and hash using constant-time comparison
  static bool verifyPin({
    required String pin,
    required String saltHex,
    required String expectedHashHex,
  }) {
    final parsed = _parse(expectedHashHex);
    final String actual;
    final String expected;
    if (parsed == null) {
      actual = _legacyHash(pin, saltHex);
      expected = expectedHashHex;
    } else {
      actual = _pbkdf2(pin, saltHex, parsed.$1);
      expected = parsed.$2;
    }
    if (actual.length != expected.length) return false;

    int result = 0;
    for (int i = 0; i < actual.length; i++) {
      result |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return result == 0;
  }

  static (int, String)? _parse(String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    final iters = int.tryParse(parts[1]);
    if (iters == null || iters <= 0) return null;
    return (iters, parts[2]);
  }

  /// PBKDF2-HMAC-SHA256, single 32-byte output block.
  static String _pbkdf2(String pin, String saltHex, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final salt = utf8.encode(saltHex);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final t = List<int>.from(u);
    for (int i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Original scheme, kept only so existing accounts can still log in.
  static String _legacyHash(String pin, String saltHex) {
    final saltBytes = utf8.encode(saltHex);
    final pinBytes = utf8.encode(pin);
    final combined = Uint8List(saltBytes.length + pinBytes.length);
    combined.setRange(0, saltBytes.length, saltBytes);
    combined.setRange(saltBytes.length, combined.length, pinBytes);

    Digest digest = sha256.convert(combined);
    for (int i = 0; i < 1000; i++) {
      digest = sha256.convert(digest.bytes + pinBytes);
    }
    return digest.toString();
  }
}
