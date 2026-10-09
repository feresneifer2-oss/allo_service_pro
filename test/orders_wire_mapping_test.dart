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
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/data/orders_repository.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

import 'support/fake_admin_auth.dart';

/// Phase 3L — `OrdersRepository` wire mapping against the LIVE rich
/// `public.orders` schema (created in Phase 3H).
///
/// Contract under test:
/// - the INSERT payload contains ONLY real live columns (legacy names such
///   as `customer_id`, `professional_id`, `professional_name`, `message`
///   are never emitted);
/// - `pro_id` comes from `professionalAuthUid` — never from the display id —
///   and a null uid is refused BEFORE any network write;
/// - `client_id` carries the authenticated customer UUID from the model
///   (bound from `UserStore` at creation);
/// - order ids are RFC-4122 v4 UUIDs (the live `id` column is uuid);
/// - `fromRow` reads the NEW column names: `pro_id` → professionalAuthUid,
///   `description` → message, and resolves the display id only from the
///   local registry (empty when unknown — never fabricated from a UUID);
/// - validation / ownership checks use `client_id` / `pro_id`;
/// - the UPDATE patch touches only columns that exist (`updated_at` is
///   intentionally not managed by this layer);
/// - the offline queue keeps serializing exactly what `toRow` produces.
///
/// CODE ONLY: NO Supabase schema change, NO RLS, NO SQL executed here.
void main() {
  final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  /// Authenticated customer UUID (what `UserStore` binds at sign-in).
  const clientUid = '11111111-2222-4333-8444-555555555555';

  /// Authenticated professional UUID (`ProfessionalModel.authUid`).
  const proUid = '99999999-8888-4777-b666-555555555555';

  /// Registry-bound professional UUID — the identity the server-first
  /// approval provisions (Phase 3P; replaces the former 'uid-3l-registry'
  /// placeholder, which was not a valid uuid).
  const registryProUid = '12121212-3434-4565-8787-909090909090';

  ServiceRequest buildRequest({
    String id = '3l-req-1',
    String professionalId = 'pro_1',
    String? professionalAuthUid = proUid,
    String message = 'Message client',
    double? rating,
    String? reviewComment,
  }) =>
      ServiceRequest(
        id: id,
        serviceTitleFr: 'Plomberie',
        serviceTitleAr: 'سباكة',
        professionalId: professionalId,
        professionalAuthUid: professionalAuthUid,
        professionalName: 'Hatem Trabelsi',
        customerName: 'Client 3L',
        customerId: clientUid,
        dateTime: DateTime(2026, 3, 1, 10, 30),
        address: 'Ariana, Tunisie',
        message: message,
        rating: rating,
        reviewComment: reviewComment,
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

  /// The mandatory live columns (rating / review_comment included — both
  /// nullable and emitted only when set).
  const liveColumns = <String>{
    'id',
    'client_id',
    'pro_id',
    'status',
    'description',
    'created_at',
    'service_title_fr',
    'service_title_ar',
    'client_name',
    'pro_name',
    'scheduled_at',
    'address',
    'photo_paths',
    'payment_method',
    'rating',
    'review_comment',
  };

  /// Column names that do NOT exist on the live schema — never read,
  /// never written.
  const legacyColumns = <String>{
    'customer_id',
    'customer_name',
    'professional_id',
    'professional_name',
    'message',
  };
  // ─── 1. INSERT payload ─────────────────────────────────────────────────
  group('INSERT payload (live rich schema only)', () {
    test('toRow emits ONLY real orders columns', () {
      final row = OrdersRepository.toRow(
          buildRequest(rating: 4.5, reviewComment: 'Top'));
      expect(row.keys.toSet(), liveColumns);
      for (final legacy in legacyColumns) {
        expect(row.keys, isNot(contains(legacy)),
            reason: '$legacy does not exist on the live schema');
      }
    });

    test('rating / review_comment are omitted when null', () {
      final row = OrdersRepository.toRow(buildRequest());
      expect(row.keys.toSet(),
          liveColumns.difference({'rating', 'review_comment'}));
      expect(row.containsKey('rating'), isFalse);
      expect(row.containsKey('review_comment'), isFalse);
    });

    test('pro_id uses professionalAuthUid, never the display id', () {
      final row = OrdersRepository.toRow(buildRequest(
        professionalId: 'PRO-99999',
        professionalAuthUid: proUid,
      ));
      expect(row['pro_id'], proUid);
      expect(row.values, isNot(contains('PRO-99999')));
      expect(row.values, isNot(contains('pro_1')),
          reason: 'pro_N / PRO-XXXXX must never reach Supabase as pro_id');
    });

    test('description, names and client_id map to their live columns', () {
      final row = OrdersRepository.toRow(buildRequest(message: 'Fuite eau'));
      expect(row['description'], 'Fuite eau');
      expect(row['client_id'], clientUid);
      expect(row['client_name'], 'Client 3L');
      expect(row['pro_name'], 'Hatem Trabelsi');
      expect(row['service_title_fr'], 'Plomberie');
      expect(row['service_title_ar'], 'سباكة');
      expect(row['payment_method'], 'cash');
      expect(row['photo_paths'], isEmpty);
      expect(row['status'], 'pending');
      expect(DateTime.tryParse(row['created_at'] as String), isNotNull);
      expect(DateTime.tryParse(row['scheduled_at'] as String), isNotNull);
    });
  });

  // ─── 2. null professionalAuthUid fails safely ──────────────────────────
  group('null professionalAuthUid fails safely BEFORE the network', () {
    test('mock pro → failed, not notConfigured (guard precedes backend work)',
        () async {
      // The suite runs WITHOUT Supabase: reaching `notConfigured` would mean
      // the config check ran BEFORE the uid guard — i.e. the guard sits
      // behind a path that could already have touched the backend. Getting
      // `failed` proves the refusal happened first, with zero network.
      expect(OrdersRepository.isConfigured, isFalse);
      final outcome = await OrdersRepository.insertOrderDetailed(
          buildRequest(professionalAuthUid: null));
      expect(outcome, OrderInsertOutcome.failed);
    });

    test('the boolean facade reports the refusal as false', () async {
      expect(
          await OrdersRepository.insertOrder(
              buildRequest(professionalAuthUid: null, id: '3l-null-2')),
          isFalse);
    });

    test('a real uid keeps the local-only (notConfigured) contract', () async {
      final outcome =
          await OrdersRepository.insertOrderDetailed(buildRequest());
      expect(outcome, OrderInsertOutcome.notConfigured);
    });
  });
  // ─── 3. UUID order id ──────────────────────────────────────────────────
  group('UUID order id', () {
    test('the creation / re-key id helper mints valid, unique v4 UUIDs', () {
      final ids = [for (var i = 0; i < 32; i++) RequestStore.newClientId()];
      for (final id in ids) {
        expect(id, matches(uuidV4), reason: 'orders.id is a uuid column');
      }
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  // ─── 4. fromRow (NEW DB names) ─────────────────────────────────────────
  group('fromRow reads the NEW column names', () {
    late List<PendingProModel> seedPros;

    setUp(() {
      seedPros = List.of(AdminStore.pendingPros.value);
      AdminStore.pendingPros.value = [];
      // Phase 3P: the approval below is SERVER-FIRST — the fake boundary
      // confirms the provisioning (no real RPC in tests).
      AdminAuth.configure(FakeAdminAuthRepository(enrolled: true));
    });

    tearDown(() {
      AdminStore.pendingPros.value = seedPros;
      AdminAuth.resetToDefault();
    });

    test('pro_id → professionalAuthUid; display id resolved from registry',
        () async {
      final registered = AdminStore.registerPro(
          makePending(id: '3101', authUid: registryProUid));
      final proCode = registered.proCode;
      expect(proCode, isNotNull);
      expect(await AdminStore.approvePro(registered.id), isTrue);

      final original = buildRequest(
        professionalId: proCode!,
        professionalAuthUid: registryProUid,
        message: 'Description utile',
      );
      final decoded =
          OrdersRepository.fromRow(OrdersRepository.toRow(original))!;

      expect(decoded.professionalAuthUid, registryProUid);
      expect(decoded.professionalId, proCode,
          reason: 'the registry (app/local cache) supplies the display id');
      // description → message; client_id → customerId; names via the new
      // client_name / pro_name columns.
      expect(decoded.message, 'Description utile');
      expect(decoded.customerId, clientUid);
      expect(decoded.customerName, 'Client 3L');
      expect(decoded.professionalName, 'Hatem Trabelsi');
      expect(decoded.serviceTitleFr, 'Plomberie');
      expect(decoded.address, 'Ariana, Tunisie');
      expect(decoded.id, '3l-req-1');
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.dateTime, original.dateTime);
    });

    test('uid unknown to the registry → empty display id, never fabricated',
        () {
      final row = OrdersRepository.toRow(buildRequest(
        professionalId: 'pro_1',
        professionalAuthUid: 'uid-3l-unknown',
      ));
      final decoded = OrdersRepository.fromRow(row)!;
      expect(decoded.professionalAuthUid, 'uid-3l-unknown');
      expect(decoded.professionalId, isEmpty);
      expect(decoded.professionalId, isNot(startsWith('pro_')));
      expect(decoded.professionalId, isNot(startsWith('PRO-')));
    });

    test('row without pro_id (legacy shape) decodes uid null', () {
      final row =
          OrdersRepository.toRow(buildRequest(professionalAuthUid: null));
      final decoded = OrdersRepository.fromRow(row)!;
      expect(decoded.professionalAuthUid, isNull);
      expect(decoded.professionalId, isEmpty);
    });
  });
  // ─── 5. Validation & ownership (client_id / pro_id) ────────────────────
  group('validation & ownership use client_id / pro_id', () {
    test('isValidRow accepts the live shape and rejects legacy-only rows', () {
      final live =
          OrdersRepository.toRow(buildRequest(professionalAuthUid: proUid));
      expect(OrdersRepository.isValidRow(live), isTrue);

      // Ownership stamps under their LIVE names are mandatory…
      final noStamps = Map<String, dynamic>.from(live)
        ..remove('client_id')
        ..remove('pro_id');
      expect(OrdersRepository.isValidRow(noStamps), isFalse);

      // …and legacy ownership columns do NOT satisfy the gate (the old
      // `customer_id` / `professional_id` assumptions are gone).
      final legacyOnly = Map<String, dynamic>.from(noStamps)
        ..['customer_id'] = clientUid
        ..['professional_id'] = proUid;
      expect(OrdersRepository.isValidRow(legacyOnly), isFalse);

      expect(OrdersRepository.isValidRow({...live, 'status': 'nope'}),
          isFalse);
      expect(
          OrdersRepository.isValidRow({...live, 'scheduled_at': 'garbage'}),
          isFalse);
    });

    test('ownership stamps match only client_id / pro_id (never legacy)', () {
      final row =
          OrdersRepository.toRow(buildRequest(professionalAuthUid: proUid));

      expect(OrdersRepository.ownershipStampsMatch(row, clientUid), isTrue);
      expect(OrdersRepository.ownershipStampsMatch(row, proUid), isTrue);
      expect(
          OrdersRepository.ownershipStampsMatch(row, 'someone-else'), isFalse);

      // A row carrying ONLY legacy stamps belongs to no one.
      final legacy = Map<String, dynamic>.from(row)
        ..remove('client_id')
        ..remove('pro_id')
        ..['customer_id'] = clientUid
        ..['professional_id'] = proUid;
      expect(
          OrdersRepository.ownershipStampsMatch(legacy, clientUid), isFalse);
      expect(OrdersRepository.ownershipStampsMatch(legacy, proUid), isFalse);
    });
  });

  // ─── 6. UPDATE payload (live columns only) ─────────────────────────────
  group('UPDATE payload (live columns only)', () {
    test('touches only status / rating / review_comment', () {
      final patch = OrdersRepository.updatePatch(
        status: RequestStatus.completed,
        rating: 5,
        reviewComment: 'Bien',
      );
      expect(patch, <String, dynamic>{
        'status': 'completed',
        'rating': 5.0,
        'review_comment': 'Bien',
      });
      expect(patch.keys.toSet(), {'status', 'rating', 'review_comment'});
      // Nonexistent / unmanaged columns are never sent.
      expect(patch.containsKey('updated_at'), isFalse);
      expect(patch.containsKey('client_id'), isFalse);
      expect(patch.containsKey('pro_id'), isFalse);
      expect(patch.containsKey('professional_id'), isFalse);
      expect(patch.containsKey('customer_id'), isFalse);
    });

    test('empty when there is nothing to update', () {
      expect(OrdersRepository.updatePatch(), isEmpty);
      expect(
          OrdersRepository.updatePatch(
              status: null, rating: null, reviewComment: null),
          isEmpty);
    });
  });
  // ─── 7. Offline replay serialization ───────────────────────────────────
  group('offline replay serializes the live wire row', () {
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

    test('payload == toRow and survives persist → restore → flush', () async {
      ConnectivityStore.debugSetOnline(false);

      final request = buildRequest(id: '3l-off-1');
      expect(await RequestStore.add(request), isTrue);

      // (a) The queued payload is EXACTLY `toRow` — live columns only.
      final queued = OfflineQueue.pending.value
          .where((a) => a.type == QueuedActionType.createOrder)
          .toList();
      expect(queued, hasLength(1));
      final row = queued.single.payload['row'] as Map;
      expect(row, OrdersRepository.toRow(request));
      expect(row['pro_id'], proUid);
      expect(row['client_id'], clientUid);
      expect(row.keys, isNot(contains('professional_id')));
      expect(row.keys, isNot(contains('message')));

      // (b) Survives a kill/restart (persist → wipe memory → restore).
      await OfflineQueue.persistToPrefs();
      OfflineQueue.pending.value = [];
      await OfflineQueue.loadFromPrefs();
      expect(OfflineQueue.length, 1);
      final restored = OfflineQueue.pending.value
          .firstWhere((a) => a.type == QueuedActionType.createOrder);
      expect((restored.payload['row'] as Map)['pro_id'], proUid);

      // (c) Reconnect → replay applies (unconfigured backend = local no-op
      // success) and the wire round-trip kept the uid.
      ConnectivityStore.debugSetOnline(true);
      final report = await OfflineQueue.flush();
      expect(report.applied, 1);
      expect(report.dropped, 0);
      expect(OfflineQueue.isEmpty, isTrue);
      expect(RequestStore.byId('3l-off-1')?.professionalAuthUid, proUid);
    });
  });
}
