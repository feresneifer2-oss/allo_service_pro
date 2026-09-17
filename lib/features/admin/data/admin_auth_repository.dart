import 'package:flutter/foundation.dart';

/// ─── Admin Auth Repository ──────────────────────────────────────────────
///
/// Abstraction for admin credential verification. The client NEVER verifies
/// credentials itself beyond delegating to this boundary — swap the
/// implementation for a server-side role check (e.g. a Supabase RPC or
/// edge function) without touching any call site.
///
/// SECURITY CONTRACT:
///  * No implementation may persist or log plaintext credentials.
///  * Production implementations MUST verify server-side; the local
///    implementation below is an explicit, temporary mock seam.
/// ────────────────────────────────────────────────────────────────────────
abstract class AdminAuthRepository {
  /// Returns true when [email]/[password] identify an administrator.
  Future<bool> verify({required String email, required String password});

  /// Whether this environment has a configured admin identity at all.
  /// A closed (unconfigured) gate must always deny verification.
  bool get isConfigured;
}

/// TEMPORARY MOCK SEAM — local verification for development & tests only.
///
/// Resolves the expected admin identity exclusively from compile-time
/// defines (no source-level defaults, ever):
///
///   --dart-define=ADMIN_EMAIL=... --dart-define=ADMIN_PASSWORD=...
///
/// If either define is absent, the gate is CLOSED (verify always false) —
/// an unauthenticated state. Tests inject fixtures explicitly through
/// [debugConfigure]; unit tests may also call `flutter test
/// --dart-define=...` if they prefer environment-driven fixtures.
///
/// This class is the ONLY place in the client where credential comparison
/// happens, and it exists purely until the Supabase backend lands. It is
/// NOT a production security boundary — passwords on the client are, by
/// definition, inspectable.
class LocalAdminAuthRepository implements AdminAuthRepository {
  final String _defineEmail = const String.fromEnvironment(
    'ADMIN_EMAIL',
    defaultValue: '',
  );
  final String _definePassword = const String.fromEnvironment(
    'ADMIN_PASSWORD',
    defaultValue: '',
  );

  String? _testEmailOverride;
  String? _testPasswordOverride;

  @override
  bool get isConfigured =>
      _expectedEmail.isNotEmpty && _expectedPassword.isNotEmpty;

  String get _expectedEmail {
    if (_testEmailOverride != null) return _testEmailOverride!;
    return _defineEmail;
  }

  String get _expectedPassword {
    if (_testPasswordOverride != null) return _testPasswordOverride!;
    return _definePassword;
  }

  /// True when the release/profile gate is properly armed via defines.
  bool get isReleaseConfigured =>
      _defineEmail.isNotEmpty && _definePassword.isNotEmpty;

  /// Test hook: injects credentials (debug/test builds only). Throws in
  /// release/profile so no optimized binary can re-arm a bypass.
  @visibleForTesting
  void debugConfigure({String? email, String? password}) {
    if (kReleaseMode || kProfileMode) {
      throw StateError(
        'debugConfigure is unavailable in release/profile builds.',
      );
    }
    _testEmailOverride = email;
    _testPasswordOverride = password;
  }

  /// Test hook: clears injected credentials.
  @visibleForTesting
  void debugReset() {
    _testEmailOverride = null;
    _testPasswordOverride = null;
  }

  @override
  Future<bool> verify({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) return false;
    final expectedEmail = _expectedEmail;
    final expectedPassword = _expectedPassword;
    // Closed gate: no credentials configured for this build.
    if (expectedEmail.isEmpty || expectedPassword.isEmpty) return false;
    return email == expectedEmail && password == expectedPassword;
  }
}

/// PRODUCTION TARGET — server-side verification (NOT wired yet).
///
/// When the Supabase backend lands, implement this class to call a remote
/// RPC (e.g. `postgrest.rpc('admin_verify', params: {...})` or a dedicated
/// auth/role check) so the password never ships with the client at all.
/// Until then, calling it fails loudly instead of silently denying.
class SupabaseAdminAuthRepository implements AdminAuthRepository {
  @override
  Future<bool> verify({required String email, required String password}) {
    throw UnsupportedError(
      'SupabaseAdminAuthRepository is not wired yet: admin verification '
      'must move server-side before production. Wire a remote RPC here.',
    );
  }

  @override
  bool get isConfigured => false;
}

/// Resolution point for the active [AdminAuthRepository].
///
/// Defaults to the local mock seam; tests may inject alternatives via
/// [configure]. Call sites (AdminStore) depend only on the abstraction.
class AdminAuth {
  AdminAuth._();

  static AdminAuthRepository _repository = LocalAdminAuthRepository();

  static AdminAuthRepository get instance => _repository;

  /// Test hook: swap the active repository (debug/test builds only).
  @visibleForTesting
  static void configure(AdminAuthRepository repository) {
    if (kReleaseMode || kProfileMode) {
      throw StateError(
        'AdminAuth.configure is unavailable in release/profile builds.',
      );
    }
    _repository = repository;
  }

  /// Test hook: restore the default local seam.
  @visibleForTesting
  static void resetToDefault() {
    _repository = LocalAdminAuthRepository();
  }

  /// Convenience access to the local seam's debug hooks. Public (not
  /// @visibleForTesting) because AdminStore legitimately forwards its own
  /// @visibleForTesting hooks here; the underlying [LocalAdminAuthRepository.
  /// debugConfigure] enforces the release/profile guard at runtime.
  static LocalAdminAuthRepository get _local =>
      _repository is LocalAdminAuthRepository
          ? _repository as LocalAdminAuthRepository
          : throw StateError(
              'Admin debug credential hooks require the local auth seam.',
            );

  static void debugSetCredentials({String? email, String? password}) =>
      _local.debugConfigure(email: email, password: password);

  static void debugResetCredentials() => _local.debugReset();
}
