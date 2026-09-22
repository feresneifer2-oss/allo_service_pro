import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('B3 · reset() clears EVERY mutable field — zero data leaks', () async {
    // Logged-in pro leaves private data everywhere.
    ProProfileStore.tokens.value = 3;
    ProProfileStore.isAvailable.value = false;
    ProProfileStore.completedServices.value = 99;
    ProProfileStore.rating.value = 3.1;
    ProProfileStore.selectedSpecialties.value = [
      const CatalogType(id: 'plumber', fr: 'Plombier', ar: 'سباك'),
    ];
    ProProfileStore.pricingType.value = 'hourly';
    ProProfileStore.priceFrom.value = 999;
    ProProfileStore.workImages.value = ['assets/pro_img.png'];
    ProProfileStore.punctualityRate.value = 0.11;
    ProProfileStore.acceptanceRate.value = 0.22;
    ProProfileStore.responseTimeMin.value = 5;
    ProProfileStore.hasBrandedUniform.value = false;
    ProProfileStore.serviceZones.value = ['Sfax'];
    ProProfileStore.zones = ['Sfax'];
    ProProfileStore.professionFr = 'Plombier';
    ProProfileStore.professionAr = 'سبّاك';
    ProProfileStore.tokensConsumed.value = true;

    await ProProfileStore.reset();

    // Every mutable field is back to its factory default.
    expect(ProProfileStore.tokens.value, 150);
    expect(ProProfileStore.isAvailable.value, isTrue);
    expect(ProProfileStore.completedServices.value, 127);
    expect(ProProfileStore.rating.value, 4.9);
    expect(ProProfileStore.selectedSpecialties.value, isEmpty);
    expect(ProProfileStore.pricingType.value, 'fixed');
    expect(ProProfileStore.priceFrom.value, 50);
    expect(ProProfileStore.workImages.value, isEmpty);
    expect(ProProfileStore.punctualityRate.value, 0.98);
    expect(ProProfileStore.acceptanceRate.value, 0.96);
    expect(ProProfileStore.responseTimeMin.value, 15);
    expect(ProProfileStore.hasBrandedUniform.value, isTrue);
    expect(ProProfileStore.serviceZones.value, ['Ariana', 'Tunis']);
    expect(ProProfileStore.zones, ['Ariana', 'Tunis']);
    expect(ProProfileStore.professionFr, isNull);
    expect(ProProfileStore.professionAr, isNull);
    expect(ProProfileStore.tokensConsumed.value, isFalse);
  });

  test('B3 · only REAL usage marks tokensConsumed; manual balance does not',
      () async {
    await ProProfileStore.reset();
    SubscriptionStore.isPaidSubscriber.value = false;
    ProProfileStore.tokens.value = 3;
    ProProfileStore.tokensConsumed.value = false;

    // Manual balance write (admin/dev) must NOT mark the account as used.
    ProProfileStore.tokens.value = 0;
    expect(ProProfileStore.tokensConsumed.value, isFalse);

    // Actual order consumption (deductTokens) marks it as used.
    ProProfileStore.tokens.value = 1;
    expect(await ProProfileStore.deductTokens(1), isTrue);
    expect(ProProfileStore.tokens.value, 0);
    expect(ProProfileStore.tokensConsumed.value, isTrue);

    // A paid subscriber spends tokens freely without marking "consumed"
    // (unlimited mode short-circuits before the flag).
    ProProfileStore.tokensConsumed.value = false;
    ProProfileStore.tokens.value = 0;
    SubscriptionStore.isPaidSubscriber.value = true;
    expect(await ProProfileStore.deductTokens(5), isTrue);
    expect(ProProfileStore.tokensConsumed.value, isFalse);
  });
}
