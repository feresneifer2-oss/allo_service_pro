import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/features/home/application/governorate_filter_store.dart';
import 'package:allo_service_pro/features/home/presentation/widgets/sub_service_sheet.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/home/presentation/widgets/professionals_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Batch 8 regression tests: home interactions & sheet localization.

/// Delegates that officially support 'ar' — silences the
/// "locale not supported by all delegates" warning in tests.
const _testDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  appLocale.value = const Locale('fr');

  setUp(() {
    GovernorateFilterStore.clear();
    appLocale.value = const Locale('fr');
  });

  test('governorate filter store notifies listeners on set/clear', () {
    var notified = 0;
    void listener() => notified++;
    GovernorateFilterStore.governorateAr.addListener(listener);
    GovernorateFilterStore.governorateFr.addListener(listener);

    GovernorateFilterStore.set('أريانة', 'Ariana');
    expect(GovernorateFilterStore.governorateAr.value, 'أريانة');
    expect(GovernorateFilterStore.governorateFr.value, 'Ariana');

    GovernorateFilterStore.clear();
    expect(GovernorateFilterStore.governorateAr.value, isNull);
    expect(GovernorateFilterStore.governorateFr.value, isNull);
    expect(notified, 4); // 2 notifiers × 2 mutations
  });

  test('city→governorate resolution works in both languages', () {
    expect(
      TunisianLocations.getGovernorateFrFromCityFr('Ariana Ville'),
      'Ariana',
    );
    expect(
      TunisianLocations.getGovernorateArFromCityAr('أريانة المدينة'),
      'أريانة',
    );
  });

  testWidgets('professionals sheet renders FR city label in FR locale',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    // Open the sheet AFTER the build phase completes — opening it inside a
    // builder triggers "setState during build" on the overlay.
    showProfessionalsSheet(captured, 'Peintre', 'رسام');
    await tester.pumpAndSettle();

    final painter = ProfessionalsRepository.all.firstWhere(
      (p) => p.professionFr.toLowerCase() == 'peintre',
    );
    expect(find.text(painter.cityFr), findsOneWidget);
  });

  testWidgets('professionals sheet renders AR city label in AR locale',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('fr')],
      localizationsDelegates: _testDelegates,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    showProfessionalsSheet(captured, 'Peintre', 'رسام');
    await tester.pumpAndSettle();

    final painter = ProfessionalsRepository.all.firstWhere(
      (p) => p.professionFr.toLowerCase() == 'peintre',
    );
    expect(find.text(painter.city), findsOneWidget);
  });

  testWidgets('sub-service sheet uses Arabic titles when provided',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('fr')],
      localizationsDelegates: _testDelegates,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    showSubServiceSheet(
      captured,
      'Peinture',
      ['Interieur', 'Exterieur'],
      serviceNameAr: 'الصباغة',
      subServicesAr: ['داخلي', 'خارجي'],
    );
    await tester.pumpAndSettle();

    // Title and sub-service labels follow the Arabic data.
    expect(find.text('الصباغة'), findsOneWidget);
    expect(find.text('داخلي'), findsOneWidget);
    expect(find.text('خارجي'), findsOneWidget);
    expect(find.text('Peinture'), findsNothing);
  });

  testWidgets('sub-service sheet falls back gracefully without AR data',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    // Legacy call shape: FR label shown, no crash.
    showSubServiceSheet(captured, 'Peinture', ['Interieur']);
    await tester.pumpAndSettle();

    expect(find.text('Peinture'), findsOneWidget);
    expect(find.text('Interieur'), findsOneWidget);
  });
}
