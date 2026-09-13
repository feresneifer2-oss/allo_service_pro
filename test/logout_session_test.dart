import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
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
    RequestStore.requests.value = [];
    ChatStore.messages.value = {};
    ChatStore.sessions.value = {};
    NotificationStore.clear();
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

  test('signOutAndReset wipes session keys, stores and notifiers',
      () async {
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
    expect(UserStore.user.value, isNull);
    expect(RequestStore.requests.value, isEmpty);
    expect(ChatStore.messages.value, isEmpty);
    expect(ChatStore.sessions.value, isEmpty);
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

  test('pro credentials persist across restarts and login restores the full profile', () async {
    // ── Registration flow (register → role → pro binding) ──
    await UserStore.loadFromPrefs();
    await UserStore.signOutAndReset();
    expect(UserStore.register(
      name: 'Ali Craft',
      phone: '22111222',
      email: 'ali@pro.tn',
      password: 'secret1',
    ), isTrue);
    UserStore.setRole(UserRole.professional);
    UserStore.bindProAccount(
      proCode: 'PRO-00042',
      verificationStatus: ProVerification.pending,
    );

    // ── Cold restart: credentials restore from SharedPreferences ──
    await UserStore.loadFromPrefs();
    expect(UserStore.signIn(
        email: 'ali@pro.tn', password: 'secret1'), isTrue);

    final u = UserStore.user.value!;
    expect(u.role, UserRole.professional);
    expect(u.proCode, 'PRO-00042');
    expect(u.verificationStatus, ProVerification.pending);
    expect(u.isProfessional, isTrue); // → login routes straight to ProShell

    // Wrong password is still rejected.
    expect(UserStore.signIn(email: 'ali@pro.tn', password: 'nope'), isFalse);
  });

  test('admin approval syncs the credential record so the next login hits ProShell', () async {
    await UserStore.loadFromPrefs();
    await UserStore.signOutAndReset();
    expect(UserStore.register(
      name: 'Sonia Craft',
      phone: '50987654',
      email: 'sonia@pro.tn',
      password: 'secret2',
    ), isTrue);
    UserStore.setRole(UserRole.professional);

    // Pro submits the registration form → pending entry in the registry.
    final registered = AdminStore.registerPro(PendingProModel(
      id: 'draft_1',
      name: 'Sonia Craft',
      phone: '50987654',
      professionFr: 'Menuisière',
      professionAr: 'نجّارة',
      submittedAt: '01/01/2026',
      status: 'pending',
    ));
    UserStore.bindProAccount(
      proCode: registered.proCode,
      verificationStatus: ProVerification.pending,
    );

    // Admin taps [قبول الحساب] → registry approved + credential synced.
    AdminStore.approvePro(registered.id);
    final entry = AdminStore.pendingPros.value
        .firstWhere((p) => p.id == registered.id);
    expect(entry.status, 'approved');
    expect(entry.badges, contains('cin'));

    // Restart → login → the restored profile is APPROVED (no pending gate).
    await UserStore.loadFromPrefs();
    expect(
        UserStore.signIn(email: 'sonia@pro.tn', password: 'secret2'), isTrue);
    final u = UserStore.user.value!;
    expect(u.role, UserRole.professional);
    expect(u.verificationStatus, ProVerification.approved);
    expect(u.proCode, registered.proCode);
    expect(u.needsVerificationGate, isFalse);
  });
}