import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';

/// Regression guard for the CodeRabbit "guard null/empty ProCodes" feedback.
///
/// `AdminStore.entryForUser` used to read `p.proCode == u.proCode`. For an
/// admin-seeded dossier that carries NO PRO code and a pro whose own session
/// also has none, that comparison is `null == null` → TRUE, so the session was
/// bound to a FOREIGN dossier (wrong approval state, wrong tokens, wrong
/// proof) and the resubmission could re-queue the wrong entry. The lookup now
/// requires a valid, non-empty identifier on BOTH sides.
void main() {
  const seeded = PendingProModel(
    id: 'pp_seeded',
    name: 'Admin Seeded',
    phone: '+21620000000',
    professionFr: 'Plombier',
    professionAr: 'سبّاك',
    city: 'Tunis',
    submittedAt: '01/01/2026',
    // No PRO code and no proof: the exact shape that collided via null==null.
    status: 'pending',
  );

  const owned = PendingProModel(
    id: 'acc_9',
    name: 'Owned Pro',
    phone: '+21629999999',
    professionFr: 'Électricien',
    professionAr: 'كهربائي',
    city: 'Ariane',
    submittedAt: '02/01/2026',
    proCode: 'PRO-90001',
    status: 'rejected',
    rejectionReason: 'Document illisible',
  );

  UserModel proWith({String? proCode, String id = 'acc_unknown'}) => UserModel(
        id: id,
        name: 'Pro',
        phone: '+21620000001',
        role: UserRole.professional,
        proCode: proCode,
        verificationStatus: ProVerification.rejected,
      );

  setUp(() {
    AdminStore.pendingPros.value = <PendingProModel>[seeded, owned];
  });

  test('a null PRO code never matches an entry that also has none', () {
    expect(AdminStore.entryForUser(proWith(proCode: null)), isNull,
        reason: 'null == null must never select a foreign dossier');
  });

  test('a blank / whitespace PRO code is refused', () {
    expect(AdminStore.entryForUser(proWith(proCode: '')), isNull);
    expect(AdminStore.entryForUser(proWith(proCode: '   ')), isNull);
  });

  test('a valid non-empty PRO code resolves its OWN entry', () {
    final entry = AdminStore.entryForUser(proWith(proCode: 'PRO-90001'));
    expect(entry, isNotNull);
    expect(entry!.id, 'acc_9');
  });

  test('a padded PRO code is normalized before matching', () {
    final entry = AdminStore.entryForUser(proWith(proCode: '  PRO-90001 '));
    expect(entry?.id, 'acc_9');
  });

  test('the legacy account-id fallback still reconciles a dossier', () {
    final entry = AdminStore.entryForUser(proWith(proCode: null, id: 'acc_9'));
    expect(entry?.id, 'acc_9',
        reason: 'entries written before PRO codes must stay reachable');
  });

  test('a client session never owns a pro dossier', () {
    final client = UserModel(
      id: 'acc_9',
      name: 'Client',
      phone: '+21620000002',
      role: UserRole.client,
      proCode: 'PRO-90001',
    );
    expect(AdminStore.entryForUser(client), isNull);
    expect(AdminStore.entryForUser(null), isNull);
  });
}
