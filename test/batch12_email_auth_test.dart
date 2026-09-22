import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/email_otp_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/language_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/otp_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/register_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/login_screen.dart';
import 'package:allo_service_pro/shared/validators.dart';

/// Batch 12 regression tests — Email-OTP authentication (the SMS/phone
/// sign-up channel is gone):
///   • e-mail validator rules,
///   • [EmailOtpService] 6-digit lifecycle (issue · verify · consume ·
///     resend · expiry),
///   • e-mail-keyed credential registry (`UserStore.register` / `signIn`),
///   • admin ⇄ credential sync through the e-mail IDENTITY,
///   • the full RegisterScreen ➔ OtpScreen ➔ LanguageScreen widget flow.

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

/// Phone-like viewport so the whole register form (4 fields + submit button)
/// is laid out on screen — the default 800×600 test surface clips it.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Wipes the in-memory credential registry (a process-wide static) through
/// its PERSISTED key: seeding an empty registry + reloading clears it, so
/// each test starts from a virgin `_accounts` map.
Future<void> _resetRegistry() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'user_accounts_json': '[]',
  });
  await UserStore.loadFromPrefs();
  UserStore.user.value = null;
  AdminStore.pendingPros.value = const <PendingProModel>[];
}

/// Completes the REAL Email-OTP handshake for [email], exactly as `OtpScreen`
/// does on a successful entry: issue a code → verify it (which CONSUMES the
/// token) → unlock the credential record.
///
/// Registrations start locked (`isVerified = false`), so any test that expects
/// a stored password to sign in must run this first.
void _completeOtpHandshake(String email) {
  expect(EmailOtpService.trySendOtp(email), isTrue);
  final code = EmailOtpService.lastDemoCode!;
  expect(EmailOtpService.verifyOtp(email, code), isTrue);
  expect(UserStore.markEmailVerified(email: email), isTrue);
}

/// Digit-by-digit OTP entry (each box holds a single character).
Future<void> _enterCode(WidgetTester tester, String code) async {
  final fields = find.byType(TextField);
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UserStore.reset();
    EmailOtpService.reset();
    EmailOtpService.validity = const Duration(minutes: 10);
  });

  tearDown(() {
    UserStore.reset();
    EmailOtpService.validity = const Duration(minutes: 10);
    EmailOtpService.reset();
  });

  testWidgets('admin credentials bypass the user registry and route to admin',
      (tester) async {
    AdminStore.debugSetAdminCredentials(
      email: 'admin@batch12.test',
      password: 'admin-pass',
    );
    addTearDown(AdminStore.debugResetAdminCredentials);
    await tester.pumpWidget(_testApp(const LoginScreen()));
    await tester.enterText(find.byType(TextField).at(0), 'admin@batch12.test');
    await tester.enterText(find.byType(TextField).at(1), 'admin-pass');
    await tester.tap(find.text('Se connecter'));
    await tester.pump(const Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('is_logged_in'), isTrue);
    expect(prefs.getString('user_role'), 'admin');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('B12 · e-mail validator', () {
    test('accepts real-world addresses', () {
      expect(AppValidators.isValidEmail('nom@exemple.com'), isTrue);
      expect(AppValidators.isValidEmail('  nom@exemple.com  '), isTrue);
      expect(AppValidators.isValidEmail('a.b+tag@sub.domaine.tn'), isTrue);
      expect(
          AppValidators.isValidEmail('fayez_neifer-2@allo-service.tn'), isTrue);
      expect(AppValidators.isValidEmail('x@y.co'), isTrue);
    });

    test('rejects malformed addresses', () {
      const bad = [
        '',
        '   ',
        'nom',
        'nom@',
        '@exemple.com',
        'nom@exemple',
        'nom@@exemple.com',
        'nom exemple@x.com',
        'nom@exemple..com',
        'nom@exemple.c',
      ];
      for (final value in bad) {
        expect(AppValidators.isValidEmail(value), isFalse,
            reason: '« $value »');
      }
    });
  });

  group('B12 · EmailOtpService lifecycle', () {
    test('a 6-digit code verifies once, then is consumed', () {
      expect(EmailOtpService.sendOtp('Otp.User@Allo.TN'), isTrue);
      final code = EmailOtpService.lastDemoCode!;

      expect(code.length, EmailOtpService.codeLength);
      expect(int.tryParse(code), isNotNull, reason: 'digits only');
      expect(EmailOtpService.hasPendingOtp('otp.user@allo.tn'), isTrue);

      // The e-mail binding is normalized: any casing / spacing matches.
      expect(EmailOtpService.verifyOtp('  OTP.User@Allo.TN ', code), isTrue);
      expect(EmailOtpService.verifyOtp('otp.user@allo.tn', code), isFalse,
          reason: 'a code is single-use');
      expect(EmailOtpService.hasPendingOtp('otp.user@allo.tn'), isFalse);
      expect(EmailOtpService.lastDemoCode, isNull);
    });

    test('a wrong code is rejected and the entry survives for a retry', () {
      expect(EmailOtpService.sendOtp('retry@allo.tn'), isTrue);
      final code = EmailOtpService.lastDemoCode!;

      expect(EmailOtpService.verifyOtp('retry@allo.tn', '000000'), isFalse);
      expect(EmailOtpService.verifyOtp('retry@allo.tn', code), isTrue,
          reason: 'a failed attempt must not consume the pending code');
    });

    test('an expired code is rejected and dropped', () {
      // A strictly-past window: `Duration.zero` is not enough on coarse
      // clocks (both timestamps can land in the same millisecond).
      EmailOtpService.validity = const Duration(seconds: -1);
      expect(EmailOtpService.sendOtp('expired@allo.tn'), isTrue);

      expect(EmailOtpService.hasPendingOtp('expired@allo.tn'), isFalse);
      expect(
        EmailOtpService.verifyOtp(
            'expired@allo.tn', EmailOtpService.lastDemoCode!),
        isFalse,
      );
    });

    test('resend issues a fresh, immediately valid code', () {
      expect(EmailOtpService.sendOtp('resend@allo.tn'), isTrue);
      expect(EmailOtpService.resendOtp('resend@allo.tn'), isTrue);
      final code = EmailOtpService.lastDemoCode!;

      expect(EmailOtpService.verifyOtp('resend@allo.tn', code), isTrue);
    });

    test('an unknown e-mail or a malformed address never verifies', () {
      expect(EmailOtpService.verifyOtp('unknown@allo.tn', '123456'), isFalse);
      expect(EmailOtpService.hasPendingOtp('unknown@allo.tn'), isFalse);
      expect(EmailOtpService.sendOtp('not-an-email'), isFalse);
      expect(EmailOtpService.lastDemoCode, isNull,
          reason: 'nothing may be issued for an invalid address');
    });
  });

  group('B12 · e-mail-keyed credential registry', () {
    test('register keys the record by a NORMALIZED e-mail, with no phone',
        () async {
      await _resetRegistry();

      expect(
        UserStore.register(
          name: 'Fayez Neifer',
          email: '  OTP.User@Allo.TN  ',
          password: 'secret1',
        ),
        isTrue,
      );
      final u = UserStore.user.value!;
      expect(u.email, 'otp.user@allo.tn', reason: 'canonical key');
      expect(u.phone, '');
      expect(u.role, isNull, reason: 'the role is chosen after the OTP');
      expect(UserStore.isEmailVerified('otp.user@allo.tn'), isFalse,
          reason: 'a fresh credential record starts LOCKED');

      // Sign-in is refused until the OTP token has been validated.
      UserStore.user.value = null;
      expect(
        await UserStore.signIn(email: 'otp.user@allo.tn', password: 'secret1'),
        isFalse,
        reason: 'a correct password alone must not open an unverified account',
      );

      _completeOtpHandshake('otp.user@allo.tn');
      expect(UserStore.isEmailVerified('OTP.USER@allo.tn'), isTrue,
          reason: 'lookup is casing-insensitive');

      // Sign-in is case-insensitive thanks to the canonical key.
      UserStore.user.value = null;
      expect(
        await UserStore.signIn(email: 'OTP.USER@allo.tn', password: 'secret1'),
        isTrue,
      );
      expect(UserStore.user.value!.name, 'Fayez Neifer');
    });

    test('register refuses a duplicate identity, in ANY casing', () async {
      await _resetRegistry();

      expect(
        UserStore.register(
            name: 'A', email: 'dup@allo.tn', password: 'secret1'),
        isTrue,
      );
      expect(
        UserStore.register(
            name: 'B', email: '  DUP@Allo.TN ', password: 'secret2'),
        isFalse,
        reason: 'an e-mail is a single identity',
      );
      _completeOtpHandshake('dup@allo.tn');
      // The first record is untouched.
      UserStore.user.value = null;
      expect(await UserStore.signIn(email: 'dup@allo.tn', password: 'secret1'),
          isTrue);
      expect(UserStore.user.value!.name, 'A');
    });

    test('register refuses a malformed e-mail (defense-in-depth)', () async {
      await _resetRegistry();

      expect(
        UserStore.register(name: 'X', email: 'not-an-email', password: 'pass'),
        isFalse,
      );
      expect(UserStore.user.value, isNull);
    });

    test('an optional phone is still normalized when one IS provided',
        () async {
      await _resetRegistry();

      expect(
        UserStore.register(
          name: 'Nizar',
          email: 'nizar@allo.tn',
          password: 'secret1',
          phone: ' +216 98 111 222 ',
        ),
        isTrue,
      );
      expect(UserStore.user.value!.phone, '98111222');
    });

    test('wrong password is rejected, unknown e-mail too', () async {
      await _resetRegistry();
      expect(
        UserStore.register(name: 'C', email: 'c@allo.tn', password: 'secret1'),
        isTrue,
      );
      _completeOtpHandshake('c@allo.tn');
      UserStore.user.value = null;

      expect(await UserStore.signIn(email: 'c@allo.tn', password: 'nope'),
          isFalse);
      expect(
          await UserStore.signIn(email: 'ghost@allo.tn', password: 'secret1'),
          isFalse);
    });
  });

  group('B12 · admin ⇄ credential sync through the e-mail identity', () {
    test('approval reaches an EMAIL-ONLY pro after a cold restart', () async {
      await _resetRegistry();

      expect(
        UserStore.register(
            name: 'Sonia', email: 'sonia.pro@allo.tn', password: 'secret2'),
        isTrue,
      );
      // The mandatory Email-OTP gate: the credential record only unlocks once
      // the 6-digit token has been validated and consumed.
      _completeOtpHandshake('sonia.pro@allo.tn');
      // AWAITED (CodeRabbit): `setRole` persists the record + the session
      // snapshot asynchronously — reloading prefs before it completes reads a
      // half-written state.
      await UserStore.setRole(UserRole.professional);

      // The pro submits the registration form — no phone is collected by the
      // auth flow any more, the e-mail carries the identity.
      final registered = AdminStore.registerPro(PendingProModel(
        id: 'draft_email_1',
        name: 'Sonia',
        phone: '',
        email: 'Sonia.Pro@Allo.TN',
        professionFr: 'Menuisière',
        professionAr: 'نجّارة',
        submittedAt: '01/01/2026',
        status: 'pending',
      ));
      await UserStore.bindProAccount(
        proCode: registered.proCode,
        verificationStatus: ProVerification.pending,
      );

      // Admin approves → the credential record must follow the e-mail.
      await AdminStore.approvePro(registered.id);

      // Cold restart → the pro signs in with e-mail + password only.
      await Future<void>.delayed(Duration.zero);
      await UserStore.loadFromPrefs();
      expect(
          await UserStore.signIn(
              email: 'sonia.pro@allo.tn', password: 'secret2'),
          isTrue);
      final u = UserStore.user.value!;
      expect(u.verificationStatus, ProVerification.approved);
      expect(u.proCode, registered.proCode);
      expect(u.isProfessional, isTrue);
      expect(u.needsVerificationGate, isFalse, reason: 'straight to ProShell');
    });

    test('rejection also travels through the e-mail identity', () async {
      await _resetRegistry();

      expect(
        UserStore.register(
            name: 'Karim', email: 'karim@allo.tn', password: 'secret3'),
        isTrue,
      );
      _completeOtpHandshake('karim@allo.tn');
      // AWAITED (CodeRabbit): `setRole` persists asynchronously.
      await UserStore.setRole(UserRole.professional);

      final registered = AdminStore.registerPro(PendingProModel(
        id: 'draft_email_2',
        name: 'Karim',
        phone: '',
        email: 'karim@allo.tn',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '01/01/2026',
        status: 'pending',
      ));
      await UserStore.bindProAccount(
        proCode: registered.proCode,
        verificationStatus: ProVerification.pending,
      );

      await AdminStore.rejectPro(registered.id, reason: 'Preuve illisible');

      await Future<void>.delayed(Duration.zero);
      await UserStore.loadFromPrefs();
      expect(
          await UserStore.signIn(email: 'karim@allo.tn', password: 'secret3'),
          isTrue);
      expect(
          UserStore.user.value!.verificationStatus, ProVerification.rejected);
      expect(UserStore.user.value!.needsVerificationGate, isTrue);
    });

    test('an EMPTY phone never mass-matches e-mail-only accounts', () async {
      await _resetRegistry();

      expect(
        UserStore.register(
            name: 'A', email: 'a.client@allo.tn', password: 'p1'),
        isTrue,
      );
      _completeOtpHandshake('a.client@allo.tn');
      UserStore.user.value = null;
      expect(
        UserStore.register(
            name: 'B', email: 'b.client@allo.tn', password: 'p2'),
        isTrue,
      );
      _completeOtpHandshake('b.client@allo.tn');

      // Legacy phone sync with a blank / unusable number must be a no-op.
      UserStore.syncAccountVerificationByPhone('',
          status: ProVerification.approved);
      UserStore.syncAccountVerificationByPhone('+216',
          status: ProVerification.approved);

      await Future<void>.delayed(Duration.zero);
      await UserStore.loadFromPrefs();
      expect(await UserStore.signIn(email: 'a.client@allo.tn', password: 'p1'),
          isTrue);
      expect(UserStore.user.value!.verificationStatus, ProVerification.none);
      UserStore.user.value = null;
      expect(await UserStore.signIn(email: 'b.client@allo.tn', password: 'p2'),
          isTrue);
      expect(UserStore.user.value!.verificationStatus, ProVerification.none);
    });

    test('the e-mail sync touches ONLY the matching record', () async {
      await _resetRegistry();

      expect(
        UserStore.register(name: 'A', email: 'a.sync@allo.tn', password: 'p1'),
        isTrue,
      );
      _completeOtpHandshake('a.sync@allo.tn');
      UserStore.user.value = null;
      expect(
        UserStore.register(name: 'B', email: 'b.sync@allo.tn', password: 'p2'),
        isTrue,
      );
      _completeOtpHandshake('b.sync@allo.tn');

      // Spacing + casing must not matter for the identity lookup.
      UserStore.syncAccountVerificationByEmail('  A.Sync@Allo.TN ',
          status: ProVerification.rejected);

      await Future<void>.delayed(Duration.zero);
      await UserStore.loadFromPrefs();
      expect(await UserStore.signIn(email: 'a.sync@allo.tn', password: 'p1'),
          isTrue);
      expect(
          UserStore.user.value!.verificationStatus, ProVerification.rejected);
      UserStore.user.value = null;
      expect(await UserStore.signIn(email: 'b.sync@allo.tn', password: 'p2'),
          isTrue);
      expect(UserStore.user.value!.verificationStatus, ProVerification.none);
    });
  });

  group('B12 · register ➔ Email OTP ➔ language (widget flow)', () {
    testWidgets(
        'the register form has no phone field and pushes the OTP screen',
        (tester) async {
      await _resetRegistry();
      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));

      // Four fields: nom · e-mail · mot de passe · confirmation.
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Adresse e-mail'), findsOneWidget);
      expect(find.textContaining('téléphone'), findsNothing,
          reason: 'the SMS/phone channel is gone');
      expect(find.byIcon(Icons.phone_outlined), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(0), 'Fayez Neifer');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'fayez.client@allo.tn');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The OTP screen announces the e-mail that received the 6-digit code.
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.text('Vérifiez votre e-mail'), findsOneWidget);
      expect(find.textContaining('fayez.client@allo.tn'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(EmailOtpService.codeLength));

      // Entering the issued code completes sign-up → language picker.
      final code = EmailOtpService.lastDemoCode!;
      expect(code.length, EmailOtpService.codeLength);
      await _enterCode(tester, code);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Choisissez votre langue'), findsOneWidget);
      expect(find.byType(LanguageScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(UserStore.user.value!.email, 'fayez.client@allo.tn');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a wrong code never advances and never consumes the OTP',
        (tester) async {
      await _resetRegistry();
      _usePhoneViewport(tester);
      await tester
          .pumpWidget(_testApp(const OtpScreen(email: 'retry.mail@allo.tn')));
      await tester.pump();

      final code = EmailOtpService.lastDemoCode!;
      expect(code, isNot('000000'), reason: 'generated codes are 6 digits ≥ 1');

      // 6 wrong digits auto-submit → error, still on the OTP screen.
      await _enterCode(tester, '000000');
      await tester.pump();
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.textContaining('Code incorrect'), findsOneWidget);
      expect(EmailOtpService.hasPendingOtp('retry.mail@allo.tn'), isTrue,
          reason: 'a failed attempt must not consume the pending code');

      // The correct code typed afterwards still works (no resend needed).
      await _enterCode(tester, code);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Choisissez votre langue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a malformed e-mail is blocked by the form validator',
        (tester) async {
      await _resetRegistry();
      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));

      await tester.enterText(find.byType(TextFormField).at(0), 'Fayez');
      await tester.enterText(find.byType(TextFormField).at(1), 'fayez@');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      expect(find.text('Adresse e-mail invalide (ex : nom@exemple.com)'),
          findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(EmailOtpService.lastDemoCode, isNull);
    });

    testWidgets('a duplicate e-mail is refused with a visible message',
        (tester) async {
      await _resetRegistry();
      expect(
        UserStore.register(
            name: 'Fayez', email: 'taken@allo.tn', password: 'secret1'),
        isTrue,
      );
      UserStore.user.value = null;

      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Autre');
      await tester.enterText(
          find.byType(TextFormField).at(1), '  TAKEN@Allo.TN ');
      // WRONG password: no proof of ownership → no recovery, no code issued.
      await tester.enterText(find.byType(TextFormField).at(2), 'secret2');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret2');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      expect(find.text('Cet e-mail est déjà utilisé.'), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(EmailOtpService.hasPendingOtp('taken@allo.tn'), isFalse,
          reason: 'a stranger must never be handed a code for that account');
    });

    testWidgets('a VERIFIED e-mail can never be re-registered over',
        (tester) async {
      await _resetRegistry();
      expect(
        UserStore.register(
            name: 'Fayez', email: 'taken@allo.tn', password: 'secret1'),
        isTrue,
      );
      _completeOtpHandshake('taken@allo.tn');
      UserStore.user.value = null;

      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Autre');
      await tester.enterText(find.byType(TextFormField).at(1), 'taken@allo.tn');
      // Even with the RIGHT password the verified account is untouchable.
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      expect(find.text('Cet e-mail est déjà utilisé.'), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
    });

    testWidgets('an abandoned registration resumes the OTP handshake',
        (tester) async {
      await _resetRegistry();
      expect(
        UserStore.register(
            name: 'Fayez', email: 'resume@allo.tn', password: 'secret1'),
        isTrue,
      );
      // The user dropped off at the OTP step: the record stays locked.
      expect(UserStore.isEmailVerified('resume@allo.tn'), isFalse);
      UserStore.user.value = null;

      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fayez');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'resume@allo.tn');
      // Same password → ownership proven → the handshake is resumed with a
      // fresh code instead of a dead-end duplicate error.
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.text('Cet e-mail est déjà utilisé.'), findsNothing);
      expect(EmailOtpService.hasPendingOtp('resume@allo.tn'), isTrue);

      // And the resumed handshake really unlocks the existing record.
      final code = EmailOtpService.lastDemoCode!;
      await _enterCode(tester, code);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Choisissez votre langue'), findsOneWidget);
      expect(UserStore.isEmailVerified('resume@allo.tn'), isTrue);
    });
  });

  /// B13 · OTP issuance is single-flight: a code the user already holds is
  /// ADOPTED, never re-issued (re-issuing would invalidate it), and the
  /// resumable registration flow issues EXACTLY ONE code.
  group('B12 · OTP issuance is single-flight (no code ever burned)', () {
    testWidgets(
        'mounting the screen ADOPTS a still-valid code instead of burning it',
        (tester) async {
      await _resetRegistry();
      _usePhoneViewport(tester);

      // A code was issued moments before the screen opened (a duplicated
      // navigation, a restored flow, a resumed registration).
      expect(EmailOtpService.trySendOtp('adopt@allo.tn'), isTrue);
      final held = EmailOtpService.lastDemoCode!;
      final issuedBefore = EmailOtpService.debugIssuedCodeCount;

      await tester
          .pumpWidget(_testApp(const OtpScreen(email: 'adopt@allo.tn')));
      await tester.pump();

      expect(EmailOtpService.debugIssuedCodeCount, issuedBefore,
          reason: 'the mount must not issue a second code');
      // The demo banner shows the very code the user already holds.
      expect(find.textContaining(held), findsOneWidget);
      // ...and that code still verifies: nothing was invalidated.
      expect(EmailOtpService.hasPendingOtp('adopt@allo.tn'), isTrue);
      expect(EmailOtpService.verifyOtp('adopt@allo.tn', held), isTrue);
    });

    testWidgets('an explicit resend still forces a fresh code', (tester) async {
      await _resetRegistry();
      _usePhoneViewport(tester);
      await tester
          .pumpWidget(_testApp(const OtpScreen(email: 'resend.force@allo.tn')));
      await tester.pump();

      final first = EmailOtpService.lastDemoCode!;
      expect(EmailOtpService.debugIssuedCodeCount, 1);

      // Let the resend cooldown expire so the button is enabled again.
      await tester.pump(const Duration(seconds: 11));
      await tester.tap(find.text('Renvoyer le code'));
      await tester.pump();

      expect(EmailOtpService.debugIssuedCodeCount, 2,
          reason: 'resend is the one deliberate re-issue');
      // The previous code is gone; the fresh one works.
      expect(EmailOtpService.verifyOtp('resend.force@allo.tn', first), isFalse);
      expect(
        EmailOtpService.verifyOtp(
            'resend.force@allo.tn', EmailOtpService.lastDemoCode!),
        isTrue,
      );
    });

    testWidgets('the resumed registration issues exactly ONE code',
        (tester) async {
      await _resetRegistry();
      expect(
        UserStore.register(
            name: 'Fayez', email: 'resume.once@allo.tn', password: 'secret1'),
        isTrue,
      );
      expect(UserStore.isEmailVerified('resume.once@allo.tn'), isFalse);
      UserStore.user.value = null;
      expect(EmailOtpService.debugIssuedCodeCount, 0);

      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fayez');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'resume.once@allo.tn');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsOneWidget);
      // The old flow issued a code HERE and a second one on the OTP screen,
      // silently invalidating the code the user was about to read.
      expect(EmailOtpService.debugIssuedCodeCount, 1);
      expect(EmailOtpService.hasPendingOtp('resume.once@allo.tn'), isTrue);

      // ...and that single, on-screen code unlocks the record.
      final code = EmailOtpService.lastDemoCode!;
      await _enterCode(tester, code);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Choisissez votre langue'), findsOneWidget);
      expect(UserStore.isEmailVerified('resume.once@allo.tn'), isTrue);
    });

    testWidgets(
        'a re-entry into the flow adopts the live code instead of '
        'restarting the handshake', (tester) async {
      await _resetRegistry();
      expect(
        UserStore.register(
            name: 'Fayez', email: 'twice@allo.tn', password: 'secret1'),
        isTrue,
      );
      UserStore.user.value = null;
      _usePhoneViewport(tester);
      await tester.pumpWidget(_testApp(const RegisterScreen()));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fayez');
      await tester.enterText(find.byType(TextFormField).at(1), 'twice@allo.tn');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final firstCode = EmailOtpService.lastDemoCode!;
      expect(EmailOtpService.debugIssuedCodeCount, 1);

      // The user backs out and submits the SAME credentials again (the classic
      // back-then-forward path). The handshake must resume on the SAME live
      // code — not burn it and hand out a second one.
      final otpContext = tester.state(find.byType(OtpScreen)).context;
      Navigator.of(otpContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.ensureVisible(find.text('Continuer'));
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(EmailOtpService.debugIssuedCodeCount, 1,
          reason: 'a still-valid code is adopted, never re-issued');
      expect(EmailOtpService.lastDemoCode, firstCode);

      // ...and the adopted code completes the handshake.
      await _enterCode(tester, firstCode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Choisissez votre langue'), findsOneWidget);
      expect(UserStore.isEmailVerified('twice@allo.tn'), isTrue);
    });
  });

  group('B12 · release-mode demo bypass is impossible', () {
    tearDown(() {
      // Restore the default seam so subsequent tests behave normally.
      EmailOtpService.debugDemoOverride = null;
    });

    test('opting OUT of demo mode makes lastDemoCode throw', () {
      // Simulate a release build: the test seam forces demo delivery OFF.
      EmailOtpService.debugDemoOverride = false;

      expect(EmailOtpService.demoMode, isFalse);
      expect(() => EmailOtpService.lastDemoCode, throwsA(isA<StateError>()),
          reason: 'the in-app OTP reader must never fire outside debug');

      // Codes issued in release are still tracked for verifyOtp (the
      // verification path is real), but they can never be READ back.
      expect(EmailOtpService.trySendOtp('release@allo.tn'), isFalse);
      expect(EmailOtpService.verifyOtp('release@allo.tn', '000000'), isFalse);
    });

    test('a release build never allows lastDemoCode to be read', () {
      EmailOtpService.debugDemoOverride = false;
      expect(() => EmailOtpService.lastDemoCode, throwsA(isA<StateError>()));
    });

    test('forcing demo ON through the seam is accepted in debug', () {
      // In a debug/test build the seam may explicitly enable or disable the
      // demo channel — the ONLY intended use of the override seam.
      EmailOtpService.debugDemoOverride = true;
      expect(EmailOtpService.demoMode, isTrue);
      EmailOtpService.debugDemoOverride = false;
      expect(EmailOtpService.demoMode, isFalse);
    });
  });
}
