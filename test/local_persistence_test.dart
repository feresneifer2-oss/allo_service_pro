import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh (empty) mock storage + default in-memory state for every test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SubscriptionStore.status.value = SubscriptionStatus.active;
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.activatedAt.value = null;
    ProProfileStore.tokens.value = 150;
  });

  group('ProProfileStore · token persistence', () {
    test('falls back to the default trial balance when nothing is saved',
        () async {
      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.tokens.value, 150);
    });

    test('falls back to defaults for unrelated saved keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'unrelated_key': 'hello',
      });

      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.tokens.value, 150);
    });

    test('deductions persist and survive a simulated app restart', () async {
      expect(ProProfileStore.deductTokens(40), isTrue);
      expect(ProProfileStore.tokens.value, 110);

      await ProProfileStore.persistToPrefs(); // make the write deterministic

      // Simulate restart: reset runtime value, then reload from storage.
      ProProfileStore.tokens.value = 150;
      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.tokens.value, 110);
    });
  });

  group('SubscriptionStore · paid-state persistence', () {
    test('first launch falls back to trial defaults', () async {
      await SubscriptionStore.loadFromPrefs();

      expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
      expect(SubscriptionStore.isTrial, isTrue);
      expect(SubscriptionStore.activatedAt.value, isNull);
    });

    test('renew persists paid state and cycle; load restores it', () async {
      final start = DateTime(2026, 8, 1, 12);
      SubscriptionStore.renew(at: start);
      await SubscriptionStore.persistToPrefs();

      // Simulate a restart: wipe runtime state, then reload from disk.
      SubscriptionStore.isPaidSubscriber.value = false;
      SubscriptionStore.activatedAt.value = null;
      SubscriptionStore.status.value = SubscriptionStatus.expired;

      await SubscriptionStore.loadFromPrefs();

      expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
      expect(SubscriptionStore.isTrial, isFalse);
      expect(SubscriptionStore.activatedAt.value, start);
      expect(
        SubscriptionStore.expiresAt,
        start.add(const Duration(days: SubscriptionStore.durationDays)),
      );
      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
    });

    test('expire persists the expired status across restarts', () async {
      SubscriptionStore.renew();
      SubscriptionStore.expire();
      await SubscriptionStore.persistToPrefs();

      SubscriptionStore.status.value = SubscriptionStatus.active;
      await SubscriptionStore.loadFromPrefs();

      expect(SubscriptionStore.status.value, SubscriptionStatus.expired);
      expect(SubscriptionStore.isExpired, isTrue);
    });
  });
}