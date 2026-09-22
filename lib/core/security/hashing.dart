import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// WEB-COMPATIBLE SHA-256 (CodeRabbit): delegated to the pure-Dart
/// `package:crypto`, which compiles seamlessly across iOS, Android and Web —
/// no platform channels, no native bindings, no dart:io dependency.
///
/// Deterministic and side-effect free: hex-encoded lower-case digest.
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// PBKDF2-HMAC-SHA256 (CodeRabbit): a real PASSWORD key-derivation function.
///
/// Single-pass hashing is too cheap against offline brute-force: this derives
/// the credential digest with [pbkdf2DefaultIterations] HMAC-SHA256 rounds,
/// making each guess thousands of times more expensive while staying pure
/// Dart / web compatible. Only the hex digest is ever persisted.
///
/// Implemented on top of `package:crypto`'s [Hmac] (RFC 8018, dkLen = 32 —
/// a single output block, so DK = U1 ⊕ U2 ⊕ … ⊕ Uc).
const int pbkdf2DefaultIterations = 20000;

String pbkdf2Hex(
  String password,
  String salt, {
  int iterations = pbkdf2DefaultIterations,
}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  // Block index 1 (big-endian) appended to the salt: the first U_1 input.
  final firstInput = <int>[...utf8.encode(salt), 0, 0, 0, 1];
  var u = hmac.convert(firstInput).bytes;
  final acc = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < acc.length; j++) {
      acc[j] ^= u[j];
    }
  }
  return acc.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
