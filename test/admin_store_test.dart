import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';

import 'support/fake_admin_auth.dart';

// Phase 1 note: the credential-comparison groups (`matchesAdmin`, the
// `debug*AdminCredentials` hooks and the configured-identity signature) were
// REMOVED with the client-side gate. Admin authorization is now decided
// server-side — its coverage lives in test/admin_authorization_test.dart and
// test/startup_session_test.dart (cold-start re-validation).

void main() {
  tearDown(AdminAuth.resetToDefault);

  group('AdminStore · counters sanity', () {
    test('pendingCount counts only pending pros', () {
      // Seeded demo data contains two pending professionals.
      expect(AdminStore.pendingCount >= 2, isTrue);
    });
  });

  group('AdminStore · pro registration sync (Pro → Admin)', () {
    test('registerPro lands a PENDING entry the En-attente tab can see', () {
      final before = AdminStore.pendingCount;

      final pro = AdminStore.registerPro(PendingProModel(
        id: 'sync-test-1',
        name: 'Slim Trabelsi',
        phone: '98765432',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        status: 'pending',
        submittedAt: DateTime.now().toIso8601String(),
      ));

      // The new entry lands at the top of the registry…
      expect(AdminStore.pendingPros.value.first.id, 'sync-test-1');
      // …with a pending status the "En attente" filter matches…
      expect(pro.status, 'pending');
      // …and the badge counter reflects it immediately.
      expect(AdminStore.pendingCount, before + 1);
    });

    test('approval removes the pro from the pending counter', () async {
      // Phase 3P — SERVER-FIRST: the approval provisions the professional on
      // the backend first. The fake boundary confirms it (no real RPC).
      AdminAuth.configure(FakeAdminAuthRepository(enrolled: true));
      final pro = AdminStore.registerPro(PendingProModel(
        id: 'sync-test-2',
        name: 'Amel Jlassi',
        phone: '22334455',
        professionFr: 'Peintre',
        professionAr: 'دهانة',
        status: 'pending',
        submittedAt: DateTime.now().toIso8601String(),
        // The server gate requires a REAL Supabase identity (uuid shape).
        authUid: '11111111-2222-4333-8444-555555555555',
      ));
      final before = AdminStore.pendingCount;

      // AWAITED (CodeRabbit): `approvePro` persists + syncs the credential
      // record asynchronously — settle it before asserting the registry.
      expect(await AdminStore.approvePro(pro.id), isTrue);

      expect(AdminStore.pendingCount, before - 1);
      expect(
        AdminStore.pendingPros.value.firstWhere((p) => p.id == pro.id).status,
        'approved',
      );
    });

    test('registration persists and survives an app restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AdminStore.pendingPros.value = [];

      AdminStore.registerPro(PendingProModel(
        id: 'sync-test-3',
        name: 'Mongi Karoui',
        phone: '55667788',
        professionFr: 'Electricien',
        professionAr: 'كهربائي',
        status: 'pending',
        submittedAt: DateTime.now().toIso8601String(),
      ));
      await AdminStore.persistToPrefs();

      // Simulate a cold restart: registry reloads from SharedPreferences.
      AdminStore.pendingPros.value = [];
      await AdminStore.loadFromPrefs();

      expect(
        AdminStore.pendingPros.value.any(
          (p) => p.id == 'sync-test-3' && p.status == 'pending',
        ),
        isTrue,
      );
    });
  });
}
