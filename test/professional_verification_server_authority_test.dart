import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/features/auth/presentation/login_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/otp_screen.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_dashboard_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// PENDING-APPROVAL ROUTING (server authority):
///
///  A. Existing professional + `is_verified = false` + OTP login
///     → VerificationGateScreen (pending state).
///  B. Existing professional + `is_verified = true` + OTP login
///     → normal ProShell dashboard.
///  C. Stale LOCAL approved + server `is_verified = false`
///     → pending (the SERVER wins, on the session AND on the credential
///     record so the next sign-in cannot re-upgrade it).
///  D. Unknown server state fails closed, and a null/unknown role inside
///     ProShell never grants the pro dashboard.
///  E. Client OTP login keeps its existing routing (ClientShell).

const _proEmail = 'pending.pro@allo.test';
const _clientEmail = 'plain.client@allo.test';

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

    // Same channel stubs as the e2e harness: the client home (ClientShell)
    // probes geolocation / connectivity on mount.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geocodingChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            _connectivityChannel, (call) async => <String>['wifi']);

    UserStore.reset();
    RequestStore.reset();
    ChatStore.reset();
    NotificationStore.clear();
    await SubscriptionStore.reset();
    await ProProfileStore.reset();
    AdminStore.pendingPros.value = [];
    ProfileRepository.debugIsVerifiedOverride = null;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geocodingChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    appLocale.value = previousLocale ?? const Locale('fr');
    ProfileRepository.debugIsVerifiedOverride = null;
    SupabaseAuthService.debugResetOverrides();
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

  /// LIVE-shaped Supabase seams: the OTP architecture under test is the REAL
  /// one (configured client → sendOtp → verifyOtp → bindRemoteIdentity →
  /// server-authority sync → route); only the network hops are faked.
  void installAuthSeams() {
    SupabaseAuthService.debugConfiguredOverride = true;
    SupabaseAuthService.debugSendOtpOverride = (String email,
            {required bool shouldCreateUser}) async =>
        OtpSendOutcome.sent;
    SupabaseAuthService.debugVerifyOtpOverride =
        (String email, String token) async => true;
    addTearDown(SupabaseAuthService.debugResetOverrides);
  }

  /// Seeds an EXISTING professional exactly like the registration flow left
  /// it: credential record (role + proCode + verification status + unlocked
  /// OTP flag) and a matching registry entry.
  Future<void> seedPro({
    required String email,
    required ProVerification localStatus,
    String registryStatus = 'pending',
  }) async {
    expect(
      UserStore.register(
        name: 'Pending Pro',
        email: email,
        password: 'secret1',
      ),
      isTrue,
    );
    await UserStore.setRole(UserRole.professional);
    final entry = AdminStore.registerPro(PendingProModel(
      id: 'pp_$email',
      name: 'Pending Pro',
      phone: '22110009',
      email: email,
      professionFr: 'Plombier',
      professionAr: 'سبّاك',
      submittedAt: '01/01/2026',
      status: 'pending',
    ));
    if (registryStatus != 'pending') {
      AdminStore.pendingPros.value = [
        for (final p in AdminStore.pendingPros.value)
          if (p.id != entry.id) p else p.copyWith(status: registryStatus),
      ];
    }
    await UserStore.bindProAccount(
      proCode: entry.proCode,
      verificationStatus: localStatus,
      proofPath: 'pro_media/doc.jpg',
    );
    // The OTP handshake already completed during registration.
    expect(UserStore.markEmailVerified(email: email), isTrue);
    await UserStore.set(
      name: 'Pending Pro',
      phone: '22110009',
      email: email,
      role: UserRole.professional,
      proCode: entry.proCode,
      proofPath: 'pro_media/doc.jpg',
      verificationStatus: localStatus,
    );
  }

  /// Drives the REAL login journey: LoginScreen → OTP dispatch → OtpScreen →
  /// 6-digit entry → verify → bind → server-authority sync → routing.
  Future<void> loginViaOtp(WidgetTester tester, String email) async {
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OtpScreen), findsOneWidget);

    const code = '123456';
    final fields = find.descendant(
      of: find.byType(OtpScreen),
      matching: find.byType(TextField),
    );
    for (var i = 0; i < code.length; i++) {
      await tester.enterText(fields.at(i), code[i]);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(OtpScreen).evaluate().isNotEmpty) {
      await tester.tap(find.text('Vérifier'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    // Drain the post-verify chain (bind → server sync → pushReplacement).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  group('server-authoritative pro verification on OTP login', () {
    testWidgets(
        'A · existing pro + is_verified=false + OTP login → pending gate',
        (tester) async {
      installAuthSeams();
      await seedPro(email: _proEmail, localStatus: ProVerification.pending);
      UserStore.user.value = null; // fresh login on this device
      ProfileRepository.debugIsVerifiedOverride = () async => false;
      addTearDown(() => ProfileRepository.debugIsVerifiedOverride = null);

      await loginViaOtp(tester, _proEmail);

      expect(UserStore.user.value?.email, _proEmail);
      expect(UserStore.user.value?.role, UserRole.professional);
      expect(UserStore.user.value!.needsVerificationGate, isTrue);
      expect(find.byType(VerificationGateScreen), findsOneWidget);
      expect(find.byType(ProDashboardScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'B · existing pro + is_verified=true + OTP login → normal dashboard',
        (tester) async {
      installAuthSeams();
      await seedPro(email: _proEmail, localStatus: ProVerification.pending);
      UserStore.user.value = null; // fresh login on this device
      ProfileRepository.debugIsVerifiedOverride = () async => true;
      addTearDown(() => ProfileRepository.debugIsVerifiedOverride = null);

      await loginViaOtp(tester, _proEmail);

      expect(UserStore.user.value?.role, UserRole.professional);
      expect(
        UserStore.user.value!.verificationStatus,
        ProVerification.approved,
      );
      expect(UserStore.user.value!.needsVerificationGate, isFalse);
      expect(find.byType(VerificationGateScreen), findsNothing);
      expect(find.byType(ProDashboardScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
        'C · stale local approved + server is_verified=false → pending '
        '(server wins, session AND record)', () async {
      SupabaseAuthService.debugConfiguredOverride = true;
      addTearDown(SupabaseAuthService.debugResetOverrides);
      ProfileRepository.debugIsVerifiedOverride = () async => false;
      addTearDown(() => ProfileRepository.debugIsVerifiedOverride = null);
      await seedPro(
        email: _proEmail,
        localStatus: ProVerification.approved,
        registryStatus: 'approved', // even the local registry claims approved
      );
      expect(
          UserStore.user.value!.verificationStatus, ProVerification.approved);

      await AdminStore.syncSessionStoresForCurrentUser();

      expect(UserStore.user.value!.verificationStatus, ProVerification.pending);
      expect(UserStore.user.value!.needsVerificationGate, isTrue);

      // The credential record mirrored the downgrade — a plain re-login can
      // never re-upgrade from stale local state while the server says false.
      expect(
        await UserStore.signIn(email: _proEmail, password: 'secret1'),
        isTrue,
      );
      expect(UserStore.user.value!.needsVerificationGate, isTrue);
    });

    testWidgets(
        'D · unknown server state fails closed; null role never opens the '
        'pro dashboard', (tester) async {
      // D1 — unresolved server answer + stale approved ⇒ fail closed.
      SupabaseAuthService.debugConfiguredOverride = true;
      addTearDown(SupabaseAuthService.debugResetOverrides);
      ProfileRepository.debugIsVerifiedOverride = () async => null;
      addTearDown(() => ProfileRepository.debugIsVerifiedOverride = null);
      await seedPro(
        email: _proEmail,
        localStatus: ProVerification.approved,
        registryStatus: 'approved',
      );
      await AdminStore.syncSessionStoresForCurrentUser();
      expect(
        UserStore.user.value!.verificationStatus,
        isNot(ProVerification.approved),
      );
      expect(UserStore.user.value!.needsVerificationGate, isTrue);

      // D2 — a null/unknown role inside ProShell must hit the gate, never
      // the dashboard.
      UserStore.user.value = const UserModel(
        id: 'unknown-role-session',
        name: '',
        phone: '',
      );
      await tester.pumpWidget(app(const ProShell()));
      await tester.pump();
      expect(find.byType(VerificationGateScreen), findsOneWidget);
      expect(find.byType(ProDashboardScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('E · client OTP login behavior is unchanged', (tester) async {
      installAuthSeams();
      // The server answer must be irrelevant for a client identity.
      ProfileRepository.debugIsVerifiedOverride = () async => false;
      addTearDown(() => ProfileRepository.debugIsVerifiedOverride = null);
      expect(
        UserStore.register(
          name: 'Client User',
          email: _clientEmail,
          password: 'secret1',
        ),
        isTrue,
      );
      await UserStore.setRole(UserRole.client);
      UserStore.user.value = null; // fresh login on this device

      await loginViaOtp(tester, _clientEmail);

      expect(UserStore.user.value?.email, _clientEmail);
      expect(UserStore.user.value?.role, UserRole.client);
      expect(UserStore.user.value!.needsVerificationGate, isFalse);
      expect(find.byType(ClientShell), findsOneWidget);
      expect(find.byType(VerificationGateScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
