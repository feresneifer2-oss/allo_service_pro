import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/network/connectivity_store.dart';
import '../../admin/application/admin_store.dart';
import 'supabase_auth_service.dart';
import 'user_store.dart';

/// Phase 7-5: background service that keeps the Pro's verification status
/// fresh without blocking the UI.
///
/// - On success: sets audit (unconfirmed=false, source=server, timestamp=now).
/// - On failure: sets unconfirmed=true (does NOT downgrade an approved status).
/// - Retries with exponential backoff (1s / 2s / 4s, 3 attempts total).
/// - Triggers: app resume, connectivity rejoin, boot, post-login.
///
/// ISOLATION CONTRACT: this service performs NO server fetches itself — the
/// single remote entry point is [AdminStore.syncSessionStoresForCurrentUser].
/// The "unconfirmed vs downgrade" authority logic lives in
/// `AdminStore._applyServerVerificationAuthority` (Phase 7-5 P5).
abstract final class VerificationSyncService {
  VerificationSyncService._();

  /// Total number of attempts per sync call (1 initial + 2 retries).
  static const int maxAttempts = 3;

  /// Exponential backoff between attempts.
  static const List<Duration> _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// Cache TTL: after this duration, a confirmed status is considered
  /// stale and a fresh sync is triggered on next app resume.
  static const Duration cacheTtl = Duration(minutes: 5);

  /// Prevents overlapping syncs.
  static bool _inFlight = false;

  /// Registered once at boot.
  static bool _initialized = false;

  /// Single lifecycle observer instance (so debugReset can detach it).
  static final _LifecycleObserver _observer = _LifecycleObserver();

  // ── Public API ─────────────────────────────────────────────────────

  /// Boot hook: subscribe to lifecycle + connectivity. Idempotent.
  static void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(_observer);
    ConnectivityStore.isOnline.addListener(_onConnectivityChanged);
    // Initial nudge: only if we already have a professional session.
    unawaited(syncNow());
  }

  /// Manually trigger a sync. Idempotent under concurrency.
  /// Returns true when the server-confirmed status was applied.
  static Future<bool> syncNow({bool force = false}) async {
    if (_inFlight) return false;

    // Guard: configured + professional session only.
    if (!SupabaseAuthService.isConfigured) return false;
    final user = UserStore.user.value;
    if (user == null || !user.isProfessional) return false;

    // TTL check (unless forced).
    if (!force) {
      // Phase 7-5 (P5d): an UNCONFIRMED session must NEVER be skipped by
      // the TTL — we retry until the server answers. Otherwise a stale
      // unconfirmed state would persist forever on non-forced calls
      // (boot / resume / connectivity).
      if (!user.verificationUnconfirmed) {
        final lastMs = user.verificationLastCheckedAtMs;
        if (lastMs != null &&
            user.verificationSource == VerificationSource.server &&
            DateTime.now().millisecondsSinceEpoch - lastMs <
                cacheTtl.inMilliseconds) {
          return true; // fresh enough
        }
      }
    }

    _inFlight = true;
    try {
      return await _syncInternal(force).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('VerificationSyncService.syncNow timed out after 30s');
          }
          return false;
        },
      );
    } finally {
      _inFlight = false;
    }
  }

  static Future<bool> _syncInternal(bool force) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await AdminStore.syncSessionStoresForCurrentUser();
        // P5b: the audit is marked INSIDE
        // AdminStore._applyServerVerificationAuthority — confirmed on a
        // clean answer, unconfirmed on a transient failure. Do NOT
        // re-mark it here: a local _markConfirmed() would flip a failed
        // read straight back to confirmed. Success = the session
        // carries a CONFIRMED answer.
        final u = UserStore.user.value;
        if (u != null && !u.verificationUnconfirmed) {
          return true;
        }
        // Unconfirmed (transient failure) → backoff and retry.
        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(_backoff[attempt]);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'VerificationSyncService attempt ${attempt + 1} failed: $e');
        }
        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(_backoff[attempt]);
        }
      }
    }
    // All attempts failed: the authority logic already PRESERVED the
    // status (never downgraded) — defensively flag unconfirmed
    // (idempotent) and report failure.
    await _markUnconfirmed();
    return false;
  }

  // ── Internals ──────────────────────────────────────────────────────

  static Future<void> _markUnconfirmed() async {
    final user = UserStore.user.value;
    if (user == null) return;
    // Keep source + timestamp as-is (they reflect the last GOOD read).
    UserStore.user.value = user.withVerificationAudit(
      unconfirmed: true,
      source: user.verificationSource,
      lastCheckedAtMs: user.verificationLastCheckedAtMs,
    );
    await UserStore.persistToPrefs();
  }

  static void _onConnectivityChanged() {
    if (ConnectivityStore.isOnline.value) {
      // Phase 7-5 (P6b): coming back online is a STATE TRANSITION — force a
      // fresh read instead of being skipped by the TTL.
      unawaited(syncNow(force: true));
    }
  }

  @visibleForTesting
  static void debugReset() {
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(_observer);
      ConnectivityStore.isOnline.removeListener(_onConnectivityChanged);
    }
    _initialized = false;
    _inFlight = false;
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(VerificationSyncService.syncNow());
    }
  }
}
