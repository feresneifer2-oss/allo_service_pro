import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/account_type/presentation/account_type_screen.dart';
import 'package:allo_service_pro/main.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/email_otp_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/language_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/login_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/otp_screen.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/splash/presentation/splash_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_profile_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/logout_tile.dart';

const clientName = 'Lifecycle Client';
const clientEmail = 'lifecycle.client@allo.test';
const clientPhone = '22110001';
const clientPassword = 'client-pass';

const professionalName = 'Lifecycle Professional';
const professionalEmail = 'lifecycle.pro@allo.test';
const professionalPhone = '22110002';
const professionalPassword = 'pro-pass';

// TEST-ONLY PLACEHOLDERS (CodeRabbit): the harness used to seed the admin
// gate with a REAL-looking personal e-mail/password pair — test fixtures must
// never resemble genuine credentials (leaks into logs/screenshots would look
// like a compromised account). These are synthetic and only valid inside this
// file's process.
const adminEmail = 'admin@test.com';
const adminPassword = 'admin-test-pass';

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
const _geocodingChannel = MethodChannel('flutter.baseflow.com/geocoding');
const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Locale? previousLocale;

  setUp(() async {
    previousLocale = appLocale.value;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    appLocale.value = const Locale('fr');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _geolocatorChannel,
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _geocodingChannel,
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _connectivityChannel,
      (call) async => <String>['wifi'],
    );

    UserStore.reset();
    RequestStore.reset();
    ChatStore.reset();
    NotificationStore.clear();
    await SubscriptionStore.reset();
    await ProProfileStore.reset();
    AdminStore.pendingPros.value = [];
    AdminStore.debugSetAdminCredentials(
      email: adminEmail,
      password: adminPassword,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geocodingChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    AdminStore.debugResetAdminCredentials();
    UserStore.reset();
    RequestStore.reset();
    ChatStore.reset();
    NotificationStore.clear();
    appLocale.value = previousLocale ?? const Locale('fr');
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // BOUNDED PUMP (CodeRabbit): the splash waits a REAL 2 seconds before
    // routing, and the app shells host live countdown timers that keep
    // scheduling frames forever — the old `pumpAndSettle()` therefore hit a
    // pending-frame timeout on a fully healthy tree. Advance strictly bounded
    // virtual time instead: 3s lets the splash reach its destination, and the
    // shells settle deterministically without quiescence.
    // COLD-REMOUNT (CodeRabbit): `pumpWidget(const AlloServiceProApp())` is a
    // CONST widget, so re-pumping it REUSES the existing element tree — the
    // Navigator keeps whatever route stack the previous step left behind and
    // the splash NEVER re-runs. Every later step that expected the welcome
    // screen (the login journey) then failed with 'Inscription not found'.
    // Tear the tree down first so each pumpApp is a genuine cold boot.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const AlloServiceProApp());
    // BOUNDED-DRAIN for the splash route (CodeRabbit): the splash awaits a real
    // `Future.delayed(2s)` and then PUSHES its destination, whose first frame
    // needs yet another pump. A fixed 3s+0.5s pair could therefore land while
    // the splash was still mounted (the welcome screen never got a frame) and
    // every downstream `find.text('Inscription')` failed. Poll until the splash
    // is gone, with a hard bound so live timers can never hang the harness.
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0;
        i < 10 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> enterOtp(WidgetTester tester, String email) async {
    final code = EmailOtpService.demoCodeFor(email) ?? '123456';
    final fields = find.byType(TextField);
    for (var i = 0; i < code.length && i < fields.evaluate().length; i++) {
      await tester.enterText(fields.at(i), code[i]);
      await tester.pump();
    }
  }

  Future<void> registerAndSelectRole(
    WidgetTester tester, {
    required String name,
    required String email,
    required String phone,
    required String password,
    required bool isProfessional,
  }) async {
    expect(find.text('Inscription'), findsOneWidget);
    await tester.tap(find.text('Inscription'));
    await tester.pump(const Duration(seconds: 1));
    // FIELD-GUARD (CodeRabbit): assert the register form actually landed (4
    // fields) before indexing into it — the pre-fix `.at(0)` on an EMPTY
    // finder threw RangeError(index): "no indices are valid: 0" whenever the
    // push hadn't completed in the test's virtual-time budget. Bounded extra
    // pumps (not pumpAndSettle: live timers never quiesce) give the push
    // animation bounded time to finish.
    var formFields = find.byType(TextFormField);
    for (var i = 0; i < 6 && formFields.evaluate().length < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
      formFields = find.byType(TextFormField);
    }
    expect(formFields, findsNWidgets(4),
        reason: 'RegisterScreen must expose name/e-mail/password/confirm');
    await tester.enterText(formFields.at(0), name);
    await tester.enterText(formFields.at(1), email);
    await tester.enterText(formFields.at(2), password);
    await tester.enterText(formFields.at(3), password);
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(milliseconds: 500));
    // OTP-ARRIVAL WAIT (CodeRabbit): registration goes through
    // `SupabaseAuthService.sendOtp` FIRST (live client), falling back to the
    // local demo channel. That path is async, so the OtpScreen push can land
    // later than one pump — poll boundedly instead of asserting immediately.
    var otpFinder = find.byType(OtpScreen);
    for (var i = 0; i < 10 && otpFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
      otpFinder = find.byType(OtpScreen);
    }
    expect(otpFinder, findsOneWidget,
        reason: 'OtpScreen must appear after registration submit');
    await enterOtp(tester, email);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LanguageScreen), findsOneWidget);
    await tester.tap(find.text('Français'));
    // PUMP-BETWEEN-TAPS (CodeRabbit): without a frame here the `Continuer`
    // button below is still built with `_selected == null` (disabled), so the
    // tap silently hits a disabled button and the journey never reaches the
    // role-selection screen. Bounded pumps only (live timers never quiesce),
    // and the tap site has NO SingleChildScrollView on this screen — it is a
    // fixed Column + Spacer, so tap it directly.
    await tester.pump(const Duration(milliseconds: 500));
    final langContinue = find.descendant(
      of: find.byType(LanguageScreen),
      matching: find.byType(ElevatedButton),
    );
    expect(langContinue, findsOneWidget);
    await tester.tap(langContinue);
    // BOUNDED WAIT for the role screen (CodeRabbit): `setLocale` persists asynchronously
    // and the pushReplacement animation needs its own frames — 10 bounded pumps
    // reach it deterministically, then the assertion tells us where we landed.
    var accountType = find.byType(AccountTypeScreen);
    for (var i = 0; i < 10 && accountType.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
      accountType = find.byType(AccountTypeScreen);
    }
    expect(accountType, findsOneWidget,
        reason: 'role selection must open after the language step');
    final roleCard = find.text(isProfessional ? 'Professionnel' : 'Client');
    expect(roleCard, findsOneWidget);
    await tester.tap(roleCard);
    await tester.pump(const Duration(milliseconds: 500));
    // SCROLL-INTO-VIEW (CodeRabbit): the account-type screen is a full-bleed
    // column on the bare 800x600 test surface, so the bottom 'Continuer'
    // sits BELOW the fold (y > 800) — the pre-fix tap threw a hit-test
    // warning, never fired, and the session stayed roleless (the line-210
    // `UserRole.client` failure). Scroll first, then tap.
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Continuer'),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Continuer'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  // NOTE ON `completeProRegistration`: the pro wizard's document step is
  // backed by the NATIVE image_picker (camera/gallery), which cannot run in a
  // VM widget test. The pro actor is therefore registered through the store
  // seam below (the same payload the wizard submits), keeping the picker seam
  // explicit for a platform integration test.

  Future<void> login(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    // LOGIN-ENTRY ROBUSTNESS (CodeRabbit): `find.text('Se connecter')` can
    // match MULTIPLE widgets at once (welcome OutlinedButton + login
    // ElevatedButton in the pushed route, 'تسجيل الدخول' in AR locale) and
    // crash `.tap()` with an ambiguous-finder error. Scope every text query
    // to the LoginScreen subtree, and navigate there FIRST when needed:
    //   • on LoginScreen already → fill the form;
    //   • on welcome (Inscription present) → push LoginScreen, then fill;
    //   • on an authenticated shell → sign out to welcome, then push+fill.
    Future<void> fillLoginForm() async {
      final scope = find.byType(LoginScreen);
      await tester.enterText(
          find.descendant(of: scope, matching: find.byType(TextField)).at(0),
          email);
      await tester.enterText(
          find.descendant(of: scope, matching: find.byType(TextField)).at(1),
          password);
      await tester.tap(
          find.descendant(of: scope, matching: find.byType(ElevatedButton)));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    if (find.byType(LoginScreen).evaluate().isNotEmpty) {
      await fillLoginForm();
      return;
    }
    if (find.text('Inscription').evaluate().isNotEmpty) {
      await tester.tap(find.text('Se connecter'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await fillLoginForm();
      return;
    }
    if (UserStore.user.value != null) {
      await UserStore.signOutAndReset();
      await pumpApp(tester);
    }
    expect(find.text('Inscription'), findsOneWidget);
    await tester.tap(find.text('Se connecter'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await fillLoginForm();
  }

  Future<void> logout(WidgetTester tester) async {
    // REAL LOGOUT TILE (CodeRabbit): the old helper searched a bare icon and
    // SILENTLY returned when it was missing — the session then stayed alive and
    // the assertion failed far from the cause. It now drives the actual
    // [LogoutTile] widget. NOTE ON LAZY BUILDING: `ProProfileScreen` renders a
    // `ListView`, so the tile is NOT in the element tree until it is scrolled
    // into view (`find.byType(LogoutTile)` legitimately returns 0 before that);
    // [scrollUntilVisible] scrolls the profile list until the tile is BUILT.
    await tester.scrollUntilVisible(
      find.byType(LogoutTile),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ProProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final tile = find.byType(LogoutTile);
    expect(tile, findsOneWidget,
        reason: 'the signed-in profile screen must expose the logout tile');
    await tester.tap(tile, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    final confirm = find.widgetWithText(ElevatedButton, 'Déconnexion');
    expect(confirm, findsOneWidget,
        reason: 'the confirm dialog must open before signing out');
    await tester.tap(confirm);
    for (var i = 0; i < 12 && UserStore.user.value != null; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('full app lifecycle preserves shared marketplace data',
      (tester) async {
    // Phone-like viewport (the same harness trick batch12 uses): the default
    // 800×600 test surface clips the auth screens, so the role-selection
    // card the UI journey must tap can be pushed out of the hit-testable
    // area.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // ── Journey 1 · REAL UI registration for the client ───────────────────
    // EXECUTED (CodeRabbit): the reusable UI helpers used to be asserted as
    // mere `isA<Function>()` (compiled but never run). The client now walks
    // the actual Inscription → OTP → language → role screens.
    await pumpApp(tester);
    await registerAndSelectRole(
      tester,
      name: clientName,
      email: clientEmail,
      phone: clientPhone,
      password: clientPassword,
      isProfessional: false,
    );
    expect(UserStore.user.value?.email, clientEmail);
    expect(UserStore.user.value?.role, UserRole.client);

    // Detach the client session before arranging the professional (the
    // binding below keys on the CURRENT session's e-mail).
    await UserStore.signOutAndReset();

    // ── Arrange the professional through the store seam (see the picker
    // note above) — the same payload the wizard submits.
    expect(
        UserStore.register(
          name: professionalName,
          email: professionalEmail,
          password: professionalPassword,
          phone: professionalPhone,
        ),
        isTrue);
    expect(UserStore.markEmailVerified(email: professionalEmail), isTrue);
    await UserStore.setRole(UserRole.professional);
    await UserStore.bindProAccount(
      proCode: 'PRO-E2E-0001',
      verificationStatus: ProVerification.approved,
    );
    AdminStore.pendingPros.value = [
      const PendingProModel(
        id: 'e2e-pro-1',
        name: professionalName,
        phone: professionalPhone,
        email: professionalEmail,
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '18/09/2026',
        proCode: 'PRO-E2E-0001',
        status: 'approved',
        tokens: 150,
      ),
    ];

    RequestStore.add(ServiceRequest(
      id: 'e2e-request-1',
      serviceTitleFr: 'Plomberie',
      serviceTitleAr: 'سباكة',
      professionalId: 'PRO-E2E-0001',
      professionalName: professionalName,
      customerName: clientName,
      customerId: clientEmail,
      dateTime: DateTime.now().add(const Duration(days: 1)),
      address: 'Tunis',
      message: 'Need urgent fixing',
      createdAt: DateTime.now(),
    ));
    expect(
        await RequestStore.updateStatus(
            'e2e-request-1', RequestStatus.accepted),
        isTrue);
    ChatStore.send(
      requestId: 'e2e-request-1',
      senderId: 'pro',
      senderName: professionalName,
      text: 'I am on my way.',
      isCustomer: false,
    );

    // The app shell can restore the approved session and render its real UI.
    await UserStore.set(
      name: professionalName,
      phone: professionalPhone,
      email: professionalEmail,
      role: UserRole.professional,
      proCode: 'PRO-E2E-0001',
      verificationStatus: ProVerification.approved,
    );
    expect(UserStore.user.value?.email, professionalEmail);
    expect(UserStore.user.value?.role, UserRole.professional);
    // SESSION-SHELL SHORT-CIRCUIT (CodeRabbit): the previous revision called
    // pumpApp + tap('Profil') here, but pumpApp mounts the splash which — with
    // a LIVE in-memory session — routes straight past welcome into a shell
    // that renders 'Profil' in MULTIPLE branches (client bottom bar, pro
    // profile tiles). Both the ambiguous `find.text('Profil').last` tap and
    // the subsequent `login()` welcome-flow assumption then crashed. The
    // pro-session UI is already covered by the 'Demandes' assertion above, so
    // sign out here and let the REAL journeys (login → logout) run from a
    // clean, deterministic welcome state.
    await pumpApp(tester);
    expect(find.text('Demandes'), findsWidgets);
    expect(RequestStore.byId('e2e-request-1')!.status, RequestStatus.accepted);
    expect(
        ChatStore.forRequest('e2e-request-1').single.text, 'I am on my way.');

    // EXECUTED JOURNEYS (CodeRabbit): the reusable UI helpers used to be
    // asserted as mere `isA<Function>()` (compiled but never run). The pro
    // session above lets the REAL UI journeys execute here: an in-app LOGIN
    // (credentials typed into the actual login screen) followed by the REAL
    // LOGOUT tile flow — including the confirm dialog.
    await UserStore.signOutAndReset();
    await pumpApp(tester);
    await login(
      tester,
      email: professionalEmail,
      password: professionalPassword,
    );
    expect(UserStore.user.value?.email, professionalEmail);
    // Navigate to the Profil tab (the logout tile lives on the profile
    // screen, not on the requests dashboard).
    await tester.tap(find.text('Profil').last);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await logout(tester);
    expect(UserStore.user.value, isNull);

    // CUSTOMER-SCOPED DATA (CodeRabbit): orders and chat rooms belong to the
    // signed-in identity and are cleared by the sign-out — a leftover order
    // history / conversation must never leak to the next user of this device.
    expect(RequestStore.byId('e2e-request-1'), isNull);
    expect(ChatStore.forRequest('e2e-request-1'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
