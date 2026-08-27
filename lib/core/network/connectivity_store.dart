import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Global network-status store powering the Uber-style offline overlay.
/// Initialized once at app startup; every screen reads the same [isOnline]
/// notifier, so the overlay and any UI can react instantly to network drops
/// and restorations.
class ConnectivityStore {
  ConnectivityStore._();

  /// True while the device has any usable network interface.
  static final isOnline = ValueNotifier<bool>(true);

  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static bool _initialized = false;

  /// Starts listening. Safe to call multiple times (idempotent).
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _sub = Connectivity().onConnectivityChanged.listen(_evaluate);
    checkNow();
  }

  /// Manual re-check used by the overlay's "Retry" button.
  static Future<void> checkNow() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _evaluate(results);
    } catch (_) {
      // Plugin unavailable (e.g. tests / early startup): keep last state.
    }
  }

  static void _evaluate(List<ConnectivityResult> results) {
    final online = results.isNotEmpty &&
        results.any((r) => r != ConnectivityResult.none);
    isOnline.value = online;
  }

  /// Test hook: flips the global online state without touching plugins.
  @visibleForTesting
  static void debugSetOnline(bool online) => isOnline.value = online;

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
