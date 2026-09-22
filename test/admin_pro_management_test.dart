import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';

void main() {
  setUp(() {
    AdminStore.pendingPros.value = [
      const PendingProModel(
        id: 'mng-1',
        name: 'Ahmed Gestion',
        phone: '20111222',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '2026-01-01',
        status: 'approved',
        proCode: 'PRO-7001',
        badges: ['cin'],
      ),
      const PendingProModel(
        id: 'mng-2',
        name: 'Sami Frozen',
        phone: '20333444',
        professionFr: 'Peintre',
        professionAr: 'دهان',
        submittedAt: '2026-01-02',
        status: 'approved',
        proCode: 'PRO-7002',
        deactivated: true,
      ),
    ];
  });

  test('badge add/remove updates the registry instantly', () {
    AdminStore.addBadge('mng-1', 'recommended');
    expect(
      AdminStore.pendingPros.value.first.badges,
      containsAll(['cin', 'recommended']),
    );

    AdminStore.removeBadge('mng-1', 'cin');
    expect(AdminStore.pendingPros.value.first.badges, ['recommended']);

    // Duplicate add is a no-op.
    AdminStore.addBadge('mng-1', 'recommended');
    expect(AdminStore.pendingPros.value.first.badges.length, 1);
  });

  test('deactivated pros disappear from client listings (real-time)', () {
    final ids = ProfessionalsRepository.live.map((p) => p.id).toList();

    // Active pro surfaces with his admin badges…
    final active = ProfessionalsRepository.byId('PRO-7001');
    expect(active, isNotNull);
    expect(active!.badges, ['cin']);

    // …while the deactivated one is fully hidden.
    expect(ids, isNot(contains('PRO-7002')));

    // Re-activating brings him back instantly.
    AdminStore.setDeactivated('mng-2', deactivated: false);
    expect(
      ProfessionalsRepository.live.map((p) => p.id),
      contains('PRO-7002'),
    );
  });

  test('badge & deactivation changes persist across restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AdminStore.addBadge('mng-1', 'top');
    AdminStore.setDeactivated('mng-2', deactivated: false);
    await AdminStore.persistToPrefs();

    // Cold restart simulation.
    AdminStore.pendingPros.value = [];
    await AdminStore.loadFromPrefs();

    final mng1 = AdminStore.pendingPros.value.firstWhere(
      (p) => p.id == 'mng-1',
    );
    final mng2 = AdminStore.pendingPros.value.firstWhere(
      (p) => p.id == 'mng-2',
    );

    expect(mng1.badges, containsAll(['cin', 'top']));
    expect(mng2.deactivated, isFalse);
  });
}
