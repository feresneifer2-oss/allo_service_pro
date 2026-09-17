import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal push-notification service for Allo Service Pro.
///
/// Wraps the OneSignal v5 SDK behind a tiny static facade so the rest of
/// the app never touches the plugin directly:
///
///  * [appId] is resolved from `--dart-define=ONESIGNAL_APP_ID=<id>` and
///    falls back to a clearly-marked placeholder — the SDK is skipped
///    entirely until a real ID is supplied (no crash, no stray network).
///  * [initialize] is idempotent AND single-flight: concurrent callers join
///    the in-flight attempt instead of racing the SDK, and the whole thing is
///    guarded so unit/widget tests (no native plugin) simply no-op instead of
///    throwing.
///  * [login]/[logout]/[addEmail] associate the app's own user identity
///    (user id / email) with the OneSignal user model.
///  * [playerId] (push subscription id, ex-"Player ID") and [externalId]
///    are exposed for later Supabase sync of device tokens.
///
/// Typical wiring:
/// ```dart
/// await OneSignalService.initialize();            // main.dart, after binding
/// await OneSignalService.login(user.id);          // after sign-in / register
/// await OneSignalService.addEmail(user.email);    // optional, post-consent
/// final token = await OneSignalService.playerId;  // sync to Supabase
/// await OneSignalService.logout();                // on sign-out
/// ```
class OneSignalService {
  OneSignalService._();

  /// Placeholder used until a real OneSignal App ID is provided via
  /// `--dart-define=ONESIGNAL_APP_ID=<your-app-id>`.
  static const String placeholderAppId = 'ONESIGNAL_APP_ID';

  /// Resolved App ID: compile-time define wins, placeholder otherwise.
  static const String appId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: placeholderAppId,
  );

  /// True once [initialize] has completed (even if it skipped for tests).
  static bool get isInitialized => _initialized;
  static bool _initialized = false;

  /// The in-flight initialization attempt, if any — the SINGLE-FLIGHT LOCK.
  ///
  /// [initialize] is check-then-act on [_initialized], so two callers arriving
  /// in the same turn (startup plus a login-triggered retry, or two screens
  /// restoring a session at once) would both start the SDK and race the native
  /// layer. A caller that finds an attempt in flight awaits THIS future instead
  /// of starting a second one.
  static Completer<void>? _initCompleter;

  /// How many attempts actually entered the locked section.
  static int _initAttempts = 0;

  /// Test hook: number of real initialization attempts performed.
  @visibleForTesting
  static int get debugInitAttempts => _initAttempts;

  /// Test hook: true while an initialization attempt holds the lock.
  @visibleForTesting
  static bool get debugInitInFlight => _initCompleter != null;

  /// Test-only delay injected while the lock is held, so a test can keep two
  /// concurrent [initialize] calls genuinely overlapping.
  ///
  /// `Duration.zero` (the default) NEVER yields: the guarded wait below is a
  /// debug-only no-op. Not touched by [debugReset], so a test owns restoring it.
  @visibleForTesting
  static Duration debugInitDelay = Duration.zero;

  /// Whether a real App ID is configured (vs. the placeholder).
  static bool get isConfigured => appId.isNotEmpty && appId != placeholderAppId;

  /// Initializes the OneSignal SDK.
  ///
  /// The native push-permission prompt is intentionally fire-and-forget
  /// ([requestPushPermission]): awaiting it would stall app startup while
  /// the OS dialog sits open. Safe to call multiple times — a second call
  /// either no-ops (already initialized) or JOINS the attempt already running
  /// — and safe in tests: without the native plugin it simply no-ops.
  /// Never throws, and never leaves an awaiting caller hanging.
  static Future<void> initialize() async {
    if (_initialized) return;

    // Single-flight: an attempt is already running, so this caller becomes a
    // joiner instead of racing it (two SDK initializations in one turn is
    // exactly the race this lock exists to prevent).
    final inFlight = _initCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      await _initializeLocked();
    } finally {
      // Released in a `finally`: whatever the attempt did, no joiner may be
      // left waiting on a future that can no longer complete.
      _initCompleter = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// The actual (single) initialization, run by the caller that WON the lock.
  ///
  /// Failure is non-fatal and retryable: [_initialized] is only flipped after
  /// the SDK call succeeded, so a later [initialize] can try again cleanly.
  static Future<void> _initializeLocked() async {
    _initAttempts += 1;

    // Test seam (debug builds only, no-op by default): keeps the lock
    // observably held so a test can prove the serialization.
    if (kDebugMode && debugInitDelay > Duration.zero) {
      await Future<void>.delayed(debugInitDelay);
    }

    // Unit/widget tests run without the native plugin: skip early.
    if (_isTestEnvironment) {
      _initialized = true;
      debugPrint('[OneSignal] skipped: running in test environment.');
      return;
    }

    if (!isConfigured) {
      _initialized = true;
      debugPrint(
        '[OneSignal] skipped: no App ID configured. '
        'Pass --dart-define=ONESIGNAL_APP_ID=<id> to enable push.',
      );
      return;
    }

    try {
      // Verbose SDK logs only in debug builds.
      if (kDebugMode) {
        await OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      }
      await OneSignal.initialize(appId);
      // CodeRabbit: mark the SDK ready STRICTLY after initialize() has
      // completed successfully — never preemptively. A failure here keeps
      // the flag false so a later initialize() call can retry cleanly.
      _initialized = true;
      // Fire-and-forget: must never block startup (CodeRabbit).
      unawaited(requestPushPermission());
    } catch (e) {
      // Startup must never fail because push is unavailable. The flag
      // stays false: `_readyForUserCalls` keeps user-facing calls off,
      // and initialize() may be retried later (e.g. after login).
      debugPrint('[OneSignal] initialize failed (non-fatal): $e');
    }
  }

  /// Prompts the native push-permission dialog (Android 13+ / iOS).
  ///
  /// Fire-and-forget by design — returns immediately and resolves to the
  /// user's choice in the background. Call any time after [initialize]
  /// (e.g. from onboarding or settings) without blocking the caller.
  /// Never throws; resolves to false when unavailable.
  static Future<bool> requestPushPermission() async {
    if (!_readyForUserCalls) return false;
    try {
      return await OneSignal.Notifications.requestPermission(true);
    } catch (e) {
      debugPrint('[OneSignal] requestPermission failed (non-fatal): $e');
      return false;
    }
  }

  /// Associates the signed-in app user with OneSignal.
  ///
  /// Call right after login/register with a stable id (user id or email).
  /// No-op (never throws) when uninitialized or in tests.
  static Future<void> login(String externalId) async {
    if (!_readyForUserCalls) return;
    final id = externalId.trim();
    if (id.isEmpty) return;
    try {
      await OneSignal.login(id);
    } catch (e) {
      debugPrint('[OneSignal] login failed (non-fatal): $e');
    }
  }

  /// Switches back to a device-scoped user. Call on sign-out.
  static Future<void> logout() async {
    if (!_readyForUserCalls) return;
    try {
      await OneSignal.logout();
    } catch (e) {
      debugPrint('[OneSignal] logout failed (non-fatal): $e');
    }
  }

  /// Adds an email subscription to the current OneSignal user.
  ///
  /// Call only after the user consented to email communication. No-op on
  /// invalid addresses, in tests, or when uninitialized. Never throws.
  static Future<void> addEmail(String email) async {
    if (!_readyForUserCalls) return;
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) return;
    try {
      await OneSignal.User.addEmail(address);
    } catch (e) {
      debugPrint('[OneSignal] addEmail failed (non-fatal): $e');
    }
  }

  /// Current push subscription id (formerly "Player ID"), or null when
  /// unavailable (tests, unconfigured, permission denied). Never throws.
  ///
  /// Persist this alongside the app user row in Supabase to target devices
  /// server-side later.
  static Future<String?> get playerId async {
    if (!_readyForUserCalls) return null;
    try {
      return OneSignal.User.pushSubscription.id;
    } catch (e) {
      debugPrint('[OneSignal] playerId read failed (non-fatal): $e');
      return null;
    }
  }

  /// The external id currently associated via [login], or null.
  /// Never throws.
  static Future<String?> get externalId async {
    if (!_readyForUserCalls) return null;
    try {
      return await OneSignal.User.getExternalId();
    } catch (e) {
      debugPrint('[OneSignal] externalId read failed (non-fatal): $e');
      return null;
    }
  }

  /// Test hook: resets the initialized flag without touching the plugin.
  @visibleForTesting
  static void debugReset() {
    _initialized = false;
    _initCompleter = null;
    _initAttempts = 0;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// True only when calls may reach the native SDK: initialized, configured,
  /// and not running under flutter_test.
  static bool get _readyForUserCalls =>
      _initialized && isConfigured && !_isTestEnvironment;

  /// Detects flutter_test without importing package:flutter_test (which is
  /// banned outside tests). The test binding class name contains "Test";
  /// the assert block is tree-shaken out of release builds.
  static bool get _isTestEnvironment {
    var inTest = false;
    assert(() {
      try {
        final binding = WidgetsBinding.instance;
        inTest = binding.runtimeType.toString().contains('Test');
      } catch (_) {
        inTest = true;
      }
      return true;
    }());
    return inTest;
  }
}
