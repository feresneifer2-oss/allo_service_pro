import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/email_otp_service.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/language_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/login_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/otp_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/register_screen.dart';

import 'support/fake_admin_auth.dart';

/// PHASE 3T — Email OTP is the REAL authentication mechanism for normal
/// users (client + professional):
///   • LoginScreen dispatches `signInWithOtp(shouldCreateUser: false)`;
///   • the existing OtpScreen verifies + binds the remote identity;
///   • a configured Supabase client is a valid RELEASE delivery channel;
///   • 429 (rate limit) is classified apart from "e-mail not configured";
///   • the local/debug fallback still works when Supabase is unconfigured.

/// Delegates that officially support 'ar' — silences the
/// "locale not supported by all delegates" warning in tests.
const _testDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _testApp(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: _testDelegates,
      home: home,
    );

/// Phone-like viewport so the auth forms are fully laid out.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Wipes the in-memory credential registry (a process-wide static) through
/// its PERSISTED key, so each test starts from a virgin `_accounts` map.
Future<void> _resetRegistry() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'user_accounts_json': '[]',
  });
  await SharedPreferences.getInstance();
  await UserStore.loadFromPrefs();
  UserStore.user.value = null;
  AdminStore.pendingPros.value = const <PendingProModel>[];
}

/// Completes the REAL Email-OTP handshake for [email], exactly as `OtpScreen`
/// does on a successful entry: issue a code → verify it (which CONSUMES the
/// token) → unlock the credential record.
void _completeOtpHandshake(String email) {
  expect(EmailOtpService.trySendOtp(email), isTrue);
  final code = EmailOtpService.lastDemoCode!;
  expect(EmailOtpService.verifyOtp(email, code), isTrue);
  expect(UserStore.markEmailVerified(email: email), isTrue);
}

/// Lets the session BINDING fully settle: `UserStore`'s write queue runs on
/// the ROOT zone (deliberately — see `UserStore._writeZone`), so its
/// continuations are real event-loop work that a fake-async `pump()` cannot
/// advance on its own. Alternating a real async gap with pumped frames lets
/// the queue drain AND the resulting navigation (pushReplacement /
/// pushAndRemoveUntil) build, so the post-routing assertions observe the
/// final widget tree instead of a half-settled one.
Future<void> _drainSessionBinding(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Digit-by-digit OTP entry, scoped to the [OtpScreen] (a LoginScreen pushed
/// underneath keeps its own TextFields in the tree).
Future<void> _enterCode(WidgetTester tester, String code) async {
  final fields = find.descendant(
    of: find.byType(OtpScreen),
    matching: find.byType(TextField),
  );
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
  await tester.pump();
}

/// A simulated LIVE Supabase client (Phase 3T seams): captures every
/// dispatch/verification and lets a test drive the provider's answer.
class _LiveAuth {
  _LiveAuth({
    this.sendOutcome = OtpSendOutcome.sent,
    this.verifyResult = true,
  });

  OtpSendOutcome sendOutcome;
  bool verifyResult;

  /// When non-null, every dispatch THROWS this (transport-layer failure).
  Object? sendError;

  final sends = <({String email, bool shouldCreateUser})>[];
  final verifies = <({String email, String token})>[];
  final passwordSignIns = <({String email, String password})>[];
  final setPasswords = <String>[];

  void install() {
    SupabaseAuthService.debugConfiguredOverride = true;
    SupabaseAuthService.debugSendOtpOverride =
        (String email, {required bool shouldCreateUser}) async {
      sends.add((email: email, shouldCreateUser: shouldCreateUser));
      final error = sendError;
      if (error != null) throw error;
      return sendOutcome;
    };
    SupabaseAuthService.debugVerifyOtpOverride =
        (String email, String token) async {
      verifies.add((email: email, token: token));
      return verifyResult;
    };
    SupabaseAuthService.debugSignInWithPasswordOverride =
        (String email, String password) async {
      passwordSignIns.add((email: email, password: password));
      // Default: refuse, so pre-B3P tests keep the OTP-fallback behavior;
      // B3P tests override this seam per-test after calling install().
      return false;
    };
    SupabaseAuthService.debugSetPasswordOverride = (String password) async {
      setPasswords.add(password);
      return true;
    };
    addTearDown(SupabaseAuthService.debugResetOverrides);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B3T · 429 classification (pure)', () {
    test('HTTP 429 maps to rateLimited', () {
      expect(
        SupabaseAuthService.classifySendFailure(
          statusCode: '429',
          message: 'Email rate limit exceeded',
        ),
        OtpSendOutcome.rateLimited,
      );
    });

    test('a throttle-marked message without a status still maps to rateLimited',
        () {
      expect(
        SupabaseAuthService.classifySendFailure(
          statusCode: null,
          message:
              'For security purposes, you can only request this after 47 seconds.',
        ),
        OtpSendOutcome.rateLimited,
      );
    });

    test('non-throttle refusals stay plain refusals', () {
      expect(
        SupabaseAuthService.classifySendFailure(
          statusCode: '400',
          message: 'Signups not allowed for otp',
        ),
        OtpSendOutcome.refused,
      );
      expect(
        SupabaseAuthService.classifySendFailure(
          statusCode: '500',
          message: 'Database error saving new user',
        ),
        OtpSendOutcome.refused,
      );
      expect(
        SupabaseAuthService.classifySendFailure(
          statusCode: null,
          message: 'Invalid email address',
        ),
        OtpSendOutcome.refused,
      );
    });
  });

  group('B3T · release delivery gate', () {
    tearDown(() {
      EmailOtpService.debugDemoOverride = null;
      SupabaseAuthService.debugResetOverrides();
    });

    test('a configured Supabase client IS a valid delivery channel', () {
      // Simulate an optimized build: the in-app demo channel is compiled out.
      EmailOtpService.debugDemoOverride = false;

      SupabaseAuthService.debugConfiguredOverride = false;
      expect(EmailOtpService.hasDeliveryChannel, isFalse);
      expect(
        () => EmailOtpService.requireDeliveryChannel(),
        throwsA(isA<EmailOtpUnavailableException>()),
      );

      // …but a wired Supabase client serves the code server-side, so the
      // release gate must PASS.
      SupabaseAuthService.debugConfiguredOverride = true;
      expect(EmailOtpService.hasDeliveryChannel, isTrue);
      expect(() => EmailOtpService.requireDeliveryChannel(), returnsNormally);
    });

    testWidgets(
        'the register form reaches the OTP screen in a release-like '
        'build served by Supabase', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      EmailOtpService.debugDemoOverride = false;
      addTearDown(() => EmailOtpService.debugDemoOverride = null);

      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Release User');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'release.user@allo.tn');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Inscription indisponible'), findsNothing,
          reason: 'a configured Supabase client is a REAL channel');
      expect(find.byType(OtpScreen), findsOneWidget);
      // Registration semantics keep shouldCreateUser: true.
      expect(seams.sends.single.shouldCreateUser, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('B3T · normal login dispatches Supabase OTP', () {
    testWidgets(
        'login sends shouldCreateUser:false and opens the existing OTP screen '
        '(resend keeps the login semantics)', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(
          find.byType(TextField).at(0), 'login.user@allo.tn');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('code de connexion'), findsOneWidget);
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(seams.sends, isNotEmpty);
      expect(seams.sends.first.email, 'login.user@allo.tn');
      expect(seams.sends.first.shouldCreateUser, isFalse,
          reason: 'signing in must never provision a new account');
      // The screen's own initial issue mirrors the login intent.
      expect(seams.sends.last.shouldCreateUser, isFalse);

      // RESEND (after the cooldown) keeps the same semantics.
      await tester.pump(const Duration(seconds: 11));
      await tester.tap(find.text('Renvoyer le code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(seams.sends.length, 3);
      expect(seams.sends.every((s) => s.shouldCreateUser == false), isTrue);
      expect(find.textContaining('nouveau code'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a rate-limited login stays put with a retry-later message',
        (tester) async {
      await _resetRegistry();
      _LiveAuth(sendOutcome: OtpSendOutcome.rateLimited).install();
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'limit@allo.tn');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsNothing);
      expect(
        find.text('Trop de tentatives. Réessayez dans quelques minutes.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'an unknown remote address is refused generically and never signs in '
        'locally', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      // A fully usable LOCAL credential record exists for this very address —
      // proving the configured build never consults it on the OTP path.
      expect(
        UserStore.register(
            name: 'Local Pass',
            email: 'unknown.remote@allo.tn',
            password: 'secret1'),
        isTrue,
      );
      _completeOtpHandshake('unknown.remote@allo.tn');
      UserStore.user.value = null;
      seams.sendOutcome = OtpSendOutcome.refused;
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(
          find.byType(TextField).at(0), 'unknown.remote@allo.tn');
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsNothing);
      expect(
          find.textContaining("Impossible d'envoyer un code"), findsOneWidget);
      expect(seams.sends.single.shouldCreateUser, isFalse);
      expect(UserStore.user.value, isNull,
          reason: 'a configured build never falls back to local credentials');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a transport failure keeps the connectivity guidance',
        (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      seams.sendError = Exception('socket closed');
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'down@allo.tn');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsNothing);
      expect(find.textContaining("Échec d'envoi"), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a password still reaches ONLY the server-side admin gate',
        (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      AdminAuth.configure(FakeAdminAuthRepository(
        enrolled: true,
        uid: 'uid-admin-3t',
        expectedEmail: 'admin@phase3t.test',
        expectedPassword: 'admin-pass',
      ));
      addTearDown(AdminAuth.resetToDefault);
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(
          find.byType(TextField).at(0), 'admin@phase3t.test');
      await tester.enterText(find.byType(TextField).at(1), 'admin-pass');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin_uid'), 'uid-admin-3t');
      expect(prefs.getString('user_role'), 'admin');
      expect(seams.sends, isEmpty,
          reason: 'the admin path never dispatches an OTP');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a non-admin password falls through to the OTP dispatch, never to a '
        'local sign-in', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      expect(
        UserStore.register(
            name: 'Same Pass', email: 'same.pass@allo.tn', password: 'secret1'),
        isTrue,
      );
      _completeOtpHandshake('same.pass@allo.tn');
      UserStore.user.value = null;
      AdminAuth.configure(FakeAdminAuthRepository(
        enrolled: false,
        expectedEmail: 'someone.else@phase3t.test',
        expectedPassword: 'other-pass',
      ));
      addTearDown(AdminAuth.resetToDefault);
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'same.pass@allo.tn');
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsOneWidget);
      // TWO dispatches are expected: the login's own dispatch and the
      // OtpScreen's initial issue — BOTH must keep the login semantics.
      expect(seams.sends, isNotEmpty);
      expect(seams.sends.every((s) => s.shouldCreateUser == false), isTrue);
      expect(UserStore.user.value, isNull,
          reason: 'the local registry must not authenticate while Supabase '
              'is configured');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('B3T · OTP verification binds the remote identity', () {
    testWidgets(
        'a successful live verification binds the session and routes a '
        'role-less identity to onboarding', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const OtpScreen(
        email: 'fresh.login@allo.tn',
        createUserOnSend: false,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(seams.sends.single.shouldCreateUser, isFalse);

      await _enterCode(tester, '246810');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _drainSessionBinding(tester);

      expect(seams.verifies.single.email, 'fresh.login@allo.tn');
      expect(seams.verifies.single.token, '246810');
      expect(UserStore.user.value?.email, 'fresh.login@allo.tn');
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
    });

    testWidgets('a failed live verification keeps the screen and binds nothing',
        (tester) async {
      await _resetRegistry();
      _LiveAuth(verifyResult: false).install();
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const OtpScreen(
        email: 'reject.login@allo.tn',
        createUserOnSend: false,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await _enterCode(tester, '000000');
      await tester.pump();

      expect(find.textContaining('Code incorrect'), findsOneWidget);
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(UserStore.user.value, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
        'a stale local identity never overrides the newly authenticated '
        'remote identity', () async {
      await _resetRegistry();
      // Identity A: a fully verified PRO session already on this device.
      expect(
        UserStore.register(
          name: 'Ancien Pro',
          email: 'old.pro@allo.tn',
          password: 'secret1',
          phone: '12345678',
        ),
        isTrue,
      );
      _completeOtpHandshake('old.pro@allo.tn');
      expect(
          await UserStore.signIn(email: 'old.pro@allo.tn', password: 'secret1'),
          isTrue);
      await UserStore.setRole(UserRole.professional);
      expect(UserStore.user.value?.isProfessional, isTrue);

      // Identity B authenticates remotely (fresh login OTP): the binding
      // reconciles to B — A's role / phone / dossier must never leak across.
      expect(await UserStore.bindRemoteIdentity(email: 'new.client@allo.tn'),
          isTrue);
      final u = UserStore.user.value!;
      expect(u.email, 'new.client@allo.tn');
      expect(u.role, isNull);
      expect(u.phone, '');
      expect(u.proCode, isNull);
      // A's credential record survives untouched — only the SESSION switched.
      expect(UserStore.hasCredentialRecord(email: 'old.pro@allo.tn'), isTrue);
      expect(UserStore.isEmailVerified('old.pro@allo.tn'), isTrue);
    });
  });

  group('B3T · local/debug fallback (Supabase genuinely unconfigured)', () {
    testWidgets('the legacy local sign-in path is preserved', (tester) async {
      await _resetRegistry();
      expect(SupabaseAuthService.isConfigured, isFalse,
          reason: 'no live client in tests and no seam installed');
      expect(
        UserStore.register(
            name: 'Client Local',
            email: 'local.client@allo.tn',
            password: 'secret1'),
        isTrue,
      );
      _completeOtpHandshake('local.client@allo.tn');
      UserStore.user.value = null;
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      // A password-less submit keeps the legacy refusal (no OTP dispatch).
      await tester.enterText(
          find.byType(TextField).at(0), 'local.client@allo.tn');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      expect(find.text('Veuillez remplir tous les champs.'), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      // Let the snackbar dismiss so it cannot mask the submit button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));

      // With the credential the LOCAL registry authenticates and the app
      // routes (role-less → onboarding) — exactly as before Phase 3T.
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _drainSessionBinding(tester);

      expect(UserStore.user.value?.email, 'local.client@allo.tn');
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('B3U · "the code is demanded only once"', () {
    test('the "already completed" marker is normalized and fail-closed',
        () async {
      await _resetRegistry();
      expect(await EmailOtpService.hasVerifiedBefore(' Mark@Allo.TN '), isFalse,
          reason: 'a virgin device has never completed the handshake');
      await EmailOtpService.markVerifiedForNextLogin('mark@allo.tn');
      // Normalization: the marker is keyed on the trimmed lowercase address,
      // exactly like the codes themselves.
      expect(await EmailOtpService.hasVerifiedBefore('MARK@allo.TN '), isTrue);
      expect(await EmailOtpService.hasVerifiedBefore('someone.else@allo.tn'),
          isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('otp_verified_mark@allo.tn'), isTrue);
    });

    testWidgets(
        'a verified OTP leaves the marker behind, so the NEXT login of that '
        'identity is never challenged again', (tester) async {
      await _resetRegistry();
      _LiveAuth().install();
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const OtpScreen(
        email: 'once.mark@allo.tn',
        createUserOnSend: false,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _enterCode(tester, '246810');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _drainSessionBinding(tester);

      // The flow left the screen (role-less → onboarding)…
      expect(find.byType(OtpScreen), findsNothing);
      expect(find.byType(LanguageScreen), findsOneWidget);
      // …and the "OTP completed" marker is on disk — written BEFORE the
      // navigation, on every channel.
      expect(
          await EmailOtpService.hasVerifiedBefore('once.mark@allo.tn'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('otp_verified_once.mark@allo.tn'), isTrue);
    });

    testWidgets(
        'a marked identity with NO server-side proof still receives the code '
        '(the shortcut can only shorten a flow, never bypass the gate)',
        (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      // The identity already completed the handshake on this device before…
      await EmailOtpService.markVerifiedForNextLogin('again@allo.tn');
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'again@allo.tn');
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // …but this client holds no persisted session and the provider accepts
      // no password, so the code remains the fallback.
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(seams.sends, isNotEmpty);
      expect(seams.sends.every((s) => s.shouldCreateUser == false), isTrue);
      expect(UserStore.user.value, isNull,
          reason: 'no local authentication while Supabase is configured');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('B3P · Facebook-style password auth', () {
    testWidgets(
        'setPassword persists the registration password after a successful '
        'OTP handshake', (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      final savedPasswords = <String>[];
      SupabaseAuthService.debugSetPasswordOverride = (String password) async {
        savedPasswords.add(password);
        return true;
      };
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const OtpScreen(
        email: 'new.pass@allo.tn',
        createUserOnSend: true,
        pendingPassword: 'secret1',
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(seams.sends.single.shouldCreateUser, isTrue);

      await _enterCode(tester, '246810');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _drainSessionBinding(tester);

      expect(savedPasswords, const ['secret1']);
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a typed password signs in first — no OTP is dispatched',
        (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      final signIns = <({String email, String password})>[];
      SupabaseAuthService.debugSignInWithPasswordOverride =
          (String email, String password) async {
        signIns.add((email: email, password: password));
        return true;
      };
      AdminAuth.configure(FakeAdminAuthRepository(
        enrolled: false,
        expectedEmail: 'someone.else@phase3p.test',
        expectedPassword: 'other-pass',
      ));
      addTearDown(AdminAuth.resetToDefault);
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(
          find.byType(TextField).at(0), 'returning.pass@allo.tn');
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _drainSessionBinding(tester);

      expect(signIns.single.email, 'returning.pass@allo.tn');
      expect(signIns.single.password, 'secret1');
      expect(seams.sends, isEmpty,
          reason: 'a successful password sign-in must not dispatch an OTP');
      expect(UserStore.user.value?.email, 'returning.pass@allo.tn');
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a rejected password falls back to the OTP dispatch',
        (tester) async {
      await _resetRegistry();
      final seams = _LiveAuth()..install();
      SupabaseAuthService.debugSignInWithPasswordOverride =
          (String email, String password) async => false;
      AdminAuth.configure(FakeAdminAuthRepository(
        enrolled: false,
        expectedEmail: 'someone.else@phase3p.test',
        expectedPassword: 'other-pass',
      ));
      addTearDown(AdminAuth.resetToDefault);
      _usePhoneViewport(tester);

      await tester.pumpWidget(_testApp(const LoginScreen()));
      await tester.enterText(
          find.byType(TextField).at(0), 'wrong.pass@allo.tn');
      await tester.enterText(find.byType(TextField).at(1), 'bad-password');
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(seams.sends, isNotEmpty);
      expect(seams.sends.every((s) => s.shouldCreateUser == false), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
