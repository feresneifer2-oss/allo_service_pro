// ─────────────────────────────────────────────────────────────────────────────
// PERSISTENT PROFESSIONAL AVAILABILITY (`pro_availability`) — TEST SUITE
// ─────────────────────────────────────────────────────────────────────────────
//
// WHAT IS UNDER TEST
// ------------------
// `isAvailable` means "this craftsman ACCEPTS NEW SERVICE REQUESTS". It is a
// durable business decision — NOT a presence/connection flag — so the whole
// feature rests on one rule: **Supabase Postgres is the single source of
// truth** and the value must survive a force-close, a kill and a restart.
//
// SCENARIOS LOCKED BY THIS SUITE
// ------------------------------
//  1. RESTART / FORCE-CLOSE — the toggle is mirrored locally and restored on the
//     next launch; a restart NEVER flips availability to false by itself.
//  2. WIRE CONTRACT — `ProAvailabilityRepository` decodes the `pro_availability`
//     row tolerantly and never throws when no backend is configured.
//  3. REALTIME — a delivered row (what `realtime:public:pro_availability` pushes
//     into `ProAvailabilityStore.applyRemoteRow`) updates the client board, the
//     owner's own switch and `ProfessionalModel.availableNow`.
//  4. OFFLINE QUEUE — a toggle made offline is queued, the queue holds exactly
//     ONE entry per professional carrying the LATEST action, the replay is an
//     idempotent upsert, and a still-unreachable backend keeps the entry.
//  5. CUSTOMER UI — `_ProfessionalCard` repaints its badge and its "Demander"
//     button from the realtime ingress, with no new search and no refresh.
//  6. OWNER UI — tapping the dashboard Switch persists the choice for the next
//     launch (the `ValueNotifier` contract is unchanged: same-frame reaction).
//
// NOTE ON THE TRANSPORT: no test initializes Supabase (the suite runs in the
// project's "local-only" mode), so the channel CALLBACK is exercised through
// its production seam (`applyRemoteRow`) — exactly the function
// `SupabaseRealtimeService` wires as the postgres_changes callback.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/offline_queue_bindings.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_availability_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/data/pro_availability_repository.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_dashboard_screen.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/features/search/presentation/search_screen.dart';

/// One `pro_availability` row exactly as Postgres Realtime delivers it
/// (`payload.newRecord`: snake_case columns, no wrapping envelope).
Map<String, dynamic> _row({
  required String proId,
  required String? proCode,
  required bool isAvailable,
}) =>
    <String, dynamic>{
      'pro_id': proId,
      'pro_code': proCode,
      'is_available': isAvailable,
      'updated_at': '2026-09-24T10:00:00Z',
    };

/// The persisted public code (pro_code) of the "own account" scenarios —
/// still carried on the row and the queue payload, but NEVER a board key
/// after Phase 7-4.
const String _ownProCode = 'PRO-7001';

/// Phase 7-4: the uuid (pro_id) this account's availability rows are keyed by.
const String _ownProUuid = 'uid-7001';

/// A signed-in professional whose account owns [_ownProUuid] / [_ownProCode].
void _bindOwnSession() {
  UserStore.user.value = const UserModel(
    id: _ownProUuid,
    name: 'Ahmed',
    phone: '21600000000',
    proCode: _ownProCode,
    role: UserRole.professional,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh device storage + fresh in-memory stores for every scenario.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProProfileStore.isAvailable.value = true;
    ProAvailabilityStore.reset();
    UserStore.user.value = null;
  });

  tearDown(() {
    ProProfileStore.isAvailable.value = true;
    ProAvailabilityStore.reset();
    UserStore.user.value = null;
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 1 · The value outlives the process (force-close / kill / restart)
  // ───────────────────────────────────────────────────────────────────────────

  group('restart restoration · ProProfileStore', () {
    test('OFFLINE survives a force-close: the next launch restores it',
        () async {
      await ProProfileStore.setAvailability(false);

      // A kill writes nothing: the in-memory default comes back…
      ProProfileStore.isAvailable.value = true;
      // …and the boot hydration is what restores the truth.
      await ProProfileStore.loadFromPrefs();

      expect(
        ProProfileStore.isAvailable.value,
        isFalse,
        reason: 'a pro who went unavailable must come back unavailable',
      );
    });

    test('no saved flag ⇒ the default stands (a restart never flips to false)',
        () async {
      // A device that only ever stored the token balance.
      SharedPreferences.setMockInitialValues(
        <String, Object>{'pro_tokens': 90},
      );

      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.isAvailable.value, isTrue);
      expect(ProProfileStore.tokens.value, 90,
          reason: 'the availability restore must not disturb the token keys');
    });

    test('an ONLINE choice is persisted too — not only the offline one',
        () async {
      await ProProfileStore.setAvailability(false);
      await ProProfileStore.setAvailability(true);

      ProProfileStore.isAvailable.value = false; // cold in-memory default
      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.isAvailable.value, isTrue);
    });

    test(
        'the realtime ingress is mirrored locally: a cross-device change '
        'survives a kill on THIS device', () async {
      ProProfileStore.applyRemoteAvailability(false);
      await pumpEventQueue(); // the mirror write is fire-and-forget

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pro_availability'), isFalse);
      expect(ProProfileStore.isAvailable.value, isFalse);
    });

    test('logout clears the LOCAL cache only — signing out is not offline',
        () async {
      await ProProfileStore.setAvailability(false);

      await ProProfileStore.reset(); // what UserStore.signOutAndReset() calls

      expect(ProProfileStore.isAvailable.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pro_availability'), isFalse,
          reason: 'the next account on this device must not inherit the flag');
    });

    test('an identical ingress value notifies nobody (no wasted frames)',
        () async {
      var notifications = 0;
      void probe() => notifications += 1;
      ProProfileStore.isAvailable.addListener(probe);
      addTearDown(() => ProProfileStore.isAvailable.removeListener(probe));

      ProProfileStore.applyRemoteAvailability(true); // already the value
      ProProfileStore.applyRemoteAvailability(true);

      expect(notifications, 0);
    });

    test('a local-only build queues nothing it could never send', () async {
      await OfflineQueue.debugReset();
      addTearDown(OfflineQueue.debugReset);

      // No signed-in remote identity and no configured backend.
      await ProProfileStore.setAvailability(false);

      expect(OfflineQueue.pending.value, isEmpty,
          reason: 'a toggle with no remote identity has no replay target');
      expect(ProProfileStore.isAvailable.value, isFalse,
          reason: 'the local switch still reflects the user action');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 2 · The wire contract of the durable row (`pro_availability`)
  // ───────────────────────────────────────────────────────────────────────────

  group('wire contract · ProAvailabilityRepository', () {
    test('decodes a well-formed row into proId / proCode / flag', () {
      final parsed = ProAvailabilityRepository.fromRow(
        _row(proId: 'uid-7001', proCode: _ownProCode, isAvailable: false),
      );

      expect(parsed, isNotNull);
      expect(parsed!.proId, 'uid-7001');
      expect(parsed.proCode, _ownProCode);
      expect(parsed.isAvailable, isFalse);
    });

    test('tolerates textual / numeric flags (legacy or hand-written rows)', () {
      expect(ProAvailabilityRepository.readAvailabilityFlag('false'), isFalse);
      expect(ProAvailabilityRepository.readAvailabilityFlag('F'), isFalse);
      expect(ProAvailabilityRepository.readAvailabilityFlag('0'), isFalse);
      expect(ProAvailabilityRepository.readAvailabilityFlag(0), isFalse);
      expect(ProAvailabilityRepository.readAvailabilityFlag('true'), isTrue);
      expect(ProAvailabilityRepository.readAvailabilityFlag('yes'), isTrue);
      expect(ProAvailabilityRepository.readAvailabilityFlag(1), isTrue);
      expect(ProAvailabilityRepository.readAvailabilityFlag('maybe'), isNull);
      expect(ProAvailabilityRepository.readAvailabilityFlag(null), isNull);
    });

    test('drops rows nobody in the client feed could ever match', () {
      // Phase 7-4: the GATE + KEY is pro_id (uuid) — a row without a usable
      // uuid is undecodable even when it carries a public code…
      expect(
        ProAvailabilityRepository.fromRow(
          _row(proId: '', proCode: _ownProCode, isAvailable: true),
        ),
        isNull,
      );
      // …or when the uuid is only whitespace…
      expect(
        ProAvailabilityRepository.fromRow(
          _row(proId: '   ', proCode: _ownProCode, isAvailable: true),
        ),
        isNull,
      );
      // …or a flag that cannot be read.
      expect(
        ProAvailabilityRepository.fromRow(
          _row(proId: 'uid-1', proCode: _ownProCode, isAvailable: true)
            ..['is_available'] = 'indisponible',
        ),
        isNull,
      );
      // pro_code stays OPTIONAL: a pro whose registration has no public code
      // yet still lands on the board under their uuid (the bug 7-4 fixed —
      // these rows used to be DROPPED and their flag fell back to "available").
      expect(
        ProAvailabilityRepository.fromRow(
          _row(proId: 'uid-1', proCode: null, isAvailable: true),
        ),
        isNotNull,
      );
      expect(
        ProAvailabilityRepository.fromRow(
          _row(proId: 'uid-1', proCode: '   ', isAvailable: true),
        ),
        isNotNull,
      );
    });

    test('no configured backend ⇒ no authority (never throws, never writes)',
        () async {
      expect(ProAvailabilityRepository.isConfigured, isFalse,
          reason: 'this suite runs without Supabase — the local-only mode');
      expect(ProAvailabilityRepository.currentAuthUserId(), isNull);

      // `false` = the caller must keep the write for a later connectivity
      // window instead of believing it landed.
      expect(
        await ProAvailabilityRepository.upsertAvailability(
          proId: 'uid-7001',
          proCode: _ownProCode,
          isAvailable: false,
        ),
        isFalse,
      );

      // `null` = NO authority, which is deliberately distinct from an EMPTY
      // board ("nobody ever toggled"): an unreachable backend must never be
      // allowed to wipe what realtime already merged.
      expect(await ProAvailabilityRepository.fetchAvailability(), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 3 · Realtime ingress → the board, the owner's switch, the feed
  // ───────────────────────────────────────────────────────────────────────────

  group('realtime ingress · ProAvailabilityStore', () {
    test('a delivered row reaches the owner dashboard AND the client board',
        () async {
      _bindOwnSession();

      // What the channel callback runs for every INSERT / UPDATE.
      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'uid-7001', proCode: _ownProCode, isAvailable: false),
      );
      await pumpEventQueue();

      // Owner side: the dashboard switch follows the persisted truth…
      expect(ProProfileStore.isAvailable.value, isFalse);
      // …client side: the board carries the uuid key (Phase 7-4).
      expect(ProAvailabilityStore.remoteFlagFor(_ownProUuid), isFalse);
    });

    test('another craftsman\'s row never touches MY own switch', () async {
      _bindOwnSession();

      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'uid-other', proCode: 'PRO-9999', isAvailable: false),
      );
      await pumpEventQueue();

      expect(ProProfileStore.isAvailable.value, isTrue);
      expect(ProAvailabilityStore.remoteFlagFor('uid-other'), isFalse);
      expect(ProAvailabilityStore.remoteFlagFor(_ownProUuid), isNull,
          reason: 'my own row was never delivered — unknown, not offline');
    });

    test('the client feed overlay: known pros flip, unknown ones keep defaults',
        () {
      ProfessionalModel pick(String id) =>
          ProfessionalsRepository.all.firstWhere((p) => p.id == id);

      final before = pick('pro_3');
      expect(before.availableNow, isTrue, reason: 'curated default');

      ProAvailabilityStore.applyRemoteAvailability('pro_3', false);

      final after = pick('pro_3');
      expect(after.availableNow, isFalse);
      expect(after.name, before.name,
          reason: 'only availability may change — every other field is kept');
      expect(after.rating, before.rating);
      expect(after.priceFrom, before.priceFrom);

      // A pro nobody ever toggled is UNKNOWN, not offline.
      expect(pick('pro_1').availableNow, isTrue);

      // …and the overlay can only ever make the row true/false it was given.
      ProAvailabilityStore.applyRemoteAvailability('pro_2', true);
      expect(pick('pro_2').availableNow, isTrue,
          reason: 'the persisted row overrides the curated mock (was false)');
    });

    test('a repeated delivery of the same value is free (no rebuild)', () {
      var notifications = 0;
      void probe() => notifications += 1;
      ProAvailabilityStore.onlineByProId.addListener(probe);
      addTearDown(
        () => ProAvailabilityStore.onlineByProId.removeListener(probe),
      );

      ProAvailabilityStore.applyRemoteAvailability('uid-3', false);
      ProAvailabilityStore.applyRemoteAvailability('uid-3', false);
      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'uid-3', proCode: 'pro_3', isAvailable: false),
      );

      expect(notifications, 1, reason: 'one value ⇒ at most one notification');
    });

    test('an undecodable delivery is ignored, never applied', () {
      // Phase 7-4: the gate is the uuid — a row without a usable pro_id has
      // no board key, whatever public code it carries.
      ProAvailabilityStore.applyRemoteRow(
        _row(proId: '', proCode: 'PRO-9999', isAvailable: false),
      );

      expect(ProAvailabilityStore.onlineByProId.value, isEmpty);
    });

    test('a failed hydration keeps the board realtime already merged',
        () async {
      ProAvailabilityStore.applyRemoteAvailability('pro_3', false);

      // No configured backend ⇒ no authority: the read must not "answer" with
      // an empty board and wipe what is already on screen.
      final hydrated = await ProAvailabilityStore.hydrateFromSupabase();

      expect(hydrated, isFalse);
      expect(ProAvailabilityStore.remoteFlagFor('pro_3'), isFalse);
    });

    test('sign-out drops the board — the next session re-hydrates it', () {
      ProAvailabilityStore.applyRemoteAvailability('pro_3', false);
      expect(ProAvailabilityStore.onlineByProId.value, isNotEmpty);

      ProAvailabilityStore.reset(); // called by the auth binding on signedOut

      expect(ProAvailabilityStore.onlineByProId.value, isEmpty);
      expect(
        ProfessionalsRepository.all
            .firstWhere((p) => p.id == 'pro_3')
            .availableNow,
        isTrue,
        reason: 'with no board the curated default stands again',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 4 · Toggling while temporarily OFFLINE (queue + safe resolution)
  // ───────────────────────────────────────────────────────────────────────────

  group('offline queue · updateProAvailability', () {
    setUp(() async {
      await OfflineQueue.debugReset();
      OfflineQueueBindings.registerAll();
    });

    tearDown(() async {
      await OfflineQueue.debugReset();
    });

    test('the executor is registered for the new action type', () async {
      final accepted = await OfflineQueue.enqueue(
        ProProfileStore.buildAvailabilityAction(
          proId: 'uid-7001',
          proCode: _ownProCode,
          isAvailable: false,
        ),
      );

      // `enqueue` REFUSES a type with no executor, so an accepted action is
      // proof that the replay path exists — the classic "queued forever, never
      // sent" bug cannot happen.
      expect(accepted, isTrue);
      expect(OfflineQueue.pending.value, hasLength(1));
      expect(
        OfflineQueue.pending.value.single.type,
        QueuedActionType.updateProAvailability,
      );
    });

    test('an unreachable backend during replay KEEPS the entry for later',
        () async {
      await OfflineQueue.enqueue(
        ProProfileStore.buildAvailabilityAction(
          proId: 'uid-7001',
          proCode: _ownProCode,
          isAvailable: false,
        ),
      );

      final report = await OfflineQueue.flush();

      expect(report.applied, 0);
      expect(report.retried, 1);
      expect(report.dropped, 0);
      expect(OfflineQueue.pending.value, hasLength(1),
          reason:
              'the offline choice must not be lost — it lands on reconnect');
      expect(OfflineQueue.pending.value.single.payload['isAvailable'], isFalse);
    });

    test('ONE entry per pro: repeated offline toggles resolve to the LAST one',
        () async {
      // Five taps while offline — offline, online, offline, online, offline…
      for (final value in <bool>[false, true, false, true, false]) {
        final action = ProProfileStore.buildAvailabilityAction(
          proId: 'uid-7001',
          proCode: _ownProCode,
          isAvailable: value,
        );
        final queued = OfflineQueue.pending.value.any(
          (a) => a.id == action.id,
        );
        if (queued) {
          OfflineQueue.replace(action);
        } else {
          await OfflineQueue.enqueue(action);
        }
      }

      final pending = OfflineQueue.pending.value;
      expect(pending, hasLength(1), reason: 'the queue is not a journal');
      expect(pending.single.id, 'pro_availability_uid-7001',
          reason: 'the id is derived from the pro, so the entry is re-keyed');
      expect(pending.single.payload['isAvailable'], isFalse,
          reason: 'the replayed value must be the LATEST user action');
      expect(pending.single.payload['proCode'], _ownProCode);
    });

    test('a malformed payload is dropped, never retried forever', () async {
      await OfflineQueue.enqueue(
        QueuedAction(
          id: 'pro_availability-broken',
          type: QueuedActionType.updateProAvailability,
          payload: <String, dynamic>{'proId': 42, 'isAvailable': 'yes'},
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final report = await OfflineQueue.flush();

      expect(report.dropped, 1);
      expect(report.retried, 0);
      expect(OfflineQueue.pending.value, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 5 · What the CUSTOMER sees when the persisted flag changes
  // ───────────────────────────────────────────────────────────────────────────

  group('customer UI · the card follows the persisted flag', () {
    Future<void> pumpSearch(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('fr'), Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SearchScreen(),
        ),
      );

      // Results only render once a governorate is picked; 'Tunis' hosts
      // pro_2 (Tunis Ville, curated OFFLINE), pro_5 (Tunis Ville, curated
      // online) plus pro_3 / pro_7 (La Marsa, curated online).
      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tunis').last);
      await tester.pumpAndSettle();
    }

    List<ElevatedButton> ctas(WidgetTester tester) => tester
        .widgetList<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Demander'),
        )
        .toList();

    testWidgets('a delivered toggle repaints the badge + Demander in ONE frame',
        (tester) async {
      await pumpSearch(tester);

      // Baseline: exactly one of the four Tunis craftsmen is unavailable.
      expect(find.text('Indisponible'), findsOneWidget);
      expect(ctas(tester), hasLength(4));
      expect(ctas(tester).where((b) => b.onPressed == null), hasLength(1));

      // ── The backend persists pro_5 as UNAVAILABLE and pushes the row ──
      // Phase 7-4: the board key is `pro_id` — a CATALOG entry carries no auth
      // identity, so its board key is the catalog id itself (a live pro's row
      // would carry the auth.users uuid instead).
      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'pro_5', proCode: 'pro_5', isAvailable: false),
      );
      await tester
          .pump(); // ← ONE frame. No new search, no refresh, no remount.

      expect(find.text('Indisponible'), findsNWidgets(2));
      expect(ctas(tester).where((b) => b.onPressed == null), hasLength(2),
          reason: 'the freshly unavailable craftsman is not requestable');

      // ── Back ONLINE: the same card returns to its requestable state ──
      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'pro_5', proCode: 'pro_5', isAvailable: true),
      );
      await tester.pump();

      expect(find.text('Indisponible'), findsOneWidget);
      expect(ctas(tester).where((b) => b.onPressed == null), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unrelated pro\'s row never touches the visible cards',
        (tester) async {
      await pumpSearch(tester);
      expect(find.text('Indisponible'), findsOneWidget);

      ProAvailabilityStore.applyRemoteRow(
        _row(proId: 'uid-9999', proCode: 'PRO-9999', isAvailable: false),
      );
      await tester.pump();

      expect(find.text('Indisponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the screen releases the board listener (no leak)',
        (tester) async {
      await pumpSearch(tester);
      // ignore: invalid_use_of_protected_member
      expect(ProAvailabilityStore.onlineByProId.hasListeners, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // ignore: invalid_use_of_protected_member
      expect(ProAvailabilityStore.onlineByProId.hasListeners, isFalse,
          reason: 'the State must detach in dispose() or it leaks forever');

      // A delivery after the screen is gone is harmless.
      ProAvailabilityStore.applyRemoteAvailability('pro_5', false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 6 · The OWNER side: the dashboard Switch now persists its choice
  // ───────────────────────────────────────────────────────────────────────────

  group('owner UI · the dashboard switch persists', () {
    testWidgets('tapping the switch mirrors the choice for the next launch',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('fr'), Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ProDashboardScreen(),
        ),
      );

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The notifier contract is unchanged: the UI already shows the new value.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(ProProfileStore.isAvailable.value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pro_availability'), isFalse,
          reason: 'the choice is persisted, not merely displayed');

      // ── Restart: cold in-memory default + the boot hydration ──
      ProProfileStore.isAvailable.value = true;
      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.isAvailable.value, isFalse,
          reason: 'the professional must not silently come back "available"');
      expect(tester.takeException(), isNull);
    });
  });

  // ── END OF SUITE ──
}
