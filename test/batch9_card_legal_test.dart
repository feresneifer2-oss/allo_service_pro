import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allo_service_pro/core/constants/legal_texts.dart';
import 'package:allo_service_pro/shared/widgets/professional_card.dart';

/// Batch 9 regression tests: card price-badge localization & legal alignment.
void main() {
  const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  Widget host(Locale locale, Widget child) => MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('fr')],
        localizationsDelegates: delegates,
        home: Scaffold(body: Center(child: child)),
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required Locale locale,
    required int priceFrom,
    required String pricingType,
  }) async {
    await tester.pumpWidget(host(
      locale,
      ProfessionalCard(
        name: 'Ahmed',
        profession: 'Plombier',
        priceFrom: priceFrom,
        pricingType: pricingType,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('fixed price badge renders per locale', (tester) async {
    await pumpCard(tester,
        locale: const Locale('fr'), priceFrom: 80, pricingType: 'fixed');
    expect(find.text('dès 80 DT'), findsOneWidget);

    await pumpCard(tester,
        locale: const Locale('ar'), priceFrom: 80, pricingType: 'fixed');
    expect(find.text('ابتداءً من 80 د.ت'), findsOneWidget);
  });

  testWidgets('hourly price badge appends per-hour unit per locale',
      (tester) async {
    await pumpCard(tester,
        locale: const Locale('fr'), priceFrom: 25, pricingType: 'hourly');
    expect(find.text('dès 25 DT/h'), findsOneWidget);

    await pumpCard(tester,
        locale: const Locale('ar'), priceFrom: 25, pricingType: 'hourly');
    expect(find.text('ابتداءً من 25 د.ت/ساعة'), findsOneWidget);
  });

  test('privacy AR fixes the Collected-Data title typo', () {
    expect(LegalTexts.privacyAr, contains('البيانات المجموعة'));
    expect(LegalTexts.privacyAr, isNot(contains('البيانات الجمعة')));
  });

  test('privacy deletion terms match the actual UI options (logout wipe)', () {
    // The UI has NO remote account-deletion action — only profile editing
    // and logout-with-local-wipe. The legal text must not promise deletion.
    expect(LegalTexts.privacyAr, isNot(contains('حذف حسابك')));
    expect(LegalTexts.privacyAr, contains('تسجيل الخروج'));
    expect(LegalTexts.privacyAr, contains('تعديل بياناتك'));

    expect(LegalTexts.privacyFr, isNot(contains('supprimer votre compte')));
    expect(LegalTexts.privacyFr, contains('Déconnexion'));
    expect(LegalTexts.privacyFr, contains('modifier vos données'));
  });
}
