import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/home/presentation/widgets/sub_service_sheet.dart';

/// Batch 11 (CodeRabbit polish) regression tests:
/// 1. tokensConsumed persists alongside the token balance.
/// 2. tokensConsumed is updated BEFORE the balance notifier fires.
/// 3. Sub-service Arabic mapping never goes out of bounds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProProfileStore.reset();
  });

  group('ProProfileStore tokensConsumed persistence', () {
    test('deductTokens flips tokensConsumed BEFORE the balance updates',
        () async {
      final observed = <bool>[];
      void listener() => observed.add(ProProfileStore.tokensConsumed.value);
      ProProfileStore.tokens.addListener(listener);

      // AWAITED (CodeRabbit): `deductTokens` is async (it persists through
      // the SharedPreferences write chain).
      expect(await ProProfileStore.deductTokens(10), isTrue);

      // Every notification fired by the balance change must already observe
      // the fresh consumed flag (never a stale false).
      expect(observed, everyElement(isTrue));
      expect(ProProfileStore.tokensConsumed.value, isTrue);
      ProProfileStore.tokens.removeListener(listener);
    });

    test('persistToPrefs saves the consumed flag; loadFromPrefs restores it',
        () async {
      await ProProfileStore.deductTokens(5);
      await ProProfileStore.persistToPrefs();

      // Simulate a fresh session: wipe memory, restore from prefs.
      ProProfileStore.tokensConsumed.value = false;
      ProProfileStore.tokens.value = 150;
      await ProProfileStore.loadFromPrefs();

      expect(ProProfileStore.tokensConsumed.value, isTrue);
      expect(ProProfileStore.tokens.value, 145);
    });

    test('reset clears the persisted consumed flag', () async {
      await ProProfileStore.deductTokens(5);
      await ProProfileStore.persistToPrefs();
      await ProProfileStore.reset();
      await ProProfileStore.loadFromPrefs();
      expect(ProProfileStore.tokensConsumed.value, isFalse);
      expect(ProProfileStore.tokens.value, 150);
    });
  });

  group('SubServiceSheet Arabic index safety', () {
    test('shorter Arabic list falls back to the French name without throwing',
        () {
      const fr = ['Devis', 'Plomberie', 'Électricité'];
      const shortAr = ['تقدير', 'سباكة'];
      // Previously: subServicesAr?[indexOf(name)] threw a RangeError for the
      // 3rd entry (index 2 out of a 2-length Arabic list).
      expect(
        () => resolveArSubServiceName(fr, shortAr, 2),
        returnsNormally,
      );
      expect(resolveArSubServiceName(fr, shortAr, 2), 'Électricité');
      expect(resolveArSubServiceName(fr, shortAr, 1), 'سباكة');
    });

    test('missing Arabic list falls back to French names', () {
      const fr = ['Devis', 'Plomberie'];
      expect(resolveArSubServiceName(fr, null, 0), 'Devis');
      expect(resolveArSubServiceName(fr, null, 1), 'Plomberie');
    });
  });
}
