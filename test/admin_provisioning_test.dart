import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';

import 'support/fake_admin_auth.dart';

/// A well-formed UUID — the ONLY identity `approvePro` will provision.
const String kProvisionProUid = '11111111-2222-4333-8444-555555555555';

/// PHASE 3P — SERVER-FIRST admin approval provisioning (focused suite).
///
/// Contract under test:
/// - `approvePro` FIRST calls the AdminAuth boundary
///   (`admin_provision_professional` → `p_user_id` / `p_specialty` / `p_bio`)
///   and reports `true` ONLY when the server confirmed the professional;
/// - a null / invalid `authUid` never reaches the RPC and never approves;
/// - an RPC failure leaves the entry PENDING: no 150 tokens, no `cin` badge,
///   no inflated KPI counter, no approved state anywhere;
/// - mapping: `specialtiesFr` joined with ", " (fallback `professionFr`,
///   null when both empty) and `description` → bio (null when blank);
/// - idempotent replays do NO extra work (no second round-trip) and never
///   approve twice;
/// - the success snack in `AdminDashboardScreen` is bound to exactly this
///   boolean — `false` shows the controlled error message instead.
///
/// The AdminAuth boundary is FAKED here: no real RPC, no Supabase client, no
/// SQL, no schema/RLS change — nothing in this suite touches production
/// infrastructure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AdminStore.pendingPros.value = [];
  });

  tearDown(AdminAuth.resetToDefault);

  /// Registers a pending entry with the given identity / payload fields.
  PendingProModel register({
    String? authUid = kProvisionProUid,
    String professionFr = 'Plombier',
    List<String> specialtiesFr = const [],
    String? description,
  }) =>
      AdminStore.registerPro(PendingProModel(
        id: 'p3p-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Karim 3P',
        phone: '20000000',
        email: 'karim.3p@example.tn',
        professionFr: professionFr,
        professionAr: 'سبّاك',
        status: 'pending',
        submittedAt: '01/01/2026',
        authUid: authUid,
        specialtiesFr: specialtiesFr,
        description: description,
      ));

  PendingProModel entryOf(PendingProModel pro) => AdminStore.pendingPros.value
      .firstWhere((p) => p.id == pro.id);

  FakeAdminAuthRepository approveFake({
    bool enrolled = true,
    bool configured = true,
  }) {
    final fake = FakeAdminAuthRepository(
      enrolled: enrolled,
      configured: configured,
    );
    AdminAuth.configure(fake);
    return fake;
  }

  group('AdminStore.approvePro · server-first provisioning', () {
    test('successful RPC → the local approval runs (status/tokens/badge/KPI)',
        () async {
      final fake = approveFake();
      final pro = register(
        specialtiesFr: const ['Plomberie', 'Peinture'],
        description: 'Artisan expérimenté',
      );
      final before = AdminStore.totalPros.value;

      expect(await AdminStore.approvePro(pro.id), isTrue);

      final entry = entryOf(pro);
      expect(entry.status, 'approved');
      expect(entry.tokens, 150);
      expect(entry.badges, contains('cin'));
      expect(AdminStore.totalPros.value, before + 1);
      // The server was consulted EXACTLY once, with the registry identity.
      expect(fake.provisionCalls, 1);
      expect(fake.lastProvisionUserId, kProvisionProUid);
    });

    test('RPC failure → NO local approval state; the entry stays pending',
        () async {
      final fake = approveFake();
      fake.provisionSucceeds = false;
      final pro = register();
      final before = AdminStore.totalPros.value;

      expect(await AdminStore.approvePro(pro.id), isFalse);

      expect(fake.provisionCalls, 1);
      final entry = entryOf(pro);
      expect(entry.status, 'pending'); // MUST remain pending
      expect(entry.tokens, 0); // no 150 starter tokens
      expect(entry.badges, isNot(contains('cin'))); // no approval badge
      expect(AdminStore.totalPros.value, before); // no inflated KPI
    });

    test('non-admin boundary (enrolled = false) refuses the approval',
        () async {
      final fake = approveFake(enrolled: false);
      final pro = register();

      expect(await AdminStore.approvePro(pro.id), isFalse);

      expect(fake.provisionCalls, 1);
      expect(entryOf(pro).status, 'pending');
    });

    test('unconfigured boundary (no backend) refuses the approval', () async {
      approveFake(configured: false);
      final pro = register();

      expect(await AdminStore.approvePro(pro.id), isFalse);
      expect(entryOf(pro).status, 'pending');
    });

    test('null authUid → RPC NEVER called, approval stays pending', () async {
      final fake = approveFake();
      final pro = register(authUid: null);
      expect(pro.authUid, isNull);

      expect(await AdminStore.approvePro(pro.id), isFalse);

      expect(fake.provisionCalls, 0);
      expect(entryOf(pro).status, 'pending');
    });

    test('invalid (non-uuid) authUid → RPC NEVER called, stays pending',
        () async {
      final fake = approveFake();
      final pro = register(authUid: 'not-a-uuid');

      expect(await AdminStore.approvePro(pro.id), isFalse);

      expect(fake.provisionCalls, 0);
      expect(entryOf(pro).status, 'pending');
    });

    test('unknown id → false, nothing provisioned', () async {
      final fake = approveFake();

      expect(await AdminStore.approvePro('p3p-missing'), isFalse);
      expect(fake.provisionCalls, 0);
    });
  });

  group('AdminStore.approvePro · RPC parameter mapping', () {
    test('specialtiesFr are joined with ", "', () async {
      final fake = approveFake();
      final pro = register(specialtiesFr: const ['Plomberie', 'Peinture']);

      expect(await AdminStore.approvePro(pro.id), isTrue);

      expect(fake.lastProvisionSpecialty, 'Plomberie, Peinture');
    });

    test('blank chips are dropped → the profession label is the fallback',
        () async {
      final fake = approveFake();
      final pro = register(
        professionFr: 'Électricien',
        specialtiesFr: const ['  '],
      );

      expect(await AdminStore.approvePro(pro.id), isTrue);

      expect(fake.lastProvisionSpecialty, 'Électricien');
    });

    test('no specialty source at all → null (server stores/preserves)',
        () async {
      final fake = approveFake();
      final pro = register(professionFr: '');

      expect(await AdminStore.approvePro(pro.id), isTrue);

      expect(fake.lastProvisionSpecialty, isNull);
    });

    test('description becomes the bio (trimmed)', () async {
      final fake = approveFake();
      final pro = register(description: "  15 ans d'expérience  ");

      expect(await AdminStore.approvePro(pro.id), isTrue);

      expect(fake.lastProvisionBio, "15 ans d'expérience");
    });

    test('missing or blank description → null bio', () async {
      final fake = approveFake();
      final noDescription = register();
      final blankDescription = register(description: '   ');

      expect(await AdminStore.approvePro(noDescription.id), isTrue);
      expect(fake.lastProvisionBio, isNull);

      expect(await AdminStore.approvePro(blankDescription.id), isTrue);
      expect(fake.lastProvisionBio, isNull);
    });
  });

  group('AdminStore.approvePro · idempotency replay', () {
    test('an already-approved entry replays NO work (no second round-trip)',
        () async {
      final fake = approveFake();
      final pro = register();

      expect(await AdminStore.approvePro(pro.id), isTrue);
      expect(fake.provisionCalls, 1);
      final firstTokens = entryOf(pro).tokens;

      // Replay: still reports success, but nothing runs a second time.
      expect(await AdminStore.approvePro(pro.id), isTrue);
      expect(fake.provisionCalls, 1, reason: 'no redundant server round-trip');
      final entry = entryOf(pro);
      expect(entry.tokens, firstTokens);
      expect(entry.badges.where((b) => b == 'cin'), hasLength(1));
    });
  });

  group('AdminDashboardScreen · success-snack gate (UI contract)', () {
    test('approvePro reports true ONLY on a confirmed provisioning', () async {
      // The dashboard binds its success snack to exactly this boolean: `true`
      // → "approuvé" snack, `false` → controlled error + card stays pending
      // (see admin_dashboard_screen.dart, Phase 3P branch).
      final fake = approveFake();
      final ok = register();
      expect(await AdminStore.approvePro(ok.id), isTrue);

      fake.provisionSucceeds = false;
      final refused = register();
      expect(await AdminStore.approvePro(refused.id), isFalse);
      expect(entryOf(refused).status, 'pending');
    });
  });
}
