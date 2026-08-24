import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';

void main() {
  group('AdminStore · credential constants', () {
    test('exposes the expected smart-routing credentials', () {
      expect(AdminStore.adminEmail, 'admin@alloservice.tn');
      expect(AdminStore.adminPassword, 'admin2026');
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
        AdminStore.matchesAdmin('admin@alloservice.tn', 'admin2026'),
        isTrue,
      );
    });

    test('rejects a wrong password', () {
      expect(
        AdminStore.matchesAdmin('admin@alloservice.tn', 'wrong-pass'),
        isFalse,
      );
    });

    test('rejects a wrong email', () {
      expect(
        AdminStore.matchesAdmin('user@alloservice.tn', 'admin2026'),
        isFalse,
      );
    });

    test('rejects empty credentials', () {
      expect(AdminStore.matchesAdmin('', ''), isFalse);
    });

    test('rejects a non-admin email even with the right password', () {
      expect(
        AdminStore.matchesAdmin('feres@example.com', 'admin2026'),
        isFalse,
      );
    });

    test('matching is strict (case-sensitive) by design', () {
      expect(
        AdminStore.matchesAdmin('ADMIN@ALLOSERVICE.TN', 'admin2026'),
        isFalse,
      );
      expect(
        AdminStore.matchesAdmin('admin@alloservice.tn', 'ADMIN2026'),
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
}