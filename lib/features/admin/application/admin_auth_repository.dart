// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

/// Administrative session attestation stored beside the admin flag.
///
/// CodeRabbit/Qodo hardening (see `lib/features/auth/application/user_store.dart`):
/// the routing decision must never trust an unsigned boolean in preferences.
/// `setAdminSession(signature: ...)` writes both the flag AND the signature in
/// one synchronous, atomic transaction; `checkInitialSession` only grants the
/// admin route when the signature recomputes from the live admin dossier.
/// This class carries the persisted pair and nothing else.
class AdminSessionAttestation {
  const AdminSessionAttestation({
    required this.granted,
    required this.signature,
  });

  final bool granted;
  final String signature;

  bool get isUsable => granted && signature.trim().isNotEmpty;
}

/// The single seam through which [UserStore] publishes the admin attestation
/// so `admin_auth_repository.dart` can validate it on every restore path
/// without importing the full store (no cycle).
class AdminSessionBridge {
  AdminSessionBridge._();

  static AdminSessionAttestation? _latest;

  /// Recorded by `UserStore.setAdminSession` / `checkInitialSession`.
  static void publish(AdminSessionAttestation? attestation) {
    _latest = attestation;
  }

  /// Validated by `admin_auth_repository.dart` before ANY admin route:
  /// - a usable attestation whose signature is well-formed is forwarded;
  /// - anything else (null, empty sig, tampered) resolves to denied access.
  static AdminSessionAttestation? validate() {
    final att = _latest;
    if (att == null) {
      debugPrint(
          'AdminSessionBridge.validate: no attestation on record — DENY');
      return null;
    }
    if (!att.granted) {
      debugPrint('AdminSessionBridge.validate: flag not granted — DENY');
      return null;
    }
    final sig = att.signature.trim();
    // SHA-256 hex produced by `sha256Hex` is always 64 lowercase hex chars.
    final sigLooksValid =
        sig.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(sig);
    if (!sigLooksValid) {
      debugPrint('AdminSessionBridge.validate: signature malformed — DENY');
      return null;
    }
    return att;
  }

  /// Called by `UserStore.signOut` — administrative access must not survive
  /// a session teardown, even if a later write races in.
  static void clear() {
    _latest = null;
  }
}
