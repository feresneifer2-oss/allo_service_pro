import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:allo_service_pro/shared/validators.dart';

/// Email OTP (6-digit) issue & verification service.
///
/// Replaces the old SMS/phone verification channel as the app's
/// authentication second factor:
///   • [sendOtp] generates a 6-digit code bound to a NORMALIZED email
///     address with a validity window (10 minutes).
///   • [verifyOtp] checks format + freshness + equality and CONSUMES the
///     code on success (a code can never be reused).
///   • [resendOtp] re-issues a fresh code (invalidating the previous one).
///
/// Delivery & the security boundary
/// ----------------------------------------------------------------
/// The app ships without an SMTP backend, so the issued code is surfaced
/// in-app through a **demo delivery channel. That channel is a DEBUG-ONLY
/// bypass and is hard-gated by [kDebugMode]:
///   • [_demoDeliveryEnabled] is a *compile-time* constant that is `true`
///     ONLY in debug builds — `false` in every optimized binary (release AND
///     profile), so tree-shaking removes the demo branch from non-debug
///     binaries entirely;
///   • [lastDemoCode] throws a [StateError] outside debug builds, so no
///     release/profile code path can read a code it was never meant to see;
///   • [_deliver] throws [EmailOtpUnavailableException] in release/profile
///     because no real channel is wired yet — an unverified delivery path is
///     never silently treated as success.
///
/// Wiring a real provider means performing the actual send inside [_deliver]
/// and dropping the demo branch; nothing else in the flow changes.
class EmailOtpService {
  EmailOtpService._();

  static const int codeLength = 6;

  /// Validity window of a freshly issued code. Deliberately NOT const: the
  /// tests shrink it to exercise the expiry branch deterministically.
  static Duration validity = const Duration(minutes: 10);

  /// Compile-time security gate: `true` ONLY in debug builds — `false` in
  /// every optimized binary (release AND profile). Because it is `const`,
  /// tree-shaking removes the demo branch from non-debug binaries entirely.
  static const bool _demoDeliveryEnabled = kDebugMode;

  // Non-debug security boundary.
  // `debugDemoOverride` exists ONLY as a test seam so a unit test can
  // simulate an optimized build (force the override to false and assert the
  // demo bypass is unreachable). It is NOT a public, mutable toggle:
  // assigning anything while in a non-debug build (release OR profile)
  // throws an [EmailOtpSecurityException] — an optimized binary can never
  // re-enable the in-app OTP reader, regardless of who calls the setter.
  static bool? _debugDemoOverride;

  /// Read-side: `true` only in a DEBUG build AND the test seam has not
  /// explicitly opted out of the demo channel.
  static bool get demoMode {
    // Profile builds run optimized code (debugging hooks still attached) —
    // close enough to release that the plaintext-OTP bypass stays off,
    // blocking any debug-only surface area.
    if (kReleaseMode || kProfileMode) return false;
    return _debugDemoOverride ?? _demoDeliveryEnabled;
  }

  /// Test-only write-side. In any non-debug build (release OR profile)
  /// attempting to enable the demo channel is a hard security violation and
  /// throws [EmailOtpSecurityException].
  @visibleForTesting
  static set debugDemoOverride(bool? value) {
    if ((kReleaseMode || kProfileMode) && value == true) {
      throw EmailOtpSecurityException(
        'Refusing to enable the in-app OTP demo channel in a non-debug '
        'build (release/profile).',
      );
    }
    _debugDemoOverride = value;
  }

  /// Test-only read-side so an assertion can probe the current override.
  @visibleForTesting
  static bool? get debugDemoOverride => _debugDemoOverride;

  static String? _lastDemoCode;

  /// The last code issued through the demo channel.
  ///
  /// THROWS a [StateError] whenever [demoMode] is false — reading a plaintext
  /// OTP is a debug-only capability, so in release/profile the bypass is
  /// unreachable.
  static String? get lastDemoCode {
    if (!demoMode) {
      throw StateError(
        'EmailOtpService.lastDemoCode is a DEBUG-only bypass and is '
        'unreachable in release/profile builds.',
      );
    }
    return _lastDemoCode;
  }

  /// The code currently pending for [email] — the DEBUG-only in-app banner.
  ///
  /// Like [lastDemoCode] this capability is debug-only and throws outside debug
  /// builds. Unlike it, the lookup is PER-ADDRESS, which is what the OTP screen
  /// needs: when it ADOPTS a still-valid code instead of sending a new one, the
  /// banner must show that very code — [_lastDemoCode] is global, so it could
  /// hold a code issued for a different address.
  ///
  /// Returns null when no fresh, unconsumed code exists for [email].
  static String? demoCodeFor(String email) {
    if (!demoMode) {
      throw StateError(
        'EmailOtpService.demoCodeFor is a DEBUG-only bypass and is '
        'unreachable in release/profile builds.',
      );
    }
    final entry = _pending[_normalize(email)];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) return null;
    return entry.code;
  }

  /// Whether a usable OTP delivery channel exists for THIS build.
  ///
  /// Debug builds always have the in-app demo channel. Release/profile
  /// builds have one ONLY after a real provider is wired (see [_deliver]).
  /// Registration flows MUST consult this before issuing a code - see
  /// [requireDeliveryChannel].
  static bool get hasDeliveryChannel => demoMode || _hasExternalProvider;

  /// True once a real (non-demo) SMTP/API provider is wired into [_deliver].
  /// Flip to true as part of wiring the provider - until then, release and
  /// profile builds refuse to start registration sequences.
  static bool _hasExternalProvider = false;

  /// Test hook: simulates a wired production provider (debug builds only).
  @visibleForTesting
  static void debugSetExternalProvider(bool wired) {
    if (kReleaseMode || kProfileMode) {
      throw EmailOtpSecurityException(
          'debugSetExternalProvider is unavailable in release/profile builds.');
    }
    _hasExternalProvider = wired;
  }

  /// Guards a registration sequence: returns normally only when a delivery
  /// channel exists, otherwise throws [EmailOtpUnavailableException].
  ///
  /// Call this BEFORE creating any credential record so a release build
  /// without SMTP can never mint an account whose code could never arrive.
  static void requireDeliveryChannel() {
    if (hasDeliveryChannel) return;
    throw const EmailOtpUnavailableException();
  }

  static final Random _random = Random.secure();
  static final Map<String, _PendingOtp> _pending = {};

  /// Codes actually issued through the delivery channel so far.
  ///
  /// Test hook (read-only): lets a regression test assert that a resumable
  /// flow issues EXACTLY ONE code — a second issuance would invalidate the
  /// code the user already holds.
  static int _issuedCodeCount = 0;

  @visibleForTesting
  static int get debugIssuedCodeCount => _issuedCodeCount;

  static String _normalize(String email) => email.trim().toLowerCase();

  /// Generates a cryptographically-random, zero-padded 6-digit code.
  static String _generate() => (_random.nextInt(900000) + 100000).toString();

  /// Simulated delivery channel — the single seam to replace with a real
  /// SMTP/API call when a backend is introduced.
  ///
  /// In release/profile ([demoMode] == false) there is NO delivery path at
  /// all, so this throws instead of pretending the mail went out: callers
  /// must surface an "unavailable" state rather than let an unverifiable
  /// code unlock an account.
  static void _deliver(String email, String code) {
    if (demoMode) {
      _lastDemoCode = code;
      debugPrint('📧 [EmailOtpService] OTP for $email → $code (simulated)');
      return;
    }
    throw const EmailOtpUnavailableException();
  }

  /// Issues a fresh OTP for [email]. Returns false when the email format
  /// is invalid (the caller shows the field error).
  ///
  /// THROWS [EmailOtpUnavailableException] in release/profile builds, where
  /// the demo channel is compiled out and no real provider is wired — see
  /// [_deliver].
  static bool sendOtp(String email) {
    final key = _normalize(email);
    if (!AppValidators.isValidEmail(key)) return false;
    final code = _generate();
    // Delivery FIRST: in a release/profile build [_deliver] throws, so no
    // pending entry is ever registered for a code that was never sent.
    _deliver(key, code);
    _pending[key] = _PendingOtp(
      code: code,
      expiresAt: DateTime.now().add(validity),
    );
    _issuedCodeCount += 1;
    return true;
  }

  /// Re-issues a fresh OTP, invalidating any previous one. Returns false
  /// when the email format is invalid.
  static bool resendOtp(String email) => sendOtp(email);

  /// Verifies [code] against the pending OTP of [email]:
  ///   • unknown email / no pending code → false
  ///   • expired code → false (entry dropped, a new one must be sent)
  ///   • wrong code → false (entry kept — the user may retry)
  ///   • correct code → true and the entry is CONSUMED (single use).
  /// Brute-force guard: after this many wrong attempts the pending code is
  /// invalidated entirely; the user must request a fresh one (which also
  /// re-arms the resend cooldown). Keeps online guessing impractical:
  /// 5 tries over a 6-digit space (1/900000 per try) per delivery window.
  static const int maxVerifyAttempts = 5;

  static bool verifyOtp(String email, String code) {
    final key = _normalize(email);
    final entry = _pending[key];
    if (entry == null) return false;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _pending.remove(key);
      return false;
    }
    if (entry.code != code.trim()) {
      // Wrong code: count the failure; burn the code once the attempt
      // budget is exhausted so it can never be verified afterwards.
      entry.failedAttempts += 1;
      if (entry.failedAttempts >= maxVerifyAttempts) {
        _pending.remove(key);
        _lastDemoCode = null;
      }
      return false;
    }
    _pending.remove(key); // single-use consumption
    _lastDemoCode = null;
    return true;
  }

  /// Whether a fresh, unconsumed OTP exists for [email].
  static bool hasPendingOtp(String email) {
    final entry = _pending[_normalize(email)];
    if (entry == null) return false;
    return !DateTime.now().isAfter(entry.expiresAt);
  }

  /// Broadcasts a code for [email] **only when the demo channel is live**.
  ///
  /// This is the sanitized entry point for UI code that must keep working in
  /// release: it returns false instead of throwing, so the screen can show an
  /// "unavailable" state while the debug bypass stays unreachable.
  static bool trySendOtp(String email) {
    try {
      return sendOtp(email);
    } on EmailOtpUnavailableException {
      return false;
    }
  }

  /// Test/teardown helper — clears every pending OTP.
  static void reset() {
    _pending.clear();
    _lastDemoCode = null;
    _issuedCodeCount = 0;
  }
}

/// Thrown when an OTP must be delivered but no delivery channel is
/// configured (i.e. any RELEASE/PROFILE build: the debug-only demo channel
/// is compiled out and no SMTP provider has been wired yet).
///
/// Callers use [EmailOtpService.trySendOtp] to degrade gracefully.
class EmailOtpUnavailableException implements Exception {
  const EmailOtpUnavailableException();

  @override
  String toString() =>
      'EmailOtpUnavailableException: no OTP delivery channel is configured '
      'for this build (the demo channel is debug-only).';
}

/// Thrown when a caller attempts to re-enable the DEBUG-only in-app OTP
/// reader through the [EmailOtpService.debugDemoOverride] test seam while
/// in a non-debug build (release OR profile).
///
/// This is a hard security boundary: an optimized binary MUST never be able
/// to surface or read a plaintext verification code, so the override
/// refuses to take effect instead of silently allowing it.
class EmailOtpSecurityException implements Exception {
  const EmailOtpSecurityException(this.message);

  final String message;

  @override
  String toString() => 'EmailOtpSecurityException: $message';
}

class _PendingOtp {
  _PendingOtp({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  /// Consecutive failed verification attempts against this code
  /// (brute-force guard — see [EmailOtpService.maxVerifyAttempts]).
  int failedAttempts = 0;
}
