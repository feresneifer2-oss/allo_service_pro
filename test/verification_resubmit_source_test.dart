import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// PHASE 10 · the rejected professional chooses WHERE the proof comes from.
///
/// The re-submission flow used to hard-code the CAMERA, so a professional
/// whose document was rejected — on a device without a usable camera, or who
/// already had the corrected file in the gallery — could not re-submit at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Locale? previousLocale;

  const rejected = UserModel(
    id: 'uid-rejected-1',
    name: 'Sami',
    phone: '22110033',
    role: UserRole.professional,
    proCode: 'PRO-04242',
    verificationStatus: ProVerification.rejected,
    rejectionReason: 'Photo illisible',
  );

  setUp(() {
    previousLocale = appLocale.value;
    appLocale.value = const Locale('fr');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UserStore.user.value = rejected;
    AdminStore.pendingPros.value = [];
    SupabaseAuthService.debugConfiguredOverride = null;
    ProProfileStore.tokens.value = 150;
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.status.value = SubscriptionStatus.inactive;
    SubscriptionStore.activatedAt.value = null;
  });

  tearDown(() {
    appLocale.value = previousLocale ?? const Locale('fr');
    SupabaseAuthService.debugResetOverrides();
    UserStore.user.value = null;
  });

  Widget app(Widget home) => MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      );

  testWidgets('the rejected gate offers camera AND gallery', (tester) async {
    await tester.pumpWidget(app(const VerificationGateScreen()));
    await tester.pump();

    // Precondition: this is the rejected branch (the re-upload action exists).
    expect(find.text('Compte refusé'), findsOneWidget);

    await tester.tap(find.text('Re-téléverser la preuve'));
    await tester.pumpAndSettle();

    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);
  });

  testWidgets('choosing the gallery closes the sheet and keeps the gate alive',
      (tester) async {
    await tester.pumpWidget(app(const VerificationGateScreen()));
    await tester.pump();

    await tester.tap(find.text('Re-téléverser la preuve'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choisir dans la galerie'));
    await tester.pump(); // start the sheet's exit animation
    await tester.pumpAndSettle(); // let it finish

    // The sheet is gone and the gate is still mounted — the gallery option is
    // wired into the SAME flow as the camera (which then no-ops gracefully
    // because a widget test owns no image source). Nothing throws and the user
    // is never stranded on a dismissed sheet.
    expect(find.text('Choisir dans la galerie'), findsNothing);
    expect(find.text('Prendre une photo'), findsNothing);
    expect(find.byType(VerificationGateScreen), findsOneWidget);
    expect(find.text('Re-téléverser la preuve'), findsOneWidget);
  });
}
