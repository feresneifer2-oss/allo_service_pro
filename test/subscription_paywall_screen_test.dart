import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/pro_dashboard/presentation/subscription_paywall_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

Widget _host(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('token-exhaustion paywall shows the FR lock copy',
      (tester) async {
    await tester.pumpWidget(_host(
      const SubscriptionPaywallScreen(reason: PaywallReason.tokensExhausted),
      const Locale('fr'),
    ));

    expect(
        find.text('Compte suspendu : Solde de tokens épuisé'), findsOneWidget);
    expect(find.textContaining('consommé tous vos tokens'), findsOneWidget);
    expect(find.text("Activer l'abonnement illimité (15 DT / mois)"),
        findsOneWidget);
  });

  testWidgets('token-exhaustion paywall shows the AR lock copy',
      (tester) async {
    appLocale.value = const Locale('ar');
    addTearDown(() => appLocale.value = const Locale('fr'));

    await tester.pumpWidget(_host(
      const SubscriptionPaywallScreen(reason: PaywallReason.tokensExhausted),
      const Locale('ar'),
    ));

    expect(find.text('تم إيقاف حسابك مؤقتاً لنفاد الرصيد'), findsOneWidget);
    expect(find.textContaining('استهلكت جميع التوكنز'), findsOneWidget);
    expect(
        find.text('تفعيل الاشتراك اللامحدود (15 د.ت / شهر)'), findsOneWidget);
  });

  testWidgets('expired-subscription paywall keeps its existing FR copy',
      (tester) async {
    await tester.pumpWidget(_host(
      const SubscriptionPaywallScreen(
          reason: PaywallReason.subscriptionExpired),
      const Locale('fr'),
    ));

    expect(find.text('Abonnement expiré'), findsOneWidget);
    expect(find.text('Contacter sur WhatsApp'), findsOneWidget);
  });
}
