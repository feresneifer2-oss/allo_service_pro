import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';

import 'queued_action.dart';

/// Result summary of one [OfflineQueue.flush] pass (tests + diagnostics).
@immutable
class FlushReport {
  const FlushReport({
    this.applied = 0,
    this.dropped = 0,
    this.retried = 0,
  });

  final int applied;
  final int dropped;
  final int retried;

  bool get isEmpty => applied == 0 && dropped == 0 && retried == 0;

  @override
  String toString() =>
      'FlushReport(applied=$applied, dropped=$dropped, retried=$retried)';
}

/// Durable, FIFO queue of business-critical operations performed while the
/// device had no usable network — so a dropped connection NEVER loses a
/// service provider's work ("zero data loss").
///
/// DESIGN:
///  * **Store-agnostic.** The queue knows nothing about orders: callers enqueue
///    a [QueuedActionType] + JSON payload and a registered
///    [QueuedActionExecutor] replays it. Domain wiring lives in
///    `offline_queue_bindings.dart`, so neither side imports the other
///    (no import cycle, no coupling).
///  * **Persisted.** Every mutation (enqueue / attempt / drop) is written to
///    SharedPreferences, so pending work survives a kill or a restart.
///  * **Automatic replay.** [init] subscribes to [ConnectivityStore.isOnline]
///    and flushes the moment connectivity returns — no user action required.
///  * **Bounded.** A transient failure is retried at most [maxAttempts] times,
///    then the entry is dropped WITH an error log, so a poisoned payload can
///    never block the queue forever.
///  * **Order-preserving.** A pass stops at the first transient failure, so
///    operations on the same order are never applied out of order. Pending
///    actions are ordered by [QueuedAction.compareTo] (monotonic sequence
///    first, then the timestamp), so operations keep their strict FIFO order —
///    even those enqueued within the same millisecond, across a restart.
///
/// Everything is guarded through [AppErrorHandler]/[AppLogger]: a queue problem
/// can never crash a screen.
class OfflineQueue {
  OfflineQueue._();

  static const String prefsKey = 'offline_action_queue';

  /// Transient failures tolerated per entry before it is dropped.
  static const int maxAttempts = 5;

  /// Operations still waiting for a successful replay (oldest first).
  static final ValueNotifier<List<QueuedAction>> pending =
      ValueNotifier<List<QueuedAction>>(<QueuedAction>[]);

  /// True while a [flush] pass is running (the UI may show a sync indicator).
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Last completed pass, for diagnostics/tests.
  static FlushReport? lastReport;

  static final Map<QueuedActionType, QueuedActionExecutor> _executors =
      <QueuedActionType, QueuedActionExecutor>{};

  static bool _initialized = false;
  static bool _flushing = false;

  /// Whether automatic replay is armed.
  static bool get isInitialized => _initialized;

  /// Number of operations waiting for replay.
  static int get length => pending.value.length;

  static bool get isEmpty => pending.value.isEmpty;

  /// Registers the executor for [type]. Registering twice replaces the handler
  /// (tests / environment swaps).
  static void registerExecutor(
    QueuedActionType type,
    QueuedActionExecutor executor,
  ) {
    _executors[type] = executor;
    AppLogger.debug('OfflineQueue', 'executor registered for ${type.name}');
  }

  /// Arms the queue: loads persisted work and starts listening for
  /// connectivity restoration. Idempotent.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    ConnectivityStore.isOnline.addListener(_onConnectivityChanged);
    await loadFromPrefs();
    AppLogger.info(
      'OfflineQueue',
      'armed (${pending.value.length} operation(s) pending)',
    );
    // Booting back online with leftover work (e.g. killed mid-sync) drains now.
    if (ConnectivityStore.isOnline.value && pending.value.isNotEmpty) {
      unawaited(flush());
    }
  }

  /// Detaches the connectivity listener (logout / test teardown).
  static Future<void> dispose() async {
    ConnectivityStore.isOnline.removeListener(_onConnectivityChanged);
    _initialized = false;
  }

  /// Queues [action] for later replay. Returns false only when the action is
  /// unusable (no id, or no executor registered for its type).
  static Future<bool> enqueue(QueuedAction action) async {
    if (action.id.trim().isEmpty) {
      AppLogger.error('OfflineQueue', 'refused to queue an action without id');
      return false;
    }
    if (!_executors.containsKey(action.type)) {
      AppLogger.error(
        'OfflineQueue',
        'refused to queue ${action.type.name}: no executor registered',
      );
      return false;
    }
    pending.value = <QueuedAction>[...pending.value, action];
    await persistToPrefs();
    AppLogger.warn(
      'OfflineQueue',
      'queued ${action.type.name} (${action.targetOrderId ?? '-'}) — '
      '${pending.value.length} pending',
    );
    return true;
  }

  /// Replays every pending operation, oldest first.
  ///
  /// Stops at the first entry reporting [QueueExecutionResult.retry] so a
  /// per-order ordering is preserved; that entry keeps its place for the next
  /// connectivity window. [QueueExecutionResult.drop] entries are discarded and
  /// logged as errors. Never throws, and returns a [FlushReport] summary.
  static Future<FlushReport> flush() async {
    if (_flushing) return const FlushReport();
    if (pending.value.isEmpty) return const FlushReport();
    if (_executors.isEmpty) {
      AppLogger.warn('OfflineQueue', 'flush skipped: no executors registered');
      return const FlushReport();
    }

    _flushing = true;
    isSyncing.value = true;

    var applied = 0;
    var dropped = 0;
    var retried = 0;

    try {
      for (final action in List<QueuedAction>.from(pending.value)) {
        final executor = _executors[action.type];
        if (executor == null) {
          // A type nobody can replay (legacy storage): drop, never block.
          _remove(action.id);
          dropped += 1;
          AppLogger.error(
            'OfflineQueue',
            'dropped ${action.type.name}: no executor registered',
          );
          continue;
        }

        QueueExecutionResult result;
        try {
          result = await executor(action);
        } catch (error, stackTrace) {
          // A throwing executor is a transient failure, never fatal here.
          AppErrorHandler.report(
            error,
            stackTrace,
            context: 'OfflineQueue.flush(${action.type.name})',
          );
          result = QueueExecutionResult.retry;
        }

        var stop = false;
        switch (result) {
          case QueueExecutionResult.applied:
            _remove(action.id);
            applied += 1;
            AppLogger.info(
              'OfflineQueue',
              'replayed ${action.type.name} (${action.targetOrderId ?? '-'})',
            );
          case QueueExecutionResult.drop:
            _remove(action.id);
            dropped += 1;
            AppLogger.error(
              'OfflineQueue',
              'dropped ${action.type.name} (${action.targetOrderId ?? '-'}): '
              'not replayable',
            );
          case QueueExecutionResult.retry:
            retried += 1;
            final attempts = action.attempts + 1;
            if (attempts >= maxAttempts) {
              _remove(action.id);
              dropped += 1;
              AppLogger.error(
                'OfflineQueue',
                'gave up on ${action.type.name} '
                '(${action.targetOrderId ?? '-'}) after $attempts attempts',
              );
            } else {
              _replace(action.copyWith(
                attempts: attempts,
                lastError: 'transient failure',
              ));
              // Preserve FIFO ordering: stop this pass on a transient failure.
              stop = true;
            }
        }
        if (stop) break;
      }
    } catch (error, stackTrace) {
      AppErrorHandler.report(error, stackTrace, context: 'OfflineQueue.flush');
    } finally {
      _flushing = false;
      isSyncing.value = false;
      await persistToPrefs();
    }

    final report =
        FlushReport(applied: applied, dropped: dropped, retried: retried);
    lastReport = report;
    if (applied > 0 || dropped > 0) {
      AppLogger.info('OfflineQueue', 'flush done: $report');
    }
    return report;
  }

  /// Restores pending work from storage (called by [init] and by tests).
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <QueuedAction>[];
      var position = 0;
      for (final entry in decoded) {
        // The position doubles as the sequence fallback of a legacy entry that
        // predates `seq`: the persisted array IS the enqueue order, so a queue
        // written by an older build keeps its exact FIFO order.
        final action = QueuedAction.fromJson(entry, fallbackSeq: position);
        position++;
        if (action == null) {
          // Corrupted/legacy entry: dropped, the rest of the queue survives.
          AppLogger.warn('OfflineQueue', 'discarded a malformed queued action');
          continue;
        }
        restored.add(action);
      }
      // Single ordering rule: the monotonic sequence FIRST (it is the true
      // insertion order, even across a relaunch), then the timestamp — so two
      // operations created within the same millisecond always replay in the
      // order they were enqueued (see [QueuedAction.compareTo]).
      restored.sort((a, b) => a.compareTo(b));
      pending.value = restored;
    } catch (error, stackTrace) {
      AppErrorHandler.report(error, stackTrace,
          context: 'OfflineQueue.loadFromPrefs');
    }
  }

  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode(pending.value.map((a) => a.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort: an unavailable storage layer must not break the in-memory
      // queue (the operation stays pending for this session).
    }
  }

  /// Drops every pending operation (logout / test isolation).
  static Future<void> clear() async {
    pending.value = <QueuedAction>[];
    lastReport = null;
    await persistToPrefs();
  }

  /// Test hook: full teardown — queue, executors and the connectivity listener.
  @visibleForTesting
  static Future<void> debugReset() async {
    await dispose();
    _executors.clear();
    _flushing = false;
    isSyncing.value = false;
    await clear();
  }

  static void _onConnectivityChanged() {
    if (ConnectivityStore.isOnline.value && pending.value.isNotEmpty) {
      AppLogger.info('OfflineQueue', 'connectivity restored — replaying');
      unawaited(flush());
    }
  }

  static void _remove(String id) {
    pending.value =
        pending.value.where((a) => a.id != id).toList(growable: false);
  }

  static void _replace(QueuedAction action) {
    pending.value = pending.value
        .map((a) => a.id == action.id ? action : a)
        .toList(growable: false);
  }
}