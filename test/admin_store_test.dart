import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';

void main() {
  group('AdminStore · credential constants', () {
    test('exposes the expected admin credentials', () {
      expect(AdminStore.adminEmail, 'feres.neifer2@gmail.com');
      expect(AdminStore.adminPassword, '24449959');
    });
  });

  group('AdminStore.matchesAdmin · smart matching logic', () {
    test('accepts the exact admin pair', () {
      expect(
        AdminStore.matchesAdmin(
          AdminStore.adminEmail,
          AdminStore.adminPassword,
        ),
        isTrue,
      );
    });

    test('accepts literal expected values', () {
      expect(
        AdminStore.matchesAdmin('feres.neifer2@gmail.com', '24449959'),
        isTrue,
      );
    });

    test('rejects a wrong password', () {
      expect(
        AdminStore.matchesAdmin('feres.neifer2@gmail.com', 'wrong-pass'),
        isFalse,
      );
    });

    test('rejects a wrong email', () {
      expect(
        AdminStore.matchesAdmin('user@alloservice.tn', '24449959'),
        isFalse,
      );
    });

    test('rejects empty credentials', () {
      expect(AdminStore.matchesAdmin('', ''), isFalse);
    });

    test('rejects a non-admin email even with the right password', () {
      expect(
        AdminStore.matchesAdmin('feres@example.com', '24449959'),
        isFalse,
      );
    });

    test('matching is strict (case-sensitive) by design', () {
      expect(
        AdminStore.matchesAdmin('FERES.NEIFER2@GMAIL.COM', '24449959'),
        isFalse,
      );
      expect(
        AdminStore.matchesAdmin('feres.neifer2@gmail.com', '24449959A'),
        isFalse,
      );
    });
  });

  group('AdminStore · counters sanity', () {
    test('pendingCount counts only pending pros', () {
      // Seeded demo data contains two pending professionals.
      expect(AdminStore.pendingCount >= 2, isTrue);
    });
  });

  group('AdminStore · pro registration sync (Pro → Admin)', () {
    test('registerPro lands a PENDING entry the En-attente tab can see',
        () {
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

    test('approval removes the pro from the pending counter', () {
      final pro = AdminStore.registerPro(PendingProModel(
        id: 'sync-test-2',
        name: 'Amel Jlassi',
        phone: '22334455',
        professionFr: 'Peintre',
        professionAr: 'دهانة',
        status: 'pending',
        submittedAt: DateTime.now().toIso8601String(),
      ));
      final before = AdminStore.pendingCount;

      AdminStore.approvePro(pro.id);

      expect(AdminStore.pendingCount, before - 1);
      expect(
        AdminStore.pendingPros.value
            .firstWhere((p) => p.id == pro.id)
            .status,
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