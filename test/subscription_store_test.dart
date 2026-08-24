import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

void main() {
  setUp(() {
    // Fresh, well-known state for every test.
    SubscriptionStore.status.value = SubscriptionStatus.active;
    SubscriptionStore.activatedAt.value = null;
  });

  group('SubscriptionStore · defaults', () {
    test('starts active with no recorded cycle', () {
      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
      expect(SubscriptionStore.activatedAt.value, isNull);
      expect(SubscriptionStore.expiresAt, isNull);
      expect(SubscriptionStore.isExpired, isFalse);
      expect(SubscriptionStore.cycleElapsed, isFalse);
    });

    test('one cycle lasts exactly 30 days', () {
      expect(SubscriptionStore.durationDays, 30);

      final start = DateTime(2026, 8, 1, 12);
      expect(
        start.add(const Duration(days: SubscriptionStore.durationDays)),
        DateTime(2026, 8, 31, 12),
      );
    });
  });

  group('SubscriptionStore · 30-day expiration', () {
    test('renew stamps the cycle start and derives expiresAt (+30 days)',
        () {
      final start = DateTime(2026, 8, 1, 12);
      SubscriptionStore.renew(at: start);

      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
      expect(SubscriptionStore.activatedAt.value, start);
      expect(SubscriptionStore.expiresAt, DateTime(2026, 8, 31, 12));
    });

    test('cycle still runs just before the 30-day mark', () {
      final start = DateTime(2026, 8, 1, 12);
      SubscriptionStore.renew(at: start);

      final almostUp = start.add(const Duration(
          days: 29, hours: 23, minutes: 59, seconds: 59));
      expect(SubscriptionStore.isCycleOver(start, almostUp), isFalse);
    });

    test('cycle is over right after the 30-day mark', () {
      final start = DateTime(2026, 8, 1, 12);
      SubscriptionStore.renew(at: start);

      final justPast = start
          .add(const Duration(days: 30))
          .add(const Duration(minutes: 1));
      expect(SubscriptionStore.isCycleOver(start, justPast), isTrue);
    });

    test('cycleElapsed distinguishes an old activation from a fresh one',
        () {
      SubscriptionStore.renew(
          at: DateTime.now().subtract(const Duration(days: 31)));
      expect(SubscriptionStore.cycleElapsed, isTrue);

      SubscriptionStore.renew(); // fresh cycle starting now
      expect(SubscriptionStore.cycleElapsed, isFalse);
      expect(SubscriptionStore.activatedAt.value, isNotNull);
    });
  });

  group('SubscriptionStore · manual methods & paywall trigger', () {
    test('expire() flips the paywall trigger state on', () {
      SubscriptionStore.renew();
      expect(SubscriptionStore.isExpired, isFalse);

      SubscriptionStore.expire();
      expect(SubscriptionStore.status.value, SubscriptionStatus.expired);
      // pro_shell / paywall gate on exactly this state:
      expect(SubscriptionStore.isExpired, isTrue);
    });

    test('renew() reactivates after an expiration', () {
      SubscriptionStore.expire();
      expect(SubscriptionStore.isExpired, isTrue);

      SubscriptionStore.renew();
      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
      expect(SubscriptionStore.isExpired, isFalse);
    });
  });
}