import 'package:flutter_test/flutter_test.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';

void main() {
  group('Tunisian governorates localization (24 total)', () {
    // THE FULL LIST (order per the API audit of tunisian_locations.dart).
    const expectedPairs = <MapEntry<String, String>>[
      MapEntry('Tunis', 'تونس'),
      MapEntry('Ariana', 'أريانة'),
      MapEntry('Ben Arous', 'بن عروس'),
      MapEntry('Manouba', 'منوبة'),
      MapEntry('Nabeul', 'نابل'),
      MapEntry('Zaghouan', 'زغوان'),
      MapEntry('Bizerte', 'بنزرت'),
      MapEntry('Béja', 'باجة'),
      MapEntry('Jendouba', 'جندوبة'),
      MapEntry('Le Kef', 'الكاف'),
      MapEntry('Siliana', 'سليانة'),
      MapEntry('Sousse', 'سوسة'),
      MapEntry('Monastir', 'المنستير'),
      MapEntry('Mahdia', 'المهدية'),
      MapEntry('Sfax', 'صفاقس'),
      MapEntry('Kairouan', 'القيروان'),
      MapEntry('Kasserine', 'القصرين'),
      MapEntry('Sidi Bouzid', 'سيدي بوزيد'),
      MapEntry('Gabès', 'قابس'),
      MapEntry('Médenine', 'مدنين'),
      MapEntry('Tataouine', 'تطاوين'),
      MapEntry('Gafsa', 'قفصة'),
      MapEntry('Tozeur', 'توزر'),
      MapEntry('Kebili', 'قبلي'),
    ];

    test('there are exactly 24 governorates in the data', () {
      expect(TunisianLocations.locations.length, 24);
    });

    test('getLocationByFr works for ALL 24 French names', () {
      for (final pair in expectedPairs) {
        final loc = TunisianLocations.getLocationByFr(pair.key);
        expect(
          loc,
          isNotNull,
          reason: 'getLocationByFr("${pair.key}") returned null',
        );
        expect(loc!.governorateFr, pair.key);
        expect(loc.governorateAr, pair.value);
      }
    });

    test('getLocationByAr works for ALL 24 Arabic names', () {
      for (final pair in expectedPairs) {
        final loc = TunisianLocations.getLocationByAr(pair.value);
        expect(
          loc,
          isNotNull,
          reason: 'getLocationByAr("${pair.value}") returned null',
        );
        expect(loc!.governorateAr, pair.value);
        expect(loc.governorateFr, pair.key);
      }
    });

    test('AR → FR conversion works for ALL 24 (via getLocationByAr)', () {
      for (final pair in expectedPairs) {
        final converted =
            TunisianLocations.getLocationByAr(pair.value)?.governorateFr;
        expect(
          converted,
          pair.key,
          reason: 'AR "${pair.value}" should convert to FR "${pair.key}", '
              'but got "$converted"',
        );
      }
    });

    test('FR → AR conversion works for ALL 24 (via getLocationByFr)', () {
      for (final pair in expectedPairs) {
        final converted =
            TunisianLocations.getLocationByFr(pair.key)?.governorateAr;
        expect(
          converted,
          pair.value,
          reason: 'FR "${pair.key}" should convert to AR "${pair.value}", '
              'but got "$converted"',
        );
      }
    });

    test('getGovernoratesFr() returns exactly 24 French names', () {
      final list = TunisianLocations.getGovernoratesFr();
      expect(list.length, 24);
      for (final pair in expectedPairs) {
        expect(list, contains(pair.key));
      }
    });

    test('getGovernoratesAr() returns exactly 24 Arabic names', () {
      final list = TunisianLocations.getGovernoratesAr();
      expect(list.length, 24);
      for (final pair in expectedPairs) {
        expect(list, contains(pair.value));
      }
    });

    test('getLocationByKeyOrAr handles AR input for all 24', () {
      for (final pair in expectedPairs) {
        final loc = TunisianLocations.getLocationByKeyOrAr(pair.value);
        expect(
          loc,
          isNotNull,
          reason: 'getLocationByKeyOrAr("${pair.value}") returned null',
        );
        expect(loc!.governorateFr, pair.key);
      }
    });

    test('getLocationByKeyOrFr handles FR input for all 24', () {
      for (final pair in expectedPairs) {
        final loc = TunisianLocations.getLocationByKeyOrFr(pair.key);
        expect(
          loc,
          isNotNull,
          reason: 'getLocationByKeyOrFr("${pair.key}") returned null',
        );
        expect(loc!.governorateAr, pair.value);
      }
    });
  });
}
