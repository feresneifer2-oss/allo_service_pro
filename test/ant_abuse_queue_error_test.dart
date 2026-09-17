import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/constants/app_constants.dart';
import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/offline_queue_bindings.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
import 'package:allo_service_pro/features/anti_abuse/application/anti_abuse_bindings.dart';
import 'package:allo_service_pro/features/anti_abuse/application/anti_abuse_store.dart';
import 'package:allo_service_pro/features/anti_abuse/presentation/ban_gate_screen.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/anti_abuse_gate.dart';
import 'package:allo_service_pro/shared/widgets/error_fallback_view.dart';

/// A test sink that always throws — verifies the logger never propagates
/// a sink failure back to the caller.
class _BrokenSink implements LogSink {
  @override
  bool get isConfigured => true;

  @override
  Future<void> write(LogRecord record) async {
    throw Exception('sink is broken');
  }
}

/// Builds a queue action with the standard (business) payload shape, at a
/// FIXED timestamp by default — so same-millisecond ordering can be exercised
/// deterministically.
QueuedAction _queuedAction(
  String id, {
  Map<String, dynamic>? payload,
  int createdAtMs = 1700000000000,
}) =>
    QueuedAction(
      id: id,
      type: QueuedActionType.updateOrderStatus,
      payload: payload ??
          <String, dynamic>{'requestId': 'req-$id', 'status': 'accepted'},
      createdAtMs: createdAtMs,
    );

void main() {
  setUp(() async {
    await AntiAbuseStore.reset();
    AppLogger.muteConsole = true;
    AppLogger.clear();
    AppErrorHandler.clear();
    AppErrorHandler.debugReset();
    SharedPreferences.setMockInitialValues({});
    UserStore.user.value = null;
    RequestStore.requests.value = [];
    ConnectivityStore.debugSetOnline(true);
    AntiAbuseStore.onSessionTerminated = null;
    // Keep the global locale deterministic for trGlobal-based widgets.
    appLocale.value = const Locale('fr');
  });

  tearDown(() async {
    AppLogger.muteConsole = true;
    await OfflineQueue.debugReset();
    await AntiAbuseStore.reset();
    AntiAbuseStore.onSessionTerminated = null;
    UserStore.user.value = null;
    RequestStore.requests.value = [];
    ConnectivityStore.debugSetOnline(true);
    appLocale.value = const Locale('fr');
  });

  // ─── 1. Global Error Handling & Logger ────────────────────────────────
  group('Global Error Handling & Logger', () {
    test('AppErrorHandler.report stores the error in lastError', () {
      AppErrorHandler.install(force: true);
      expect(AppErrorHandler.lastError.value, isNull);

      AppErrorHandler.report(Exception('test failure'), StackTrace.current,
          context: 'test');

            expect(AppErrorHandler.lastError.value, isA<Exception>());
      expect(AppLogger.errors.length, 1);
      expect(AppLogger.errors.first.tag, 'AppError');
    });

    test('AppErrorHandler.runGuarded returns null on failure', () async {
      AppErrorHandler.install(force: true);
      final result = await AppErrorHandler.runGuarded('test', () async {
        throw Exception('async failure');
      });

      expect(result, isNull);
      expect(AppLogger.errors.length, 1);
    });

    test('AppErrorHandler.runGuardedSync catches synchronous errors', () {
      AppErrorHandler.install(force: true);
      final result = AppErrorHandler.runGuardedSync('test-sync', () {
        throw Exception('sync failure');
      });

      expect(result, isNull);
      expect(AppLogger.errors.length, 1);
    });

    test('AppLogger retains up to maxHistory records', () {
      AppLogger.clear();
      for (var i = 0; i < AppLogger.maxHistory + 10; i++) {
        AppLogger.info('TestTag', 'message $i');
      }

      expect(AppLogger.history.value.length, AppLogger.maxHistory);
      expect(AppLogger.history.value.first.message,
          'message ${AppLogger.maxHistory + 9}');
    });

    test('AppLogger logSink failure never breaks the caller', () async {
      AppLogger.debugSetSink(_BrokenSink());
      AppLogger.error('TestTag', 'message', Exception('err'));

      expect(AppLogger.errors.length, 1);
      AppLogger.debugSetSink(null);
    });

    test('minLevel filters out lower-severity logs', () {
      AppLogger.clear();
      AppLogger.minLevel = LogLevel.warning;
      AppLogger.debug('Low', 'debug message');
      AppLogger.info('Low', 'info message');
      AppLogger.warn('Hi', 'warn message');

      expect(AppLogger.history.value.length, 1);
      expect(AppLogger.history.value.first.message, 'warn message');
      AppLogger.minLevel = LogLevel.debug;
    });

    testWidgets('ErrorWidget.builder renders the branded fallback, not a red screen',
        (WidgetTester tester) async {
      // flutter_test verifies (by IDENTITY) that ErrorWidget.builder was not
      // left changed — and it does so right after the test body, BEFORE any
      // tearDown runs. So the exact pre-test instance must be restored inline.
      final savedErrorWidgetBuilder = ErrorWidget.builder;
      AppErrorHandler.install(force: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ErrorWidget.builder(
              FlutterErrorDetails(exception: Exception('boom')),
            ),
          ),
        ),
      );

      expect(find.byType(AppErrorFallback), findsOneWidget);
      expect(find.textContaining('Une erreur est survenue'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);

      ErrorWidget.builder = savedErrorWidgetBuilder;
    });
  });

  // ─── 2. Offline Queue ─────────────────────────────────────────────────
  group('Offline Queue', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OfflineQueue.debugReset();
      OfflineQueueBindings.registerAll();
    });

    test('enqueue adds an action', () async {
      final action = QueuedAction(
        id: 'test-1',
        type: QueuedActionType.updateOrderStatus,
        payload: {'requestId': 'req-1', 'status': 'completed'},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      final enqueued = await OfflineQueue.enqueue(action);
      expect(enqueued, isTrue);
      expect(OfflineQueue.length, 1);
      expect(OfflineQueue.pending.value.first.id, 'test-1');
    });

    test('flush replays and applies queued order status updates', () async {
      final request = ServiceRequest(
        id: 'req-1',
        serviceTitleFr: 'Test',
        serviceTitleAr: 'اختبار',
        professionalId: 'pro-1',
        professionalName: 'Test Pro',
        customerName: 'Client',
        customerId: 'client-1',
        dateTime: DateTime.now(),
        address: 'Tunis',
        message: 'Test request',
        createdAt: DateTime.now(),
      );
      RequestStore.add(request);

      final action = QueuedAction(
        id: 'test-flush-1',
        type: QueuedActionType.updateOrderStatus,
        payload: {'requestId': 'req-1', 'status': 'completed'},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await OfflineQueue.enqueue(action);

      final report = await OfflineQueue.flush();
      expect(report.applied, 1);
      expect(OfflineQueue.isEmpty, isTrue);

      final updated = RequestStore.byId('req-1');
      expect(updated?.status, RequestStatus.completed);
    });

    test('flush drops malformed payloads permanently', () async {
      final action = QueuedAction(
        id: 'malformed-1',
        type: QueuedActionType.updateOrderStatus,
        payload: {},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await OfflineQueue.enqueue(action);

      final report = await OfflineQueue.flush();
      expect(report.dropped, 1);
      expect(OfflineQueue.isEmpty, isTrue);
    });

    test('offline persistence survives restart', () async {
      final action = QueuedAction(
        id: 'persist-1',
        type: QueuedActionType.updateOrderStatus,
        payload: {'requestId': 'req-1', 'status': 'completed'},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await OfflineQueue.enqueue(action);

      await OfflineQueue.persistToPrefs();
      OfflineQueue.pending.value = [];

      await OfflineQueue.loadFromPrefs();

      expect(OfflineQueue.length, 1);
      expect(OfflineQueue.pending.value.first.id, 'persist-1');
    });

    test('offline status updates are queued and replayed when connectivity returns',
        () async {
      await OfflineQueue.init();
      ConnectivityStore.debugSetOnline(false);

      final request = ServiceRequest(
        id: 'req-offline-1',
        serviceTitleFr: 'Test',
        serviceTitleAr: 'اختبار',
        professionalId: 'pro-1',
        professionalName: 'Test Pro',
        customerName: 'Client',
        customerId: 'client-1',
        dateTime: DateTime.now(),
        address: 'Tunis',
        message: 'Test request',
        createdAt: DateTime.now(),
      );
      RequestStore.add(request);
      expect(
        RequestStore.updateStatus('req-offline-1', RequestStatus.accepted),
        isTrue,
      );
      expect(RequestStore.byId('req-offline-1')?.status, RequestStatus.accepted);
      expect(OfflineQueue.length, 1);

      ConnectivityStore.debugSetOnline(true);
      for (var i = 0; i < 40; i++) {
        if (OfflineQueue.isEmpty && !OfflineQueue.isSyncing.value) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (!OfflineQueue.isEmpty) {
        await OfflineQueue.flush();
      }

      expect(OfflineQueue.isEmpty, isTrue);
      expect(RequestStore.byId('req-offline-1')?.status, RequestStatus.accepted);
      ConnectivityStore.debugSetOnline(true);
    });
  });

  // ─── 2b. Offline Queue · snapshot & deterministic ordering ────────────
  group('Offline Queue · snapshot & deterministic ordering', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OfflineQueue.debugReset();
      OfflineQueueBindings.registerAll();
    });

    test('payload is a deep immutable snapshot, never a live view', () {
      final nested = <String, dynamic>{'note': 'original'};
      final action = _queuedAction(
        'snap-1',
        payload: <String, dynamic>{
          'requestId': 'req-1',
          'status': 'pending',
          'meta': nested,
        },
      );

      // The caller keeps mutating its own maps after building the action...
      nested['note'] = 'mutated';

      // ...the queued (persisted-to-be) arguments are untouched, and nobody
      // can write through the action either.
      expect(action.payload['status'], 'pending');
      expect((action.payload['meta'] as Map)['note'], 'original');
      expect(
        () => action.payload['status'] = 'cancelled',
        throwsUnsupportedError,
      );
      expect(
        () => (action.payload['meta'] as Map)['note'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('non JSON-safe payloads are rejected at construction', () {
      expect(
        () => _queuedAction(
          'bad-scalar',
          payload: <String, dynamic>{'when': DateTime(2026)},
        ),
        throwsArgumentError,
      );
      expect(
        () => _queuedAction(
          'bad-nested',
          payload: <String, dynamic>{'items': <Object?>['ok', Object()]},
        ),
        throwsArgumentError,
      );
    });

    test('a monotonically increasing seq breaks same-millisecond ties', () {
      QueuedAction.debugResetSequence();
      // Deliberately ordered so the id tiebreak can never be the one working:
      // lexicographically 'a-second' < 'z-first'.
      final first = _queuedAction('z-first');
      final second = _queuedAction('a-second');
      final third = _queuedAction('m-third');

      expect(first.seq, lessThan(second.seq));
      expect(second.seq, lessThan(third.seq));
      expect(first.compareTo(second), lessThan(0),
          reason: 'insertion order wins over the id tiebreak');
      expect(third.compareTo(second), greaterThan(0));
      expect(first.compareTo(first), 0);
    });

    test('seq is persisted with the action and restored on load', () async {
      final action = _queuedAction('persist-seq');
      await OfflineQueue.enqueue(action);
      final originalSeq = action.seq;

      await OfflineQueue.persistToPrefs();
      OfflineQueue.pending.value = <QueuedAction>[];
      await OfflineQueue.loadFromPrefs();

      final restored = OfflineQueue.pending.value.single;
      expect(restored.seq, originalSeq);
      expect(restored.toJson()['seq'], originalSeq);
    });

    test('same-millisecond actions keep their FIFO order across a restart',
        () async {
      const stamp = 1700000000000;
      // Ids chosen so lexicographic order DIFFERS from the enqueue order.
      const ids = <String>['act-10', 'act-9', 'act-2', 'act-1'];
      for (final id in ids) {
        await OfflineQueue.enqueue(_queuedAction(id, createdAtMs: stamp));
      }

      await OfflineQueue.persistToPrefs();
      OfflineQueue.pending.value = <QueuedAction>[];
      await OfflineQueue.loadFromPrefs();

      expect(
        OfflineQueue.pending.value.map((a) => a.id).toList(),
        ids,
        reason: 'createdAtMs ties are broken by the insertion sequence, '
            'never by id nor by sort instability',
      );
    });

    test('a legacy queue without seq keeps its stored order and stays ahead '
        'of new actions', () async {
      QueuedAction.debugResetSequence();
      const stamp = 1700000000000;
      // Hand-written storage as an older build would have left it: identical
      // timestamps and NO `seq` field at all.
      Map<String, dynamic> legacyEntry(String id) => <String, dynamic>{
            'id': id,
            'type': 'updateOrderStatus',
            'payload': <String, dynamic>{
              'requestId': 'r-$id',
              'status': 'accepted',
            },
            'createdAtMs': stamp,
            'attempts': 0,
          };
      SharedPreferences.setMockInitialValues(<String, Object>{
        OfflineQueue.prefsKey:
            jsonEncode(<Map<String, dynamic>>[legacyEntry('legacy-1'), legacyEntry('legacy-2')]),
      });

      await OfflineQueue.loadFromPrefs();
      final restored = OfflineQueue.pending.value;
      expect(restored.map((a) => a.id).toList(),
          <String>['legacy-1', 'legacy-2'],
          reason: 'the persisted array IS the enqueue order');

      // A relaunch must never enqueue an action that sorts BEFORE a stored one.
      final fresh = _queuedAction('fresh', createdAtMs: stamp);
      expect(fresh.seq, greaterThan(restored.last.seq),
          reason: 'restoring pushed the monotonic counter forward');
      expect(restored.last.compareTo(fresh), lessThan(0));
    });

    test('the parser validates keys and types BEFORE any cast view', () {
      const stamp = 1700000000000;
      // Non-String key at the entry level (a lazy `cast` would explode later,
      // on first read, inside an executor).
      expect(
        QueuedAction.fromJson(<dynamic, dynamic>{
          'id': 'x',
          'type': 'updateOrderStatus',
          'payload': <String, dynamic>{},
          'createdAtMs': stamp,
          1: 'odd',
        }),
        isNull,
      );
      // Non-String key INSIDE the payload.
      expect(
        QueuedAction.fromJson(<String, dynamic>{
          'id': 'x',
          'type': 'updateOrderStatus',
          'payload': <dynamic, dynamic>{1: 'odd'},
          'createdAtMs': stamp,
        }),
        isNull,
      );
      // A value that could never round-trip through JSON.
      expect(
        QueuedAction.fromJson(<String, dynamic>{
          'id': 'x',
          'type': 'updateOrderStatus',
          'payload': <String, dynamic>{'when': DateTime(2026)},
          'createdAtMs': stamp,
        }),
        isNull,
      );
      // A healthy entry — with a persisted sequence — still parses.
      final healthy = QueuedAction.fromJson(<String, dynamic>{
        'id': 'ok',
        'type': 'updateOrderStatus',
        'payload': <String, dynamic>{'requestId': 'r', 'status': 'accepted'},
        'createdAtMs': stamp,
        'seq': 7,
        'attempts': 2,
      });
      expect(healthy, isNotNull);
      expect(healthy!.seq, 7);
      expect(healthy.attempts, 2);
      // ...and its payload is immutable too.
      expect(
        () => healthy.payload['requestId'] = 'other',
        throwsUnsupportedError,
      );
    });

    test('a malformed entry is dropped while the rest of the queue survives',
        () async {
      const stamp = 1700000000000;
      Map<String, dynamic> entry(String id, String type) => <String, dynamic>{
            'id': id,
            'type': type,
            'payload': <String, dynamic>{'requestId': 'r-$id'},
            'createdAtMs': stamp,
            'attempts': 0,
          };
      SharedPreferences.setMockInitialValues(<String, Object>{
        OfflineQueue.prefsKey: jsonEncode(<Map<String, dynamic>>[
          entry('good-1', 'updateOrderStatus'),
          // Unknown type: permanently unusable, must not brick the queue.
          entry('poison', 'vanished'),
          entry('good-2', 'updateOrderStatus'),
        ]),
      });

      await OfflineQueue.loadFromPrefs();

      expect(OfflineQueue.pending.value.map((a) => a.id).toList(),
          <String>['good-1', 'good-2']);
    });

    test('non-finite numbers are rejected BEFORE any persistence', () {
      // NaN/±Infinity can never be JSON-encoded: left unchecked they would
      // poison toJson() and — persistToPrefs being best-effort — silently
      // disable persistence for the WHOLE queue.
      expect(
        () => _queuedAction('bad-nan',
            payload: <String, dynamic>{'ratio': double.nan}),
        throwsArgumentError,
      );
      expect(
        () => _queuedAction('bad-inf',
            payload: <String, dynamic>{'budget': double.infinity}),
        throwsArgumentError,
      );
      // ...including nested metadata and list items.
      expect(
        () => _queuedAction(
          'bad-nested-inf',
          payload: <String, dynamic>{
            'meta': <String, dynamic>{'ratio': double.negativeInfinity},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _queuedAction('bad-list-inf',
            payload: <String, dynamic>{'steps': <Object?>[1, double.nan]}),
        throwsArgumentError,
      );

      // A finite number is still perfectly fine.
      expect(
        _queuedAction('ok-num',
                payload: <String, dynamic>{'ratio': 0.25, 'count': 3})
            .payload['ratio'],
        0.25,
      );

      // And a non-finite timestamp in storage can never be revived either —
      // the tolerant parser drops the entry instead of throwing on toInt().
      expect(
        QueuedAction.fromJson(<String, dynamic>{
          'id': 'x',
          'type': 'updateOrderStatus',
          'payload': <String, dynamic>{},
          'createdAtMs': double.nan,
        }),
        isNull,
      );
      expect(
        QueuedAction.fromJson(<String, dynamic>{
          'id': 'x',
          'type': 'updateOrderStatus',
          'payload': <String, dynamic>{},
          'createdAtMs': double.infinity,
        }),
        isNull,
      );
    });

    test('seq is the ABSOLUTE primary comparison key', () {
      // A later wall-clock stamp can NEVER overrule the sequence (a skewed
      // clock, an NTP correction): the order is decided by the insertion
      // sequence alone.
      final earlierSeqLaterStamp = QueuedAction(
        id: 'a',
        type: QueuedActionType.updateOrderStatus,
        payload: <String, dynamic>{'requestId': 'r1', 'status': 'accepted'},
        createdAtMs: 2000,
        seq: 1,
      );
      final laterSeqEarlierStamp = QueuedAction(
        id: 'b',
        type: QueuedActionType.updateOrderStatus,
        payload: <String, dynamic>{'requestId': 'r2', 'status': 'accepted'},
        createdAtMs: 1000,
        seq: 2,
      );
      expect(earlierSeqLaterStamp.compareTo(laterSeqEarlierStamp), lessThan(0),
          reason: 'seq decides, even against a conflicting timestamp');
      expect(laterSeqEarlierStamp.compareTo(earlierSeqLaterStamp),
          greaterThan(0));

      // Sorting any permutation reproduces the sequence order exactly.
      final shuffled = <QueuedAction>[
        laterSeqEarlierStamp,
        earlierSeqLaterStamp,
      ]..sort((a, b) => a.compareTo(b));
      expect(shuffled.map((a) => a.seq), <int>[1, 2]);

      // The id and the timestamp stay total-order tiebreakers only: identical
      // sequences (hand-crafted storage) still have ONE defined order.
      final twinA = QueuedAction(
        id: 't1',
        type: QueuedActionType.updateOrderStatus,
        payload: <String, dynamic>{'requestId': 'r1'},
        createdAtMs: 5,
        seq: 9,
      );
      final twinB = QueuedAction(
        id: 't2',
        type: QueuedActionType.updateOrderStatus,
        payload: <String, dynamic>{'requestId': 'r2'},
        createdAtMs: 5,
        seq: 9,
      );
      expect(twinA.compareTo(twinB), lessThan(0));
      expect(twinB.compareTo(twinA), greaterThan(0));
      expect(twinA.compareTo(twinA), 0);
    });
  });

  // ─── 3. Anti-Abuse 50-Cancellation Auto-Ban ─────────────────────────────
  group('Anti-Abuse 50-Cancellation Auto-Ban', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AntiAbuseStore.reset();
    });

    test('49 cancellations do NOT trigger a ban', () async {
      AntiAbuseStore.setActiveClient('client-test-49');
      await AntiAbuseStore.debugRecordCancellations(49);

      expect(AntiAbuseStore.count, 49);
      expect(AntiAbuseStore.isCurrentlyBanned, isFalse);
      expect(AntiAbuseStore.showBanGate.value, isFalse);
    });

    test('50th cancellation triggers a ban, logs out, and flips showBanGate',
        () async {
      AntiAbuseBindings.register();
      UserStore.user.value = const UserModel(
        id: 'client-test-50',
        name: 'Client',
        phone: '22123456',
        role: UserRole.client,
      );
      AntiAbuseStore.setActiveClient('client-test-50');
      await AntiAbuseStore.debugRecordCancellations(49);

      expect(AntiAbuseStore.isCurrentlyBanned, isFalse);
      expect(AntiAbuseStore.showBanGate.value, isFalse);
      expect(UserStore.user.value, isNotNull);

      await AntiAbuseStore.recordCancellation();

      expect(AntiAbuseStore.count, 50);
      expect(AntiAbuseStore.isCurrentlyBanned, isTrue);
      expect(AntiAbuseStore.showBanGate.value, isTrue);
      expect(AntiAbuseStore.bannedClientId, 'client-test-50');
      expect(UserStore.user.value, isNull);
    });

    test('ban is triggered exactly on the 50th individual cancellation',
        () async {
      AntiAbuseStore.setActiveClient('client-individual-50');
      for (var i = 0; i < 50; i++) {
        await AntiAbuseStore.recordCancellation();
      }
      expect(AntiAbuseStore.count, 50);
      expect(AntiAbuseStore.isCurrentlyBanned, isTrue);
      expect(AntiAbuseStore.showBanGate.value, isTrue);
    });

    test('cancellation recording with no active client is a no-op', () async {
      await AntiAbuseStore.recordCancellation();
      expect(AntiAbuseStore.count, 0);
      expect(AntiAbuseStore.isCurrentlyBanned, isFalse);
    });

    test('cancellation recording with empty client ID is a no-op', () async {
      AntiAbuseStore.setActiveClient('');
      await AntiAbuseStore.recordCancellation();
      expect(AntiAbuseStore.count, 0);
      expect(AntiAbuseStore.isCurrentlyBanned, isFalse);
    });

    test('counts persist across restart', () async {
      AntiAbuseStore.setActiveClient('client-persist-30');
      await AntiAbuseStore.debugRecordCancellations(30);

      // Simulate restart.
      AntiAbuseStore.debugClearMemory();
      await AntiAbuseStore.loadFromPrefs();

      expect(AntiAbuseStore.countFor('client-persist-30'), 30);
    });

    test('banned client is restored after restart', () async {
      AntiAbuseStore.setActiveClient('client-ban-restart');
      await AntiAbuseStore.debugRecordCancellations(50);

      // Simulate restart.
      AntiAbuseStore.debugClearMemory();
      await AntiAbuseStore.loadFromPrefs();

      expect(AntiAbuseStore.isBanned('client-ban-restart'), isTrue);
    });

    test('RequestStore cancellation triggers anti-abuse tracking', () async {
      AntiAbuseStore.setActiveClient('active-client-1');

      final request = ServiceRequest(
        id: 'req-cancel-1',
        serviceTitleFr: 'Plombier',
        serviceTitleAr: 'سبّاك',
        professionalId: 'pro-1',
        professionalName: 'Sami',
        customerName: 'Client',
        customerId: 'active-client-1',
        dateTime: DateTime.now(),
        address: 'Tunis',
        message: 'Test',
        createdAt: DateTime.now(),
      );
      RequestStore.add(request);
      RequestStore.updateStatus('req-cancel-1', RequestStatus.accepted);
      RequestStore.updateStatus('req-cancel-1', RequestStatus.cancelled);

      expect(AntiAbuseStore.count, 1);
    });
  });

  // ─── 4. Ban Gate Screen ───────────────────────────────────────────────
  group('Ban Gate Screen', () {
    testWidgets('displays support number and sign-out button',
        (WidgetTester tester) async {
      bool signedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AntiAbuseBanGateScreen(
            signOutAndReset: () => signedOut = true,
          ),
        ),
      );

      expect(find.text(AppConstants.adminSupportNumber), findsWidgets);

      final signOutButton = find.textContaining('Se déconnecter');
      expect(signOutButton, findsOneWidget);

      await tester.tap(signOutButton);
      expect(signedOut, isTrue);
    });

    testWidgets('displays Arabic content when locale is Arabic',
        (WidgetTester tester) async {
      appLocale.value = const Locale('ar');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: AntiAbuseBanGateScreen(
            signOutAndReset: () {},
          ),
        ),
      );

      expect(find.textContaining('تم حظر الحساب'), findsOneWidget);
      expect(find.text(AppConstants.adminSupportNumber), findsWidgets);
    });

    testWidgets('AntiAbuseGate intercepts navigation and shows the support number',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AntiAbuseGate(child: Text('app-ok')),
        ),
      );
      expect(find.text('app-ok'), findsOneWidget);

      AntiAbuseStore.debugForceBan('client-gate');
      await tester.pump();

      expect(find.text('app-ok'), findsNothing);
      expect(find.byType(AntiAbuseBanGateScreen), findsOneWidget);
      expect(find.text(AppConstants.adminSupportNumber), findsWidgets);
      expect(find.textContaining('50'), findsOneWidget);
    });
  });
}
