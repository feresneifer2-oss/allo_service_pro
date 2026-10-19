import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';

import 'support/fake_admin_auth.dart';

/// Phase 3J — `authUid` propagation through the LOCAL models only.
///
/// Scope contract (must stay true):
/// - `PendingProModel.authUid` is nullable, persisted, and backward
///   compatible (old records load with null).
/// - `ProfessionalModel.authUid` is nullable; `id` / PRO-XXXXX routing is
///   UNCHANGED.
/// - `ProfessionalsRepository.live` copies pending -> client-facing.
/// - `withAvailability` clones preserve the UID.
/// - Mock catalog entries keep `authUid == null`.
/// - NO Supabase, NO orders, NO RLS touched here.
void main() {
  PendingProModel makePending({String? authUid, String id = 'p-3j-1'}) =>
      PendingProModel(
        id: id,
        name: 'Karim Test',
        phone: '20000000',
        email: 'karim.test@example.tn',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        status: 'pending',
        submittedAt: '01/01/2026',
        authUid: authUid,
      );

  /// Supabase professional identities (valid uuids): the server-first
  /// approval gate (Phase 3P) refuses a non-uuid identity BEFORE the RPC is
  /// reached, so the former non-uuid placeholders became constants.
  const liveProUid = 'dddddddd-eeee-4fff-8aaa-bbbbbbbbbbbb';
  const overlayProUid = 'eeeeeeee-ffff-4aaa-8bbb-cccccccccccc';

  group('PendingProModel.authUid serialization', () {
    test('round-trips authUid through toJson/fromJson', () {
      final pro = makePending(authUid: 'uid-1111-2222');
      final restored = PendingProModel.fromJson(pro.toJson());
      expect(restored.authUid, 'uid-1111-2222');
    });

    test('backward compatible: absent key loads as null', () {
      final pro = makePending(authUid: 'uid-1111-2222');
      final json = pro.toJson()..remove('authUid');
      expect(json.containsKey('authUid'), isFalse);
      final restored = PendingProModel.fromJson(json);
      expect(restored.authUid, isNull);
    });

    test('backward compatible: null / empty / whitespace decode to null', () {
      for (final raw in <Map<String, dynamic>>[
        makePending().toJson()..['authUid'] = null,
        makePending().toJson()..['authUid'] = '',
        makePending().toJson()..['authUid'] = '   ',
        makePending().toJson()..['authUid'] = 12345,
      ]) {
        expect(PendingProModel.fromJson(raw).authUid, isNull,
            reason: 'raw=${raw['authUid']}');
      }
    });

    test('copyWith preserves authUid when the arg is omitted', () {
      final pro = makePending(authUid: 'uid-carry');
      // Approval-style updates must not strip the identity.
      final updated = pro.copyWith(status: 'approved', tokens: 150);
      expect(updated.authUid, 'uid-carry');
      expect(updated.status, 'approved');
    });
  });

  group('ProfessionalModel propagation from pending registry', () {
    // Phase 3P — SERVER-FIRST: an approval below provisions the professional
    // through the AdminAuth boundary; the fake confirms it (no real RPC).
    setUp(() => AdminAuth.configure(FakeAdminAuthRepository(enrolled: true)));
    tearDown(AdminAuth.resetToDefault);

    test('live copies authUid while keeping the PRO-XXXXX id', () async {
      final seed = List.of(AdminStore.pendingPros.value);
      try {
        AdminStore.pendingPros.value = [];
        final registered = AdminStore.registerPro(
          makePending(authUid: liveProUid, id: 'p-3j-live'),
        );
        expect(registered.proCode, isNotNull);
        expect(await AdminStore.approvePro(registered.id), isTrue);

        final live = ProfessionalsRepository.live;
        final entry = live.firstWhere((p) => p.id == registered.proCode);
        // Routing id is STILL the public code…
        expect(entry.id, registered.proCode);
        // …and the auth identity travels alongside it.
        expect(entry.authUid, liveProUid);
      } finally {
        AdminStore.pendingPros.value = seed;
      }
    });

    test('legacy draft without authUid is NEVER approved (server-first gate)',
        () async {
      // Phase 3P: without a server identity (`authUid`) the provisioning RPC
      // cannot run — the approval is refused, the RPC is never called, and
      // the entry stays pending, so no "approved" state can exist without a
      // backend row.
      final fake = FakeAdminAuthRepository(enrolled: true);
      AdminAuth.configure(fake);
      final seed = List.of(AdminStore.pendingPros.value);
      try {
        AdminStore.pendingPros.value = [];
        final registered = AdminStore.registerPro(
          makePending(id: 'p-3j-legacy'),
        );
        expect(registered.authUid, isNull);

        final approved = await AdminStore.approvePro(registered.id);

        expect(approved, isFalse);
        expect(fake.provisionCalls, 0,
            reason: 'no server identity → the RPC must never be reached');
        final entry = AdminStore.pendingPros.value
            .firstWhere((p) => p.id == registered.id);
        expect(entry.status, 'pending');
        // …and the client feed never lists it as a live professional.
        expect(
          ProfessionalsRepository.live.any((p) => p.id == registered.proCode),
          isFalse,
        );
      } finally {
        AdminStore.pendingPros.value = seed;
      }
    });

    test('withAvailability clone preserves authUid', () async {
      final seed = List.of(AdminStore.pendingPros.value);
      try {
        AdminStore.pendingPros.value = [];
        final registered = AdminStore.registerPro(
          makePending(authUid: overlayProUid, id: 'p-3j-overlay'),
        );
        expect(await AdminStore.approvePro(registered.id), isTrue);

        final entry = ProfessionalsRepository.live
            .firstWhere((p) => p.id == registered.proCode);
        final flipped = entry.withAvailability(!entry.availableNow);
        expect(flipped.authUid, entry.authUid);
        expect(flipped.authUid, overlayProUid);
        // Same-value overlay returns the identical instance.
        expect(entry.withAvailability(entry.availableNow), same(entry));
      } finally {
        AdminStore.pendingPros.value = seed;
      }
    });
  });

  group('Mock catalog', () {
    test('every mock professional keeps authUid null', () {
      expect(allProfessionals, isNotEmpty);
      for (final p in allProfessionals) {
        expect(p.authUid, isNull, reason: 'mock ${p.id}');
      }
    });
  });
}
