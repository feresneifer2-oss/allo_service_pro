import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

/// PHASE 8 · R1 + R3 — SERVER-AUTHORITATIVE PRO VERIFICATION.
///
/// These tests reproduce the REAL cross-device approval: the admin approves
/// from THEIR device while the pro's device keeps the dossier written at
/// registration (`pro_<timestamp>`, status `pending`). The existing same-device
/// test (`batch12_email_auth_test` · "approval reaches an EMAIL-ONLY pro after
/// a cold restart") can never reach this state, because there the admin
/// approves on the pro's own device and the local registry is already
/// `approved` — which is exactly why the production bug went unnoticed.
const _uid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const _proCode = 'PRO-04242';
const _localId = 'pro_1700000000000';
const _email = 'sami.pro@allo.tn';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The dossier as the REGISTRATION wizard wrote it on this device.
  PendingProModel localDossier() => const PendingProModel(
        id: _localId,
        name: 'Sami',
        phone: '22110033',
        email: _email,
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '01/01/2026',
        docImage: 'local/proof.jpg',
        status: 'pending',
        proCode: _proCode,
        authUid: _uid,
      );

  Future<void> bindSession(ProVerification status) => UserStore.set(
        name: 'Sami',
        phone: '22110033',
        email: _email,
        role: UserRole.professional,
        proCode: _proCode,
        verificationStatus: status,
      );

  /// The authoritative server answer: `true`/`false` = a CONFIRMED status,
  /// `null` = transient failure (offline / timeout / RLS).
  void serverAnswers(bool? verified) {
    ProfileRepository.debugIsVerifiedOverride = () async => verified;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UserStore.user.value = null;
    ProProfileStore.tokens.value = 150;
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.status.value = SubscriptionStatus.inactive;
    SubscriptionStore.activatedAt.value = null;
    ProfileRepository.debugIsVerifiedOverride = null;
    AdminStore.debugApprovedProsOverride = null;
    // A backend IS configured: the scenario that produced the bug.
    SupabaseAuthService.debugConfiguredOverride = true;
    AdminStore.pendingPros.value = [localDossier()];
  });

  tearDown(() {
    SupabaseAuthService.debugResetOverrides();
    ProfileRepository.debugIsVerifiedOverride = null;
    AdminStore.debugApprovedProsOverride = null;
    UserStore.user.value = null;
  });

  // ── T1 ────────────────────────────────────────────────────────────────
  test(
      'T1 · approved session + stale local pending + server confirms approved '
      '→ stays approved, no downgrade, no duplicate', () async {
    await bindSession(ProVerification.approved);
    serverAnswers(true);

    await AdminStore.syncSessionStoresForCurrentUser();

    final u = UserStore.user.value!;
    expect(u.verificationStatus, ProVerification.approved,
        reason: 'the confirmed server approval must survive the local mirror');
    expect(u.verificationUnconfirmed, isFalse);
    expect(u.needsVerificationGate, isFalse);
    // R3: the sync never invents a second dossier for the same professional.
    expect(AdminStore.pendingPros.value.length, 1);
    // The claim that makes the test meaningful: the LOCAL cache still says
    // `pending`, and it lost — the server decided.
    expect(AdminStore.entryForUser(u)!.status, 'pending');
  });

  // ── T2 ────────────────────────────────────────────────────────────────
  test(
      'T2 · approved session + stale local pending + server failure '
      '→ approved preserved, flagged unconfirmed, never downgraded', () async {
    await bindSession(ProVerification.approved);
    serverAnswers(null); // transient failure

    await AdminStore.syncSessionStoresForCurrentUser();

    final u = UserStore.user.value!;
    expect(u.verificationStatus, ProVerification.approved,
        reason: 'a failed read is NOT a pending decision');
    expect(u.verificationUnconfirmed, isTrue,
        reason: 'the session must advertise that the status is unconfirmed');
    expect(u.needsVerificationGate, isFalse,
        reason: 'the pro keeps dashboard access on the last known good state');
    expect(AdminStore.pendingPros.value.length, 1);
  });

  // ── T3 ────────────────────────────────────────────────────────────────
  test(
      'T3 · hydration with an existing pro_<timestamp> dossier → updates it '
      'in place (proCode kept, status approved, no duplicate)', () async {
    AdminStore.debugApprovedProsOverride = () async => <dynamic>[
          <String, dynamic>{
            'id': _uid,
            'name': 'Sami',
            'phone': '22110033',
            'email': _email,
            'specialty': 'Plombier',
            'bio': 'Bio serveur',
          },
        ];

    final synced = await AdminStore.hydrateApprovedProsFromSupabase();

    expect(synced, 1);
    expect(AdminStore.pendingPros.value.length, 1,
        reason: 'the server uuid must MATCH the local dossier, not add one');

    final entry = AdminStore.pendingPros.value.single;
    expect(entry.id, _localId, reason: 'the local dossier id is preserved');
    expect(entry.proCode, _proCode, reason: 'the PRO code is preserved');
    expect(entry.authUid, _uid);
    expect(entry.status, 'approved', reason: 'confirmed server status applied');
    expect(entry.docImage, 'local/proof.jpg',
        reason: 'device-local metadata is never dropped');
    expect(entry.name, 'Sami');

    // The lookup every navigation gate uses must resolve to that ONE record.
    await bindSession(ProVerification.pending);
    final resolved = AdminStore.entryForUser(UserStore.user.value);
    expect(resolved, isNotNull);
    expect(resolved!.id, _localId);
    expect(resolved.status, 'approved');
  });

  // ── T4 ────────────────────────────────────────────────────────────────
  test('T4 · pending session + server failure → stays pending, never approved',
      () async {
    await bindSession(ProVerification.pending);
    serverAnswers(null);

    await AdminStore.syncSessionStoresForCurrentUser();

    final u = UserStore.user.value!;
    expect(u.verificationStatus, ProVerification.pending);
    expect(u.verificationStatus, isNot(ProVerification.approved));
    expect(u.verificationStatus, isNot(ProVerification.rejected));
    expect(u.verificationUnconfirmed, isTrue);
    expect(u.needsVerificationGate, isTrue, reason: 'stays on the gate');
  });
}
