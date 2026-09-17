import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/constants/app_constants.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';

/// Silently tracks client cancellations and enforces the 50-cancellation
/// auto-ban policy.
///
/// ARCHITECTURE:
/// - **Silent by design.** The cancellation counter is NEVER surfaced in the
///   UI. Clients do not see a visible tally, a warning badge, or a progress
///   indicator. The only consumer of the count is this store itself.
/// - **Scope:** counters are keyed by a stable client identity (e-mail when
///   present, otherwise the account id) so they survive app restarts and
///   re-logins.
/// - **Threshold:** when a client's count reaches
///   [AppConstants.antiAbuseCancellationLimit], they are immediately banned:
///   [onSessionTerminated] forces a session logout and the app intercepts
///   navigation with [showBanGate].
/// - **Irreversible locally:** a ban persists until an explicit [reset]
///   (tests) or a server-side reinstatement.
class AntiAbuseStore {
  AntiAbuseStore._();

  static const String _kKey = 'anti_abuse_cancellations';
  static const String _kBannedKey = 'anti_abuse_banned_clients';

  /// Currently-signed-in client identity. Null = no active client.
  static String? _activeClientId;

  /// In-memory cancellation counts. Persisted so counts survive restarts.
  static final Map<String, int> _counts = {};

  /// Set of client identities that have been auto-banned.
  static final Set<String> _bannedIds = {};

  /// Whether the auto-ban gate should intercept navigation.
  static final ValueNotifier<bool> showBanGate = ValueNotifier<bool>(false);

  /// Production/test seam: invoked after a client is auto-banned so the
  /// session can be wiped without this store importing [UserStore]
  /// (avoids a feature-layer cycle).
  static Future<void> Function()? onSessionTerminated;

  /// The client identity that triggered the ban (for diagnostics / testing).
  static String? get bannedClientId =>
      _bannedIds.isNotEmpty ? _bannedIds.first : null;

  /// Active client identity (null when no client session is bound).
  static String? get activeClientId => _activeClientId;

  /// Binds the silent counter to the live client session.
  ///
  /// Professional sessions are ignored (and any previous client binding is
  /// cleared) so a pro confirming/cancelling from the dashboard can never
  /// increment their own anti-abuse tally. When [email] is present it is
  /// preferred as the stable key so a fresh `user_*` id on re-login still
  /// hits the same counter.
  static void bindSession({required String id, String? email}) {
    final trimmedEmail = email?.trim().toLowerCase();
    final stable = (trimmedEmail != null && trimmedEmail.isNotEmpty)
        ? trimmedEmail
        : id.trim();
    if (stable.isEmpty) return;

    // Fold a previous id-keyed tally into the stable identity.
    if (stable != id && _counts.containsKey(id)) {
      _counts[stable] = (_counts[stable] ?? 0) + (_counts.remove(id) ?? 0);
    }
    if (stable != id && _bannedIds.remove(id)) {
      _bannedIds.add(stable);
    }

    _activeClientId = stable;
    if (_bannedIds.contains(stable)) {
      showBanGate.value = true;
    }
  }

  /// Sets the active client ID. Call on login.
  static void setActiveClient(String clientId) {
    final id = clientId.trim();
    if (id.isEmpty) {
      _activeClientId = null;
      return;
    }
    _activeClientId = id;
    if (_bannedIds.contains(id)) {
      showBanGate.value = true;
    }
  }

  /// Clears the active client on a normal logout. A live ban gate keeps the
  /// identity so [isCurrentlyBanned] stays true until the user acknowledges.
  static void clearActiveClient() {
    if (showBanGate.value) return;
    _activeClientId = null;
  }

  /// Returns the cancellation count for the active client (0 if never seen).
  static int get count => _counts[_activeClientId] ?? 0;

  /// Returns the cancellation count for a specific client identity.
  static int countFor(String clientId) => _counts[clientId] ?? 0;

  /// Returns whether a client is currently banned.
  static bool isBanned(String? clientId) =>
      clientId != null &&
      clientId.isNotEmpty &&
      _bannedIds.contains(clientId);

  /// Checks whether the active client is currently banned.
  static bool get isCurrentlyBanned =>
      _activeClientId != null && _bannedIds.contains(_activeClientId);

  /// Records a silent cancellation.
  ///
  /// When a client session is bound, the active identity is authoritative
  /// (stable e-mail key). Otherwise [clientId] — typically the order's
  /// `customerId` — is used so a cancellation applied without a client
  /// session still counts against the owner of the order.
  static Future<void> recordCancellation({String? clientId}) async {
    final resolved = _activeClientId ??
        ((clientId != null && clientId.trim().isNotEmpty)
            ? clientId.trim()
            : null);
    if (resolved == null || resolved.isEmpty) {
      AppLogger.debug(
        'AntiAbuse',
        'recordCancellation called with no client identity — ignored.',
      );
      return;
    }

    final incremented = (_counts[resolved] ?? 0) + 1;
    _counts[resolved] = incremented;

    AppLogger.info(
      'AntiAbuse',
      'Silent cancellation recorded for $resolved — total: $incremented',
    );

    await _persist();

    if (incremented >= AppConstants.antiAbuseCancellationLimit) {
      await _banClient(resolved);
    }
  }

  /// Dismisses the intercepting gate after the user acknowledges it.
  /// Does NOT lift the ban — a later login still re-opens the gate.
  static void acknowledgeBanGate() {
    showBanGate.value = false;
    _activeClientId = null;
  }

  /// Internal: bans a client, intercepts navigation, and terminates the session.
  static Future<void> _banClient(String clientId) async {
    _bannedIds.add(clientId);
    showBanGate.value = true;

    AppLogger.warn(
      'AntiAbuse',
      'CLIENT AUTO-BANNED after reaching '
      '${AppConstants.antiAbuseCancellationLimit} cancellations '
      '(clientId: $clientId). Session cleared.',
    );

    await _persistBanned();

    final terminate = onSessionTerminated;
    if (terminate != null) {
      try {
        await terminate();
      } catch (error, stackTrace) {
        AppLogger.error(
          'AntiAbuse',
          'Session termination after auto-ban failed',
          error,
          stackTrace,
        );
      }
    }
  }

  /// Loads persisted cancellation counts and bans from SharedPreferences.
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bannedIds
        ..clear()
        ..addAll(prefs.getStringList(_kBannedKey)?.toSet() ?? {});

      final saved = prefs.getString(_kKey);
      if (saved == null) return;
      _counts.clear();
      _readCounts(saved);
    } catch (error, stackTrace) {
      AppLogger.error(
        'AntiAbuse',
        'Failed to load stored cancellation counts',
        error,
        stackTrace,
      );
    }
  }

  static void _readCounts(String saved) {
    try {
      final decoded = jsonDecode(saved);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is! String || key.isEmpty) return;
          final n = value is int ? value : int.tryParse('$value');
          if (n != null && n > 0) _counts[key] = n;
        });
        return;
      }
    } catch (_) {
      // Legacy pipe-delimited payload — parsed below.
    }
    for (final part in saved.split('|')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final id = kv[0];
      final n = int.tryParse(kv[1]);
      if (id.isNotEmpty && n != null) {
        _counts[id] = n;
      }
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, int>{
        for (final e in _counts.entries)
          if (e.value > 0) e.key: e.value,
      };
      await prefs.setString(_kKey, jsonEncode(payload));
    } catch (error, stackTrace) {
      AppLogger.error(
        'AntiAbuse',
        'Failed to persist cancellation count',
        error,
        stackTrace,
      );
    }
  }

  static Future<void> _persistBanned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kBannedKey, _bannedIds.toList());
    } catch (error, stackTrace) {
      AppLogger.error(
        'AntiAbuse',
        'Failed to persist ban list',
        error,
        stackTrace,
      );
    }
  }

  /// Full reset: clears all counters, bans, and active client.
  /// Used in tests and never on a production logout (bans must survive).
  static Future<void> reset() async {
    _counts.clear();
    _bannedIds.clear();
    showBanGate.value = false;
    _activeClientId = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
      await prefs.remove(_kBannedKey);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Test hook: force the active client to appear banned.
  @visibleForTesting
  static void debugForceBan(String clientId) {
    _activeClientId = clientId;
    _bannedIds.add(clientId);
    showBanGate.value = true;
  }

  /// Test hook: simulate N cancellations for the active client.
  @visibleForTesting
  static Future<void> debugRecordCancellations(int n) async {
    for (var i = 0; i < n; i++) {
      await recordCancellation();
    }
  }

  /// Test hook: clears only the in-memory state, forcing the next
  /// [loadFromPrefs] to restore from disk.
  @visibleForTesting
  static void debugClearMemory() {
    _counts.clear();
    _bannedIds.clear();
    showBanGate.value = false;
  }
}
