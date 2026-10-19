import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/offline_queue_bindings.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/data/orders_repository.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

import 'support/fake_admin_auth.dart';

/// Phase 3K — `ServiceRequest.professionalAuthUid` propagation through the
/// LOCAL booking/request flow (wire assertions refreshed in Phase 3L).
///
/// Scope contract (must stay true):
/// - the field is nullable; `professionalId` (`PRO-XXXXX` / `pro_N`) stays
///   the display/routing id and is NEVER replaced by the uid;
/// - an approved (real) pro resolves to its Supabase uid; mock catalog pros
///   and unknown ids resolve to null — never a foreign pro's uid;
/// - Phase 3L: the wire row carries the uid as `orders.pro_id` (`toRow` /
///   `fromRow` map it both ways); the display id is NOT on the wire and is
///   resolved from the local registry on decode (empty when unknown);
/// - `copyWith`, status transitions and both remote merges preserve the uid
///   on the LOCAL copy;
/// - the offline queue payload stays byte-identical to `toRow`; the uid
///   survives on the local order across enqueue → restart → replay.
///
/// NO Supabase schema, NO RLS changes here.
void main() {
  /// Shapes a request exactly like the drafts the creation screens build
  /// (booking screen / create-request screen): the uid travels ALONGSIDE
  /// the display id. Fixed dates keep `toRow` deterministic for the wire
  /// contract assertions.
  ServiceRequest buildRequest({
    required String id,
    String professionalId = 'pro_1',
    String? professionalAuthUid,
  }) =>
      ServiceRequest(
        id: id,
        serviceTitleFr: 'Plomberie',
        serviceTitleAr: 'سباكة',
        professionalId: professionalId,
        professionalAuthUid: professionalAuthUid,
        professionalName: 'Hatem Trabelsi',
        customerName: 'Client 3K',
        customerId: 'client-3k',
        dateTime: DateTime(2026, 3, 1, 10, 30),
        address: 'Ariana, Tunisie',
        message: '',
        createdAt: DateTime(2026, 3, 1, 9, 0),
      );

  PendingProModel makePending({required String id, String? authUid}) =>
      PendingProModel(
        id: id,
        name: 'Karim $id',
        phone: '500$id',
        email: '$id@example.tn',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        status: 'pending',
        submittedAt: '01/01/2026',
        authUid: authUid,
      );

  /// Supabase professional identities (valid uuids): the server-first
  /// approval gate (Phase 3P) refuses a missing/non-uuid identity BEFORE the
  /// RPC is reached, so the former 'uid-3k-*' placeholders became constants.
  const liveProUid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const bookingProUid = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';
  const foreignProUid = 'cccccccc-dddd-4eee-8fff-000000000000';

  // ─── 1. Model ──────────────────────────────────────────────────────────
  group('ServiceRequest.professionalAuthUid (model)', () {
    test('defaults to null when no uid is provided', () {
      expect(buildRequest(id: '3k-m-1').professionalAuthUid, isNull);
    });

    test('retains the uid passed at construction', () {
      final request =
          buildRequest(id: '3k-m-2', professionalAuthUid: 'uid-model');
      expect(request.professionalAuthUid, 'uid-model');
      // The routing id is untouched — the uid travels alongside it.
      expect(request.professionalId, 'pro_1');
      expect(request.professionalAuthUid, isNot(request.professionalId));
    });

    test('copyWith carries the uid verbatim (re-key + status seams)', () {
      final base = buildRequest(id: '3k-m-3', professionalAuthUid: 'uid-carry');

      final reKeyed = base.copyWith(id: 'fresh-client-uuid');
      expect(reKeyed.id, 'fresh-client-uuid');
      expect(reKeyed.professionalAuthUid, 'uid-carry');

      final accepted =
          base.copyWith(status: RequestStatus.accepted, paymentMethod: 'd17');
      expect(accepted.status, RequestStatus.accepted);
      expect(accepted.paymentMethod, 'd17');
      expect(accepted.professionalAuthUid, 'uid-carry');
    });

    test('copyWith can explicitly override the uid (remote-merge inherit)', () {
      final base = buildRequest(id: '3k-m-4', professionalAuthUid: 'uid-old');
      expect(
        base.copyWith(professionalAuthUid: 'uid-new').professionalAuthUid,
        'uid-new',
      );
      // Passing null NEVER clears a stored uid (?? pattern).
      expect(
        base.copyWith(professionalAuthUid: null).professionalAuthUid,
        'uid-old',
      );
    });
  });
  // ─── 2. Creation-site resolution ───────────────────────────────────────
  group('creation-site resolution (mirrors booking/create-request screens)',
      () {
    late List<PendingProModel> seedPros;

    setUp(() {
      seedPros = List.of(AdminStore.pendingPros.value);
      AdminStore.pendingPros.value = [];
      // Phase 3P: approvals below are SERVER-FIRST — the fake boundary
      // confirms the provisioning (no real RPC in tests).
      AdminAuth.configure(FakeAdminAuthRepository(enrolled: true));
    });

    tearDown(() {
      AdminStore.pendingPros.value = seedPros;
      AdminAuth.resetToDefault();
    });

    test('real pro → uid travels into the created request', () async {
      final registered = AdminStore.registerPro(
        makePending(id: '3001', authUid: liveProUid),
      );
      final proCode = registered.proCode;
      expect(proCode, isNotNull);
      expect(await AdminStore.approvePro(registered.id), isTrue);

      // Exact expression used by create_request_screen._continue():
      // resolve the auth identity from the SAME id stored on the order.
      final resolvedAuthUid = ProfessionalsRepository.byId(proCode!)?.authUid;
      expect(resolvedAuthUid, liveProUid);

      final draft = buildRequest(
        id: '3k-real',
        professionalId: proCode,
        professionalAuthUid: resolvedAuthUid,
      );
      expect(draft.professionalAuthUid, liveProUid);
      // Routing id unchanged — still the public pro code, never the uid.
      expect(draft.professionalId, proCode);
    });

    test('booking-screen mirror: cached model is the stored id → its uid',
        () async {
      final registered = AdminStore.registerPro(
        makePending(id: '3002', authUid: bookingProUid),
      );
      final proCode = registered.proCode;
      expect(proCode, isNotNull);
      expect(await AdminStore.approvePro(registered.id), isTrue);

      // booking_screen._confirm() ternary, with an explicit widget id that
      // _pickProfessional() resolved (pro.id == resolvedProId → first arm).
      final pro = ProfessionalsRepository.byId(proCode!);
      expect(pro, isNotNull);
      final resolvedAuthUid = pro!.id == proCode
          ? pro.authUid
          : ProfessionalsRepository.byId(proCode)?.authUid;
      expect(resolvedAuthUid, bookingProUid);

      final request = buildRequest(
        id: '3k-booking',
        professionalId: proCode,
        professionalAuthUid: resolvedAuthUid,
      );
      expect(request.professionalId, proCode);
      expect(request.professionalAuthUid, bookingProUid);
    });

    test('stale/unknown id → null, never a foreign pro uid', () async {
      final registered = AdminStore.registerPro(
        makePending(id: '3003', authUid: foreignProUid),
      );
      final proCode = registered.proCode;
      expect(proCode, isNotNull);
      expect(await AdminStore.approvePro(registered.id), isTrue);

      // The resolved model belongs to the approved pro, but the id stored
      // on the order is a stale widget value the registry does not know —
      // the request must NOT inherit the resolved pro's uid.
      final pro = ProfessionalsRepository.byId(proCode!);
      expect(pro, isNotNull);
      const staleId = 'pro_stale_404';
      final resolvedAuthUid = pro!.id == staleId
          ? pro.authUid
          : ProfessionalsRepository.byId(staleId)?.authUid;
      expect(resolvedAuthUid, isNull);

      final request = buildRequest(
        id: '3k-stale',
        professionalId: staleId,
        professionalAuthUid: resolvedAuthUid,
      );
      expect(request.professionalAuthUid, isNull);
      expect(request.professionalId, staleId);
    });

    test('mock catalog pros → null uid at both creation sites', () {
      for (final mockId in <String>['pro_1', 'pro_5']) {
        final pro = ProfessionalsRepository.byId(mockId);
        expect(pro, isNotNull, reason: 'mock $mockId must exist');
        expect(pro!.authUid, isNull, reason: 'mock $mockId has no auth uid');

        // create-request site…
        final draft = buildRequest(
          id: '3k-mock-$mockId',
          professionalId: mockId,
          professionalAuthUid: ProfessionalsRepository.byId(mockId)?.authUid,
        );
        expect(draft.professionalAuthUid, isNull, reason: mockId);
        expect(draft.professionalId, mockId, reason: mockId);

        // booking site (cached-model branch: model.id == resolvedProId).
        final resolvedAuthUid = pro.id == mockId
            ? pro.authUid
            : ProfessionalsRepository.byId(mockId)?.authUid;
        expect(resolvedAuthUid, isNull, reason: mockId);
      }
    });
  });
  // ─── 3. Wire contract (orders.pro_id — Phase 3L) ────────────────────────
  group('wire contract (orders.pro_id)', () {
    test('toRow differs ONLY in pro_id: uid on the wire, display id absent',
        () {
      final withUid =
          buildRequest(id: '3k-w-1', professionalAuthUid: 'uid-wire');
      final withoutUid = buildRequest(id: '3k-w-1');

      final rowWith = OrdersRepository.toRow(withUid);
      final rowWithout = OrdersRepository.toRow(withoutUid);

      // Same key set; the ONLY difference is the uid column itself.
      expect([...rowWith.keys]..sort(), [...rowWithout.keys]..sort());
      expect(rowWith['pro_id'], 'uid-wire');
      expect(rowWithout['pro_id'], isNull);
      final withMinusPro = Map<String, dynamic>.from(rowWith)..remove('pro_id');
      final withoutMinusPro = Map<String, dynamic>.from(rowWithout)
        ..remove('pro_id');
      expect(withMinusPro, withoutMinusPro);
      // The display/routing id never travels on the wire (Phase 3L: the live
      // schema has no professional_id column at all).
      expect(rowWith.keys, isNot(contains('professional_id')));
      expect(rowWith.values, isNot(contains('pro_1')));
    });

    test('fromRow round-trip carries pro_id → uid; no display id invented', () {
      final original = buildRequest(
        id: '3k-w-2',
        professionalId: 'PRO-12345',
        professionalAuthUid: 'uid-wire',
      );
      final decoded =
          OrdersRepository.fromRow(OrdersRepository.toRow(original));
      expect(decoded, isNotNull);
      // Phase 3L: the wire row carries the uid, so a hydrated copy decodes it.
      expect(decoded!.professionalAuthUid, 'uid-wire');
      expect(decoded.professionalId, isEmpty,
          reason: 'PRO-12345 is not in the local registry — never fabricated');
      expect(decoded.id, '3k-w-2');
      expect(decoded.customerId, original.customerId);
      expect(decoded.message, original.message);
    });
  });

  // ─── 4. Local-flow preservation ────────────────────────────────────────
  group('local flow preserves the uid', () {
    setUp(RequestStore.reset);
    tearDown(RequestStore.reset);

    test('status transition (copyWith path) keeps the uid', () async {
      final paid = SubscriptionStore.isPaidSubscriber.value;
      SubscriptionStore.isPaidSubscriber.value = true; // skip the token gate
      try {
        final request =
            buildRequest(id: '3k-status-1', professionalAuthUid: 'uid-status');
        await RequestStore.add(request);
        expect(RequestStore.byId('3k-status-1')?.professionalAuthUid,
            'uid-status');

        expect(
          await RequestStore.updateStatus(
              '3k-status-1', RequestStatus.accepted),
          isTrue,
        );
        final updated = RequestStore.byId('3k-status-1')!;
        expect(updated.status, RequestStatus.accepted);
        expect(updated.professionalAuthUid, 'uid-status');
      } finally {
        SubscriptionStore.isPaidSubscriber.value = paid;
      }
    });

    test('realtime merge (applyRemoteOrder) inherits the local uid', () async {
      final request =
          buildRequest(id: '3k-merge-1', professionalAuthUid: 'uid-merge');
      await RequestStore.add(request);

      // What the realtime channel delivers since Phase 3L: a wire-built row
      // carrying the uid as `pro_id`.
      final wireRow =
          OrdersRepository.fromRow(OrdersRepository.toRow(request))!;
      expect(wireRow.professionalAuthUid, 'uid-merge');

      RequestStore.applyRemoteOrder(wireRow);
      expect(RequestStore.byId('3k-merge-1')?.professionalAuthUid, 'uid-merge');

      // A legacy remote row decoding WITHOUT `pro_id` still inherits the
      // local uid instead of stripping it (pre-3L shape).
      final legacyRow =
          Map<String, dynamic>.from(OrdersRepository.toRow(request))
            ..remove('pro_id');
      final legacyRemote = OrdersRepository.fromRow(legacyRow)!;
      expect(legacyRemote.professionalAuthUid, isNull);
      RequestStore.applyRemoteOrder(legacyRemote);
      expect(RequestStore.byId('3k-merge-1')?.professionalAuthUid, 'uid-merge');

      // A remote row that ALREADY carries a uid always wins.
      RequestStore.applyRemoteOrder(
          wireRow.copyWith(professionalAuthUid: 'uid-remote'));
      expect(
          RequestStore.byId('3k-merge-1')?.professionalAuthUid, 'uid-remote');
    });

    test('hydration merge inherits uid, keeps local-only rows on top', () {
      final localWithUid =
          buildRequest(id: '3k-hyd-1', professionalAuthUid: 'uid-hyd');
      final localOnly =
          buildRequest(id: '3k-hyd-local', professionalId: 'pro_5');
      final remoteSameId =
          OrdersRepository.fromRow(OrdersRepository.toRow(localWithUid))!;
      final remoteNew = OrdersRepository.fromRow(
          OrdersRepository.toRow(buildRequest(id: '3k-hyd-new')))!;
      // Phase 3L: the wire round-trip carries the uid (`pro_id`).
      expect(remoteSameId.professionalAuthUid, 'uid-hyd');

      final merged = RequestStore.mergeHydrated(
        [localWithUid, localOnly],
        [remoteSameId, remoteNew],
      );

      // Ordering contract: local-only rows first, then the remote history.
      expect(merged.map((r) => r.id).toList(),
          ['3k-hyd-local', '3k-hyd-1', '3k-hyd-new']);
      // The replaced row keeps the uid — the wire round-trip carried it
      // (`pro_id`) and the local inherit covers any legacy decode.
      expect(merged.firstWhere((r) => r.id == '3k-hyd-1').professionalAuthUid,
          'uid-hyd');
      // …and a genuinely NEW remote order stays null.
      expect(merged.firstWhere((r) => r.id == '3k-hyd-new').professionalAuthUid,
          isNull);
      // The kept local-only row is untouched.
      expect(merged.first.professionalId, 'pro_5');
    });
  });
  // ─── 5. Offline queue round-trip ───────────────────────────────────────
  group('offline queue round-trip (payload = untouched wire row)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OfflineQueue.debugReset();
      OfflineQueueBindings.registerAll();
      RequestStore.reset();
    });

    tearDown(() async {
      ConnectivityStore.debugSetOnline(true);
      await OfflineQueue.debugReset();
      RequestStore.reset();
    });

    test('uid survives enqueue → restart → replay on the LOCAL order',
        () async {
      ConnectivityStore.debugSetOnline(false);

      final request = buildRequest(
        id: '3k-off-1',
        professionalAuthUid: 'uid-offline',
      );
      expect(await RequestStore.add(request), isTrue);

      // (a) The local durable copy carries the uid.
      expect(RequestStore.byId('3k-off-1')?.professionalAuthUid, 'uid-offline');

      // (b) The queued payload is EXACTLY the untouched wire row.
      final queued = OfflineQueue.pending.value
          .where((a) => a.type == QueuedActionType.createOrder)
          .toList();
      expect(queued, hasLength(1));
      final row = queued.single.payload['row'] as Map;
      expect([...row.keys]..sort(),
          [...OrdersRepository.toRow(request).keys]..sort());
      expect(row, OrdersRepository.toRow(request));
      // Phase 3L: the uid NOW travels on the wire as `pro_id`; the display
      // id never does (the live schema has no professional_id column).
      expect(row['pro_id'], 'uid-offline');
      expect(row.keys, isNot(contains('professional_id')));
      expect(row.values, isNot(contains('pro_1')));

      // (c) Survives a kill/restart (persist → wipe memory → restore).
      await OfflineQueue.persistToPrefs();
      OfflineQueue.pending.value = [];
      await OfflineQueue.loadFromPrefs();
      expect(OfflineQueue.length, 1);
      final restored = OfflineQueue.pending.value
          .firstWhere((a) => a.type == QueuedActionType.createOrder);
      expect((restored.payload['row'] as Map)['id'], '3k-off-1');
      expect((restored.payload['row'] as Map)['pro_id'], 'uid-offline');

      // (d) Reconnect → replay applies (unconfigured backend = local no-op
      // success) and the LOCAL order still carries the uid.
      ConnectivityStore.debugSetOnline(true);
      final report = await OfflineQueue.flush();
      expect(report.applied, 1);
      expect(report.dropped, 0);
      expect(OfflineQueue.isEmpty, isTrue);
      expect(RequestStore.byId('3k-off-1')?.professionalAuthUid, 'uid-offline');
    });
  });
}
