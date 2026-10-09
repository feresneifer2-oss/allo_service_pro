import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';
import '../../../core/network/connectivity_store.dart';

/// Outcome of one live OTP dispatch (`auth.signInWithOtp`).
///
/// PHASE 3T: the previous `bool` conflated every failure into one bucket, so
/// the UI could not tell the provider's RATE LIMITER (HTTP 429 — "try again
/// later") from a genuine channel refusal (SMTP not wired, unknown account
/// under `shouldCreateUser: false`, invalid address). Transport failures
/// (offline / DNS / timeout) are NOT represented here: [SupabaseAuthService.sendOtp]
/// RETHROWS them, keeping the retryable network classification intact.
enum OtpSendOutcome {
  /// The provider accepted the request; the code is on its way.
  sent,

  /// HTTP 429 (or a throttle-marked provider message): the rate limiter
  /// refused this attempt. Retrying immediately cannot help — the UI shows a
  /// dedicated "try again later" state.
  rateLimited,

  /// Any other provider-side refusal. Retrying with the same configuration
  /// cannot help.
  refused,
}

/// Thin gateway around Supabase Auth for the Email-OTP flow.
///
/// ISOLATION CONTRACT: this class must stay free of any app-store import
/// (UserStore, AdminStore, …) so [UserStore] can call [signOut] without an
/// import cycle. Mapping the Supabase identity onto the local session lives
/// in [bindSupabaseAuthListener] (supabase_auth_bindings.dart).
///
/// Every call degrades gracefully: when Supabase was never initialized
/// (unit tests, offline-first demo builds) [isConfigured] answers `false`
/// and callers fall back to the local [EmailOtpService] demo channel.
class SupabaseAuthService {
  SupabaseAuthService._();

  /// TEST SEAM (Phase 3T): overrides [isConfigured] so focused tests can
  /// exercise the LIVE branches (login/registration OTP dispatch, 429
  /// classification) without a real backend. `null` = real detection.
  @visibleForTesting
  static bool? debugConfiguredOverride;

  /// TEST SEAM (Phase 3T): stands in for the live `signInWithOtp` dispatch.
  /// `null` = real client call.
  @visibleForTesting
  static Future<OtpSendOutcome> Function(
    String email, {
    required bool shouldCreateUser,
  })? debugSendOtpOverride;

  /// TEST SEAM (Phase 3T): stands in for the live `verifyOTP` exchange.
  /// `null` = real client call.
  @visibleForTesting
  static Future<bool> Function(String email, String token)?
      debugVerifyOtpOverride;

  /// TEST SEAM: stands in for the live `signInWithPassword` exchange.
  /// `null` = real client call.
  @visibleForTesting
  static Future<bool> Function(String email, String password)?
      debugSignInWithPasswordOverride;

  /// TEST SEAM: stands in for the live `updateUser` password save.
  /// `null` = real client call.
  @visibleForTesting
  static Future<bool> Function(String password)? debugSetPasswordOverride;

  /// Clears every test seam (Phase 3T) — call from test `setUp`/`tearDown`
  /// so a simulated configuration can never leak into another test.
  @visibleForTesting
  static void debugResetOverrides() {
    debugConfiguredOverride = null;
    debugSendOtpOverride = null;
    debugVerifyOtpOverride = null;
    debugSignInWithPasswordOverride = null;
    debugSetPasswordOverride = null;
  }

  /// Whether `Supabase.initialize()` ran in this process. Accessing the
  /// client before initialization throws — that throw IS the detection.
  static bool get isConfigured {
    final override = debugConfiguredOverride;
    if (override != null) return override;
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stable Supabase Auth UUID (`auth.users.id`) of the signed-in identity.
  ///
  /// This is THE id every backend column keyed to the authenticated user must
  /// carry (`orders.customer_id`, `messages.sender_id`, `profiles.id`, the
  /// `documents/<uid>/…` storage prefix). `null` when Supabase is not
  /// initialized or nobody is signed in, so callers fall back EXPLICITLY
  /// instead of inventing an identity.
  static String? get currentUserId {
    if (!isConfigured) return null;
    try {
      final id = Supabase.instance.client.auth.currentUser?.id;
      if (id == null) return null;
      final trimmed = id.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      // Seam safety: a simulated/void client must degrade to "no identity"
      // instead of crashing every backend call that reads this.
      debugPrint('SupabaseAuthService.currentUserId unavailable: $e');
      return null;
    }
  }

  /// Triggers the 6-digit e-mail OTP (`signInWithOtp`). Supabase emails the
  /// code and — when [shouldCreateUser] — creates the user row on first
  /// sign-in.
  ///
  /// REGISTRATION dispatches with the default (`true`). The LOGIN path
  /// (Phase 3T) passes `false`: signing in must never provision a brand-new
  /// account behind the user's back; an unknown address is answered with an
  /// [OtpSendOutcome.refused] (the UI nudges towards sign-up instead).
  ///
  /// Returns an [OtpSendOutcome] for provider-side answers. A TRANSPORT
  /// failure (offline / DNS / timeout — no HTTP status) is RETHROWN so
  /// callers keep the retryable network classification distinct from a
  /// channel refusal.
  static Future<OtpSendOutcome> sendOtp(
    String email, {
    bool shouldCreateUser = true,
  }) async {
    final override = debugSendOtpOverride;
    if (override != null) {
      return override(email, shouldCreateUser: shouldCreateUser);
    }
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: shouldCreateUser,
      );
      return OtpSendOutcome.sent;
    } on AuthException catch (e) {
      // TRANSPORT FIRST (CodeRabbit): a network-class failure carries no HTTP
      // status — it is RETRYABLE and must be rethrown (the OTP screen shows
      // the connectivity guidance) instead of being reported as an
      // unavailable delivery channel.
      if (_isTransportFailure(e)) {
        debugPrint('SupabaseAuthService.sendOtp transport failure '
            '(retryable): $e');
        rethrow;
      }
      // Provider/CHANNEL-side refusal (SMTP not wired, rate limit, invalid
      // address): retrying with the same configuration cannot help — but a
      // RATE LIMIT (429) gets its own outcome so the UI never tells the user
      // "e-mail not configured" for a throttle.
      final outcome = classifySendFailure(
        statusCode: e.statusCode,
        message: e.message,
      );
      debugPrint('SupabaseAuthService.sendOtp refused ($outcome): $e');
      return outcome;
    } on StateError catch (e) {
      // Supabase not initialized (tests / local-only mode): no channel at all.
      debugPrint('SupabaseAuthService.sendOtp: not configured: $e');
      return OtpSendOutcome.refused;
    } catch (e) {
      // TRANSPORT failure (offline / DNS / timeout) — rethrown so the OTP
      // screen can distinguish it from a channel refusal (CodeRabbit).
      debugPrint('SupabaseAuthService.sendOtp transport failure: $e');
      rethrow;
    }
  }

  /// PURE 429 classifier (Phase 3T) — exposed for focused tests.
  ///
  /// HTTP 429 (or a provider message carrying a throttle marker, e.g.
  /// GoTrue's "For security purposes, you can only request this after N
  /// seconds") means the provider's RATE LIMITER refused this attempt: the
  /// UI must show a "try again later" state, never "e-mail not configured".
  /// Everything else is a plain [OtpSendOutcome.refused].
  @visibleForTesting
  static OtpSendOutcome classifySendFailure({
    Object? statusCode,
    required String message,
  }) {
    if (statusCode?.toString() == '429') return OtpSendOutcome.rateLimited;
    final text = message.toLowerCase();
    if (text.contains('rate limit') ||
        text.contains('too many') ||
        text.contains('security purposes')) {
      return OtpSendOutcome.rateLimited;
    }
    return OtpSendOutcome.refused;
  }

  /// RETRYABLE-TRANSPORT CLASSIFIER (CodeRabbit, evaluated BEFORE any generic
  /// AuthException handling): supabase-dart wraps socket / DNS / timeout
  /// faults in [AuthApiException] with NO HTTP status code. Those are
  /// transient NETWORK failures — retryable — and must never be reported as
  /// "the delivery channel is unavailable". Any real HTTP status
  /// (400 / 401 / 422 / 429 / 500) is a genuine provider-side response and a
  /// real channel classification.
  static bool _isTransportFailure(AuthException e) {
    if (e.statusCode != null) return false;
    final text = e.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup') ||
        text.contains('connection') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('clientexception');
  }

  /// Verifies the 6-digit token (`verifyOTP`, e-mail type). A session in the
  /// response means the code was correct, unconsumed and unexpired — the
  /// remote identity is now authenticated.
  static Future<bool> verifyOtp(String email, String token) async {
    final override = debugVerifyOtpOverride;
    if (override != null) return override(email, token);
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: token.trim(),
        type: OtpType.email,
      );
      return res.session != null;
    } on AuthException catch (e) {
      // TRANSPORT FIRST (CodeRabbit): a network-class failure (no HTTP
      // status) is RETRYABLE and is logged as such — never reported as a
      // wrong-code / provider refusal. The user-facing outcome is the same
      // (`false` → try again), but diagnostics and retry policy now know
      // the difference.
      if (_isTransportFailure(e)) {
        debugPrint('SupabaseAuthService.verifyOtp transport failure '
            '(retryable): $e');
        return false;
      }
      debugPrint('SupabaseAuthService.verifyOtp rejected: $e');
      return false;
    } catch (e) {
      debugPrint('SupabaseAuthService.verifyOtp failed: $e');
      return false;
    }
  }

  /// Password sign-in (`signInWithPassword`) — the ONE remote credential
  /// exchange in the app, used EXCLUSIVELY by the server-side admin gate
  /// (`SupabaseAdminAuthRepository`).
  ///
  /// Regular users authenticate with the 6-digit e-mail OTP; an operator
  /// enrolled in `public.admins` gets their Supabase identity from the
  /// Dashboard (e-mail + password) and therefore needs this path. No secret
  /// ships in the binary: the only authority over admin membership stays the
  /// backend (`public.is_admin()` keyed on `auth.uid()`).
  ///
  /// Returns `true` only when a session now authenticates this identity.
  /// Every failure (wrong password, unconfirmed e-mail, provider disabled,
  /// network) is a `false` — never a throw into the UI layer.
  static Future<bool> signInWithPassword(String email, String password) async {
    if (!isConfigured) return false;
    final signInOverride = debugSignInWithPasswordOverride;
    if (signInOverride != null) return signInOverride(email, password);
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return res.session != null;
    } on AuthException catch (e) {
      debugPrint('SupabaseAuthService.signInWithPassword rejected: $e');
      return false;
    } catch (e) {
      debugPrint('SupabaseAuthService.signInWithPassword failed: $e');
      return false;
    }
  }

  /// Saves a password onto the CURRENT authenticated Supabase session.
  /// Used after OTP verification during registration, while the session
  /// created by verifyOTP is still valid.
  /// Returns true on success, false otherwise (never throws to UI).
  static Future<bool> setPassword(String password) async {
    if (!isConfigured) return false;
    final setOverride = debugSetPasswordOverride;
    if (setOverride != null) return setOverride(password);
    try {
      final res = await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      return res.user != null;
    } catch (e) {
      debugPrint('SupabaseAuthService.setPassword failed: $e');
      return false;
    }
  }

  /// Drops the locally stored Supabase session WITHOUT any remote revocation
  /// (`scope: local`).
  ///
  /// Used by the admin gate when an authenticated identity turns out NOT to
  /// be enrolled server-side: the session this sign-in attempt just created
  /// must not linger on disk (it would be re-hydrated on the next boot) nor
  /// displace the local app session.
  static Future<bool> clearLocalSession() => _stripLocalSession();

  /// Remote sign-out.
  ///
  /// RETURNS `true` when the remote session was revoked **or when there is
  /// nothing to revoke**:
  ///   • Supabase not initialized (local-only build) → nothing remote exists;
  ///   • the device is OFFLINE → the refresh token cannot be used by anyone
  ///     while there is no network, and the local session is still dropped by
  ///     the caller, so refusing the sign-out would trap the user in the app.
  ///     The deferred revocation is logged for diagnostics.
  ///
  /// RETURNS `false` on a GENUINE server refusal while online: callers MUST
  /// treat that as an ABORTED sign-out (session stays alive, nothing is
  /// wiped) so a device can never keep a live remote session while the user
  /// believes they logged out.
  static Future<bool> signOut() async {
    if (!isConfigured) return true; // nothing remote to revoke
    if (!ConnectivityStore.isOnline.value) {
      debugPrint('SupabaseAuthService.signOut: offline — remote revocation '
          'deferred until the next online sign-out.');
      final localStripped = await _stripLocalSession();
      if (!localStripped) return false;
      return true;
    }
    try {
      // SCOPE PINNED (CodeRabbit): the ONLINE revocation is deliberately
      // `global` — every refresh token issued to this identity is revoked
      // server-side, not just the one on this device — mirroring the offline
      // path's explicit `local` pin below. The signedOut event the server
      // fires is what drives the bindings' local cleanup, and the
      // `_stripLocalSession` verification closes the synchronization loop.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    } catch (e, st) {
      debugPrint('SupabaseAuthService.signOut failed: $e');
      AppErrorHandler.report(e, st, context: 'SupabaseAuthService.signOut');
      return false;
    }
    // POST-REMOTE LOCAL CHECK (CodeRabbit): the server revocation succeeded,
    // but the matching local session MUST also be gone — a stale token left
    // behind would resurrect the session on the next boot via
    // `onAuthStateChange`'s `initialSession` event. A failed local strip is
    // an ABORTED sign-out, never a silent success.
    if (!await _stripLocalSession()) return false;
    return true;
  }

  /// Removes the locally stored Supabase session (scope `local` — never
  /// emits a network request) and verifies it is actually gone.
  ///
  /// Returns `true` only when `currentSession` reads `null` afterwards.
  /// Non-null afterwards (or a thrown strip) is a `false` — the caller must
  /// abort the sign-out so the device can never believe it logged out while
  /// a usable token remains on disk.
  static Future<bool> _stripLocalSession() async {
    if (!isConfigured) return true;
    // OFFLINE SESSION STRIP (CodeRabbit): the refresh token cannot be used
    // while offline, so the risk is not "someone else uses it right now" —
    // it is the NEXT online launch. If the local Supabase session is left
    // intact, `onAuthStateChange`'s `initialSession` event on the next
    // boot re-hydrates it and silently logs the user back in AFTER they
    // already signed out locally (a "ghost" signed-in state). Force-clear
    // the local session now so the offline sign-out is durable and the
    // deferred remote revocation has no stale token to act on. Passing
    // [SignOutScope.local] EXPLICITLY: the default is also `local` today,
    // but the offline path must NEVER reach the network — an explicit
    // local scope pins the contract (no server request is emitted: without
    // an access token _signOut only strips the local session and fires the
    // signedOut event). A future upstream default of `global` would
    // otherwise send this "offline" path straight to the admin endpoint.
    try {
      await Supabase.instance.client.auth.signOut(
        scope: SignOutScope.local,
      );
    } catch (e) {
      debugPrint(
          'SupabaseAuthService._stripLocalSession failed (best-effort): $e');
      return false;
    }
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        debugPrint('SupabaseAuthService._stripLocalSession: session still '
            'present after strip — aborting sign-out.');
        return false;
      }
    } catch (e) {
      debugPrint('SupabaseAuthService._stripLocalSession verify failed: $e');
      return false;
    }
    return true;
  }

  /// Identity of the currently authenticated remote user, if any.
  static ({String email, String? fullName})? get currentUser {
    if (!isConfigured) return null;
    try {
      final u = Supabase.instance.client.auth.currentUser;
      if (u?.email == null) return null;
      final meta = u!.userMetadata;
      // SAFE METADATA CAST (CodeRabbit): user metadata is untrusted JSON — a
      // value typed as num/bool by the writer must never crash an
      // `as String?` cast. Stringify defensively and trim.
      final rawName = meta is Map<String, dynamic>
          ? (meta['full_name'] ?? meta['name'])?.toString()
          : null;
      final name =
          (rawName?.trim().isNotEmpty ?? false) ? rawName!.trim() : null;
      return (email: u.email!, fullName: name);
    } catch (e) {
      // Seam safety (Phase 3T): identical contract to `currentUserId` — a
      // simulated/void client degrades to "no remote identity".
      debugPrint('SupabaseAuthService.currentUser unavailable: $e');
      return null;
    }
  }
}
