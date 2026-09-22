import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';
import '../../../core/network/connectivity_store.dart';

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

  /// Whether `Supabase.initialize()` ran in this process. Accessing the
  /// client before initialization throws — that throw IS the detection.
  static bool get isConfigured {
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
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Triggers the 6-digit e-mail OTP (`signInWithOtp`). Supabase emails the
  /// code and creates the user row on first sign-in (`shouldCreateUser`).
  /// Returns `false` on ANY failure (network, rate limit, invalid address) —
  /// never throws into the UI layer.
  static Future<bool> sendOtp(String email) async {
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      return true;
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
      // address): retrying with the same configuration cannot help.
      debugPrint('SupabaseAuthService.sendOtp rejected by the channel: $e');
      return false;
    } on StateError catch (e) {
      // Supabase not initialized (tests / local-only mode): no channel at all.
      debugPrint('SupabaseAuthService.sendOtp: not configured: $e');
      return false;
    } catch (e) {
      // TRANSPORT failure (offline / DNS / timeout) — rethrown so the OTP
      // screen can distinguish it from a channel refusal (CodeRabbit).
      debugPrint('SupabaseAuthService.sendOtp transport failure: $e');
      rethrow;
    }
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
    final u = Supabase.instance.client.auth.currentUser;
    if (u?.email == null) return null;
    final meta = u!.userMetadata;
    // SAFE METADATA CAST (CodeRabbit): user metadata is untrusted JSON — a
    // value typed as num/bool by the writer must never crash an
    // `as String?` cast. Stringify defensively and trim.
    final rawName = meta is Map<String, dynamic>
        ? (meta['full_name'] ?? meta['name'])?.toString()
        : null;
    final name = (rawName?.trim().isNotEmpty ?? false) ? rawName!.trim() : null;
    return (email: u.email!, fullName: name);
  }
}
