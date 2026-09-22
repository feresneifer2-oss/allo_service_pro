import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/email_otp_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Completes the mandatory Email-OTP handshake for [email] exactly as
  /// `OtpScreen` does: issue a code → verify it (which CONSUMES the token) →
  /// unlock the credential record.
  ///
  /// Since the switch to Email OTP every registration starts LOCKED
  /// (`isVerified = false`), so a sign-in can only succeed after this step —
  /// tests that assert on the post-login profile must run it first.
  void verifyEmail(String email) {
    expect(EmailOtpService.trySendOtp(email), isTrue);
    final code = EmailOtpService.lastDemoCode!;
    expect(EmailOtpService.verifyOtp(email, code), isTrue);
    expect(UserStore.markEmailVerified(email: email), isTrue);
  }

  // ── Test isolation ──────────────────────────────────────────────────────
  // Every store in this app is a PROCESS-WIDE static, so each test is handed a
  // virgin state explicitly instead of inheriting whatever the previous test
  // left behind:
  //
  //  1. A clean mock prefs store (so nothing below can throw on a missing
  //     plugin binding, and no earlier fixture survives).
  //  2. `signOutAndReset()` returns every live session store (profile,
  //     subscription, tokens, chats, orders, notifications) to its
  //     logged-out defaults.
  //  3. Re-seeding the mock prefs installs THIS file's session fixture.
  //  4. `'user_accounts_json': '[]'` + `loadFromPrefs()` is what actually
  //     clears the CREDENTIAL REGISTRY. `UserStore._accounts` is only wiped
  //     when the persisted key is PRESENT (`loadFromPrefs` skips the clear
  //     when the key is absent) and `signOut()` deliberately KEEPS credentials
  //     so a returning user can log back in. Skipping this step lets a record
  //     registered by an earlier test (plus its verification lock) leak into
  //     the credential-rehydration test below, silently flipping
  //     `register()`/`signIn()` results.
  //  5. The admin registry and the in-memory session notifier are reset last,
  //     so no test can observe another test's pro entry or logged-in user.
  setUp(() async {
    EmailOtpService.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserStore.signOutAndReset();

    SharedPreferences.setMockInitialValues(<String, Object>{
      // Present-but-EMPTY registry: this is what makes loadFromPrefs() clear
      // the process-wide in-memory credential map.
      'user_accounts_json': '[]',
      'user_id': 'user_1',
      'user_name': 'Feres Ben Salah',
      'user_phone': '22123456',
      'user_email': 'feres@test.tn',
      'user_role_index': UserRole.client.index,
      'is_logged_in': true,
      'user_role': 'client',
      'pro_tokens': 42,
      'sub_isPaidSubscriber': true,
      'sub_statusIndex': SubscriptionStatus.active.index,
    });
    await UserStore.loadFromPrefs();

    // Logged-out in-memory start: tests that need a session load it themselves.
    UserStore.user.value = null;
    AdminStore.pendingPros.value = const <PendingProModel>[];
    RequestStore.requests.value = [];
    ChatStore.messages.value = {};
    ChatStore.sessions.value = {};
    NotificationStore.clear();
  });

  tearDown(() {
    RequestStore.reset();
    ChatStore.reset();
  });

  test('loadFromPrefs restores the session and auto-login flags', () async {
    await UserStore.loadFromPrefs();
    await SubscriptionStore.loadFromPrefs();
    await ProProfileStore.loadFromPrefs();

    expect(UserStore.user.value, isNotNull);
    expect(UserStore.user.value!.role, UserRole.client);
    expect(ProProfileStore.tokens.value, 42);
    expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
  });

  test('signOutAndReset wipes session keys and private stores', () async {
    await UserStore.loadFromPrefs();
    await SubscriptionStore.loadFromPrefs();
    await ProProfileStore.loadFromPrefs();

    // Simulate live session state.
    RequestStore.requests.value = [
      ServiceRequest(
        id: 'r-1',
        serviceTitleFr: 'Peinture',
        serviceTitleAr: 'دهان',
        professionalId: 'pro_1',
        professionalName: 'Ahmed',
        customerName: 'Feres',
        dateTime: DateTime.now(),
        address: 'Ariana',
        message: '',
        createdAt: DateTime.now(),
      ),
    ];
    ChatStore.activate('r-1');
    NotificationStore.add(
      NotificationModel(
        id: 'n-1',
        title: 'Test',
        message: 'Test notification',
        type: 'system',
        recipientId: 'pro_1',
        requestId: 'r-1',
        createdAt: DateTime.now(),
      ),
    );

    await UserStore.signOutAndReset();

    // 1. SharedPreferences: user data + auto-login flags are gone.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('user_id'), isFalse);
    expect(prefs.containsKey('user_name'), isFalse);
    expect(prefs.containsKey('user_role_index'), isFalse);
    expect(prefs.containsKey('is_logged_in'), isFalse);
    expect(prefs.containsKey('user_role'), isFalse);
    expect(prefs.containsKey('pro_tokens'), isFalse);
    expect(prefs.containsKey('sub_isPaidSubscriber'), isFalse);

    // 2. Notifiers: fully reset to logged-out defaults.
    // CUSTOMER-SCOPED DATA (CodeRabbit): orders and chat rooms belong to the
    // signed-in identity, so the sign-out now clears them too — a leftover
    // order history / conversation must never leak to the next user of this
    // device.
    expect(UserStore.user.value, isNull);
    expect(RequestStore.requests.value, isEmpty);
    expect(ChatStore.messages.value, isEmpty);
    expect(ChatStore.sessions.value, isNot(contains('r-1')));
    expect(NotificationStore.notifications.value, isEmpty);
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
    expect(ProProfileStore.tokens.value, 150);
  });

  test('app restart after logout NEVER auto-logs back in', () async {
    await UserStore.loadFromPrefs();
    await UserStore.signOutAndReset();

    // Simulate a cold restart: restore from (now empty) preferences.
    await UserStore.loadFromPrefs();
    await SubscriptionStore.loadFromPrefs();
    await ProProfileStore.loadFromPrefs();

    // No session → the splash must route to the welcome / auth flow.
    expect(UserStore.user.value, isNull);
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    expect(ProProfileStore.tokens.value, 150);
  });

  test(
      'pro credentials persist across restarts and login restores the full profile',
      () async {
    // ── Registration flow (register → role → pro binding) ──
    // Isolation guard (see setUp): the credential registry is a process-wide
    // static that survives logout ON PURPOSE (a returning user must be able to
    // log back in), so this test asserts its own virgin starting point instead
    // of trusting the harness. A record leaked from an earlier test would flip
    // `register()` to false and make this rehydration check pass or fail for
    // the wrong reason. The e-mail below is deliberately a FIXED literal: if
    // isolation ever breaks, this guard is what reports it.
    expect(UserStore.hasCredentialRecord(email: 'ali@pro.tn'), isFalse,
        reason: 'credential registry state leaked from a previous test');
    expect(UserStore.user.value, isNull,
        reason: 'no session may be inherited by this test');

    await UserStore.loadFromPrefs();
    await UserStore.signOutAndReset();
    expect(
        UserStore.register(
          name: 'Ali Craft',
          phone: '22111222',
          email: 'ali@pro.tn',
          password: 'secret1',
        ),
        isTrue);
    verifyEmail('ali@pro.tn');
    // AWAITED (CodeRabbit): `setRole` persists asynchronously — the reload
    // below must not race it.
    await UserStore.setRole(UserRole.professional);
    await UserStore.bindProAccount(
      proCode: 'PRO-00042',
      verificationStatus: ProVerification.pending,
    );

    // ── Cold restart: credentials restore from SharedPreferences ──
    await UserStore.loadFromPrefs();
    expect(await UserStore.signIn(email: 'ali@pro.tn', password: 'secret1'),
        isTrue);

    final u = UserStore.user.value!;
    expect(u.role, UserRole.professional);
    expect(u.proCode, 'PRO-00042');
    expect(u.verificationStatus, ProVerification.pending);
    expect(u.isProfessional, isTrue); // → login routes straight to ProShell

    // Wrong password is still rejected.
    expect(
        await UserStore.signIn(email: 'ali@pro.tn', password: 'nope'), isFalse);
  });

  test(
      'admin approval syncs the credential record so the next login hits ProShell',
      () async {
    await UserStore.loadFromPrefs();
    await UserStore.signOutAndReset();
    expect(
        UserStore.register(
          name: 'Sonia Craft',
          phone: '50987654',
          email: 'sonia@pro.tn',
          password: 'secret2',
        ),
        isTrue);
    verifyEmail('sonia@pro.tn');
    // AWAITED (CodeRabbit): `setRole` persists asynchronously.
    await UserStore.setRole(UserRole.professional);

    // Pro submits the registration form → pending entry in the registry.
    final registered = AdminStore.registerPro(PendingProModel(
      id: 'draft_1',
      name: 'Sonia Craft',
      phone: '50987654',
      email: 'sonia@pro.tn',
      professionFr: 'Menuisière',
      professionAr: 'نجّارة',
      submittedAt: '01/01/2026',
      status: 'pending',
    ));
    await UserStore.bindProAccount(
      proCode: registered.proCode,
      verificationStatus: ProVerification.pending,
    );

    // Admin taps [قبول الحساب] → registry approved + credential synced.
    // AWAITED (CodeRabbit): the credential sync inside `approvePro` is now
    // awaited internally, but the returned future itself must be awaited so
    // the reload below never races the persist step.
    await AdminStore.approvePro(registered.id);
    final entry =
        AdminStore.pendingPros.value.firstWhere((p) => p.id == registered.id);
    expect(entry.status, 'approved');
    expect(entry.badges, contains('cin'));

    // Restart → login → the restored profile is APPROVED (no pending gate).
    await UserStore.loadFromPrefs();
    expect(await UserStore.signIn(email: 'sonia@pro.tn', password: 'secret2'),
        isTrue);
    final u = UserStore.user.value!;
    expect(u.role, UserRole.professional);
    expect(u.verificationStatus, ProVerification.approved);
    expect(u.proCode, registered.proCode);
    expect(u.needsVerificationGate, isFalse);
  });
}
