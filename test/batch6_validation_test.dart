import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/validators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Batch 6 · phone validation', () {
    test('rejects Tunisian numbers starting with 6 or 8', () {
      expect(AppValidators.isValidTunisianPhone('61234567'), isFalse);
      expect(AppValidators.isValidTunisianPhone('81234567'), isFalse);
      expect(AppValidators.isValidTunisianPhone('98765432'), isTrue);
      expect(AppValidators.isValidTunisianPhone('22 123 456'), isTrue);
      expect(AppValidators.isValidTunisianPhone('31234567'), isTrue);
      expect(AppValidators.isValidTunisianPhone('71234567'), isTrue);
    });
  });

  group('Batch 6 · unique governorate keys', () {
    test('all 24 governorates have unique non-empty keys', () {
      final keys = TunisianLocations.locations.map((l) => l.key).toList();
      expect(keys.length, 24);
      expect(keys.any((k) => k.trim().isEmpty), isFalse);
      expect(keys.toSet().length, keys.length, reason: 'keys must be unique');
    });

    test('key lookup is collision-free against city names', () {
      // The city "Tunis Ville" must never resolve another governorate when
      // the unique slug is used.
      expect(
          TunisianLocations.getLocationByKey('tunis')!.governorateFr, 'Tunis');
      expect(
        TunisianLocations.getLocationByKeyOrFr('Tunis')!.key,
        'tunis',
        reason: 'governorate label beats identical city names',
      );
      // A city name alone falls back to its own governorate.
      expect(
        TunisianLocations.matchGovernorate('La Marsa', 'la marsa')!
            .governorateFr,
        'Tunis',
      );
    });
  });

  group('Batch 6 · governorate sanitization in UserStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      UserStore.user.value = null;
    });

    test('blank governorate values are normalized to null (never stored)',
        () async {
      UserStore.set(
        name: 'Ali',
        phone: '22123456',
        role: UserRole.client,
        governorateAr: '  ',
        governorateFr: '',
      );
      final u = UserStore.user.value!;
      expect(u.governorateAr, isNull, reason: 'whitespace-only → null');
      expect(u.governorateFr, isNull, reason: 'empty string → null');

      await UserStore.loadFromPrefs();
      final restored = UserStore.user.value!;
      expect(restored.governorateAr, isNull);
      expect(restored.governorateFr, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_governorate_ar'), isFalse,
          reason: 'blank key must be stripped, not saved as empty');
      expect(prefs.containsKey('user_governorate_fr'), isFalse);
    });

    test('valid governorate survives a full persist/reload round-trip',
        () async {
      UserStore.set(
        name: 'Sami',
        phone: '98111222',
        role: UserRole.client,
        governorateAr: 'تونس',
        governorateFr: 'Tunis',
      );
      // set() fires persistence without awaiting — await it explicitly so
      // the reload below cannot race the write.
      await UserStore.persistToPrefs();
      await UserStore.loadFromPrefs();
      final u = UserStore.user.value!;
      expect(u.governorateFr, 'Tunis');
      expect(u.governorateAr, 'تونس');
    });
  });
}
