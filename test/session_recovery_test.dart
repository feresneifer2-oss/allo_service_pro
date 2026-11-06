import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/features/auth/presentation/welcome_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// PHASE 9 · ACCOUNT-LIFECYCLE RECOVERY — R2 · R4 · R5 · R6 · R7.
///
/// Each test pins ONE recovery rule of the Uber-style account loop:
///   R4 · a session that ends must return to the entry screen, never park the
///        user on an action-less spinner;
///   R5 · the verification gate reconciles with the server on its own;
///   R6 · a stale local marker without a cloud session routes to the guest;
///   R2 · a malformed server row never downgrades a confirmed approval;
///   R7 · an absent `professionals` row is a DEFINITE answer, not a retry loop.
const _proCode = 'PRO-04242';
const _uid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Locale? previousLocale;

  setUp(() {
    previousLocale = appLocale.value;
    appLocale.value = const Locale('fr');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UserStore.reset();
    AdminStore.pendingPros.value = <PendingProModel>[];
    ProProfileStore.tokens.value = 150;
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.status.value = SubscriptionStatus.inactive;
    SubscriptionStore.activatedAt.value = null;
    ProfileRepository.debugIsVerifiedOverride = null;
    ProfileRepository.debugStatusMapOverride = null;
    AdminStore.debugApprovedProsOverride = null;
    SupabaseAuthService.debugConfiguredOverride = null;
  });

  tearDown(() {
    appLocale.value = previousLocale ?? const Locale('fr');
    SupabaseAuthService.debugResetOverrides();
    ProfileRepository.debugIsVerifiedOverride = null;
    ProfileRepository.debugStatusMapOverride = null;
    AdminStore.debugApprovedProsOverride = null;
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

  PendingProModel dossier({String status = 'pending'}) => PendingProModel(
        id: 'pro_1700000000000',
        name: 'Sami',
        phone: '22110033',
        email: 'sami.pro@allo.tn',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '01/01/2026',
        docImage: 'local/proof.jpg',
        status: status,
        proCode: _proCode,
        authUid: _uid,
      );

  Future<void> bindSession(ProVerification status) => UserStore.set(
        name: 'Sami',
        phone: '22110033',
        email: 'sami.pro@allo.tn',
        role: UserRole.professional,
        proCode: _proCode,
        verificationStatus: status,
      );

  // ── R4 · the shell leaves for the entry screen ────────────────────────
  testWidgets(
      'R4 · ProShell without a session routes to the entry screen '
      '(never parks on the verification gate)', (tester) async {
    UserStore.user.value = null;

    await tester.pumpWidget(app(const ProShell()));
    await tester.pump(); // post-frame callback schedules the route
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(VerificationGateScreen), findsNothing);
  });

  // ── R4 · the gate itself is never a dead end ──────────────────────────
  testWidgets('R4 · the gate with no session offers a way out', (tester) async {
    UserStore.user.value = null;

    await tester.pumpWidget(app(const VerificationGateScreen()));
    await tester.pump();

    // The recoverable view replaced the action-less spinner.
    expect(find.text('Votre session a expiré.'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // ── R5 · the gate reconciles on its own ───────────────────────────────
  testWidgets('R5 · the gate re-reads the server on mount and every 10s',
      (tester) async {
    SupabaseAuthService.debugConfiguredOverride = true;
    AdminStore.pendingPros.value = [dossier()];
    await bindSession(ProVerification.pending);

    var reads = 0;
    ProfileRepository.debugStatusMapOverride = () async {
      reads++;
      return <String, dynamic>{'status': 'pending'};
    };

    await tester.pumpWidget(app(const VerificationGateScreen()));
    await tester.pump();
    await tester.pump(); // flush the initState sync

    expect(reads, greaterThanOrEqualTo(1),
        reason: 'mounting the gate must trigger an immediate re-check');

    final afterMount = reads;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(reads, greaterThan(afterMount),
        reason: 'the periodic retry must keep reconciling without user input');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // ── R6 · a stale local marker is not a session ────────────────────────
  test('R6 · a stale marker with no cloud session routes to the guest',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
      'user_role': 'professionnel',
    });
    // Backend configured, but the SDK holds NO session (expired / revoked).
    SupabaseAuthService.debugConfiguredOverride = true;

    expect(await UserStore.checkInitialSession(), isNull);
  });

  test('R6 · local-only builds keep the marker (there is no server to ask)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
      'user_role': 'professionnel',
    });
    SupabaseAuthService.debugConfiguredOverride = false;

    expect(await UserStore.checkInitialSession(), 'professionnel');
  });

  // ── R2 · no downgrade without a confirmed decision ────────────────────
  test('R2 · a malformed server row never downgrades a confirmed approval',
      () async {
    SupabaseAuthService.debugConfiguredOverride = true;
    AdminStore.pendingPros.value = [dossier()];
    await bindSession(ProVerification.approved);
    // A row exists, but `status` is null: NOT a confirmed decision.
    ProfileRepository.debugStatusMapOverride =
        () async => <String, dynamic>{'status': null};

    await AdminStore.syncSessionStoresForCurrentUser();

    final u = UserStore.user.value!;
    expect(u.verificationStatus, ProVerification.approved,
        reason: 'an unresolved row must preserve the last known good state');
    expect(u.verificationUnconfirmed, isTrue);
    expect(u.needsVerificationGate, isFalse);
  });

  // ── R7 · "no row" is an answer, not a failure ─────────────────────────
  test('R7 · an absent professionals row is a DEFINITE pending answer',
      () async {
    SupabaseAuthService.debugConfiguredOverride = true;
    AdminStore.pendingPros.value = [dossier()];
    await bindSession(ProVerification.approved);
    // The query succeeded and returned nothing: no dossier server-side.
    ProfileRepository.debugStatusMapOverride = () async => <String, dynamic>{};

    await AdminStore.syncSessionStoresForCurrentUser();

    final u = UserStore.user.value!;
    expect(u.verificationStatus, ProVerification.pending,
        reason: 'an unprovisioned account must be gated, not retried forever');
    expect(u.verificationUnconfirmed, isFalse,
        reason: 'a definite answer is not an unconfirmed one');
  });
}
