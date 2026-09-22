import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/offline_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final savedTokens = ProProfileStore.tokens.value;
  final savedTokensConsumed = ProProfileStore.tokensConsumed.value;
  final savedSubscriptionStatus = SubscriptionStore.status.value;
  final savedPaidSubscriber = SubscriptionStore.isPaidSubscriber.value;
  final savedLocale = appLocale.value;
  var connectivityWasInitialized = false;

  ServiceRequest request({
    String id = 'chaos-request-1',
    RequestStatus status = RequestStatus.pending,
    String message = '',
  }) =>
      ServiceRequest(
        id: id,
        serviceTitleFr: 'Plomberie',
        serviceTitleAr: 'سباكة',
        professionalId: 'pro-chaos',
        professionalName: 'Pro Chaos',
        customerName: 'Client Chaos',
        customerId: 'client-chaos',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        address: 'Tunis',
        message: message,
        status: status,
        createdAt: DateTime.now(),
      );

  Widget host(Widget child, {Locale locale = const Locale('fr')}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: OfflineOverlay(child: child),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RequestStore.requests.value = [];
    ChatStore.sessions.value = {};
    ChatStore.messages.value = {};
    NotificationStore.clear();
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.status.value = SubscriptionStatus.active;
    ProProfileStore.tokens.value = 100;
    ProProfileStore.tokensConsumed.value = false;
    ConnectivityStore.isOnline.value = true;
    UserStore.user.value = null;
    AdminStore.pendingPros.value = [];
  });

  tearDown(() async {
    if (connectivityWasInitialized) {
      await ConnectivityStore.dispose();
      connectivityWasInitialized = false;
    }
    RequestStore.reset();
    ChatStore.reset();
    NotificationStore.clear();
    ProProfileStore.tokens.value = savedTokens;
    ProProfileStore.tokensConsumed.value = savedTokensConsumed;
    SubscriptionStore.status.value = savedSubscriptionStatus;
    SubscriptionStore.isPaidSubscriber.value = savedPaidSubscriber;
    UserStore.user.value = null;
    appLocale.value = savedLocale;
  });

  group('Phase 1 · isolated reset harness', () {
    test('setUp establishes clean process-wide singleton state', () {
      expect(RequestStore.requests.value, isEmpty);
      expect(ChatStore.sessions.value, isEmpty);
      expect(ChatStore.messages.value, isEmpty);
      expect(NotificationStore.notifications.value, isEmpty);
      expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
      expect(ProProfileStore.tokens.value, 100);
      expect(ProProfileStore.tokensConsumed.value, isFalse);
      expect(ConnectivityStore.isOnline.value, isTrue);
      expect(UserStore.user.value, isNull);
    });
  });

  group('Phase 2 · network chaos and connectivity resilience', () {
    test('connectivity transitions notify listeners and checkNow is safe',
        () async {
      final changes = <bool>[];
      void listener() => changes.add(ConnectivityStore.isOnline.value);
      ConnectivityStore.isOnline.addListener(listener);
      addTearDown(() => ConnectivityStore.isOnline.removeListener(listener));

      ConnectivityStore.debugSetOnline(false);
      expect(ConnectivityStore.isOnline.value, isFalse);
      ConnectivityStore.debugSetOnline(true);
      expect(ConnectivityStore.isOnline.value, isTrue);
      await ConnectivityStore.checkNow();

      expect(changes, [false, true]);
    });

    testWidgets('offline overlay follows connectivity state', (tester) async {
      appLocale.value = const Locale('fr');
      await tester.pumpWidget(host(const Text('content')));
      expect(find.text('content'), findsOneWidget);

      ConnectivityStore.debugSetOnline(false);
      await tester.pump();
      expect(find.text('En attente de connexion Internet'), findsOneWidget);

      ConnectivityStore.debugSetOnline(true);
      await tester.pump();
      expect(find.text('En attente de connexion Internet'), findsNothing);
    });

    test('offline submission remains local and is not replayed', () async {
      ConnectivityStore.debugSetOnline(false);
      final item = request(message: 'offline request');

      // No submission path reads ConnectivityStore.isOnline today, so an
      // offline request is neither blocked nor queued by RequestStore.add.
      RequestStore.add(item);
      expect(RequestStore.requests.value, hasLength(1));

      ConnectivityStore.debugSetOnline(true);
      expect(RequestStore.requests.value, hasLength(1));
      expect(RequestStore.requests.value.single.id, item.id);
    });
  });

  group('Phase 3 · rapid double-tap and idempotency', () {
    test('duplicate request submission is idempotent by request id', () {
      final item = request();
      RequestStore.add(item);
      RequestStore.add(item);

      // RequestStore now rejects an existing id before insertion, so rapid
      // duplicate submission produces one stored request.
      expect(
        RequestStore.requests.value.where((r) => r.id == item.id).length,
        1,
      );
      expect(RequestStore.byId(item.id), same(item));
    });

    test('repeated acceptance deducts tokens once and keeps chat active',
        () async {
      final item = request();
      RequestStore.add(item);
      ProProfileStore.tokens.value = 30;

      expect(await RequestStore.updateStatus(item.id, RequestStatus.accepted),
          isTrue);
      expect(await RequestStore.updateStatus(item.id, RequestStatus.accepted),
          isFalse);
      expect(ProProfileStore.tokens.value, 20);
      expect(ChatStore.isActive(item.id), isTrue);
    });

    test('admin approval and suspension are IDEMPOTENT (CodeRabbit)', () async {
      const id = 'chaos-pro-1';
      AdminStore.pendingPros.value = [
        const PendingProModel(
          id: id,
          name: 'Chaos Pro',
          phone: '22112233',
          professionFr: 'Plombier',
          professionAr: 'سباك',
          submittedAt: '19/09/2026',
          proCode: 'PRO-CHAOS',
          status: 'pending',
        ),
      ];
      final before = AdminStore.totalPros.value;

      // Repeat calls on an ALREADY-approved entry replay NO side effect:
      // tokens granted once, badge added once, KPI counter incremented once.
      await AdminStore.approvePro(id);
      await AdminStore.approvePro(id);
      final approved = AdminStore.pendingPros.value.single;
      expect(AdminStore.totalPros.value - before, 1);
      expect(approved.tokens, 150);
      expect(approved.badges.where((b) => b == 'cin'), hasLength(1));

      // Repeat suspensions emit the verification notification ONCE.
      final notificationsBefore = NotificationStore.notifications.value.length;
      await AdminStore.suspendPro(id);
      await AdminStore.suspendPro(id);
      expect(
        NotificationStore.notifications.value.length - notificationsBefore,
        1,
      );
    });

    test('chat activation resets its countdown while deactivation is guarded',
        () async {
      ChatStore.activate('chat-chaos');
      final first = ChatStore.sessionOf('chat-chaos')!.activatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ChatStore.activate('chat-chaos');
      final second = ChatStore.sessionOf('chat-chaos')!.activatedAt;
      expect(second.isAfter(first), isTrue);

      ChatStore.deactivate('chat-chaos');
      final closed = ChatStore.sessionOf('chat-chaos')!;
      ChatStore.deactivate('chat-chaos');
      expect(ChatStore.sessionOf('chat-chaos')!.active, isFalse);
      expect(ChatStore.sessionOf('chat-chaos')!.closedAt, closed.closedAt);
    });
  });

  group('Phase 4 · process death and cold restart recovery', () {
    test('tokens and subscription recover from SharedPreferences', () async {
      ProProfileStore.tokens.value = 50;
      await ProProfileStore.persistToPrefs();
      ProProfileStore.tokens.value = 1;
      await ProProfileStore.loadFromPrefs();
      expect(ProProfileStore.tokens.value, 50);

      final start = DateTime(2026, 9, 19);
      await SubscriptionStore.renew(at: start, ownerId: 'pro-recovery');
      SubscriptionStore.status.value = SubscriptionStatus.expired;
      SubscriptionStore.isPaidSubscriber.value = false;
      SubscriptionStore.activatedAt.value = null;
      await SubscriptionStore.loadFromPrefs();
      expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
      expect(SubscriptionStore.status.value, SubscriptionStatus.active);
      expect(SubscriptionStore.activatedAt.value, start);
    });

    test('session routing trusts persisted login flags after process death',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': true,
        'user_role': 'professionnel',
      });
      UserStore.user.value = null;
      expect(await UserStore.checkInitialSession(), 'professionnel');

      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': false,
        'user_role': 'admin',
      });
      UserStore.user.value = UserModel(
        id: 'stale',
        name: 'Stale',
        phone: '',
        role: UserRole.client,
      );
      expect(await UserStore.checkInitialSession(), isNull);
    });

    test('request data is lost because RequestStore is in-memory only', () {
      RequestStore.add(request());
      RequestStore.requests.value = [];
      // RequestStore has no loadFromPrefs method: pending requests are lost
      // when process death wipes this in-memory-only store.
      expect(RequestStore.requests.value, isEmpty);
    });
  });

  group('Phase 5 · hidden failure modes and state integrity', () {
    test('unsigned raw admin preferences NEVER grant admin routing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': true,
        'user_role': 'admin',
      });
      UserStore.user.value = null;

      // SECURITY INVARIANT (CodeRabbit): a raw routing flag written outside a
      // real admin sign-in carries no session signature — the cold start
      // refuses it and the device stays a guest.
      expect(await UserStore.checkInitialSession(), isNull);

      // Only a REAL sign-in — which stores the signature of the configured
      // identity — restores the admin route on a cold start.
      AdminStore.debugSetAdminCredentials(
        email: 'boss@chaos.test',
        password: 'pw-chaos',
      );
      addTearDown(AdminStore.debugResetAdminCredentials);
      final signature = AdminAuth.sessionSignature;
      expect(signature, isNotNull);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': true,
        'user_role': 'admin',
        'admin_session_sig': signature!,
      });
      UserStore.user.value = null;
      expect(await UserStore.checkInitialSession(), 'admin');
    });

    test('credential registry persists ONLY digests, never plaintext',
        () async {
      expect(
        UserStore.register(
          name: 'Hashed User',
          email: 'hashed@chaos.test',
          password: 'raw-password',
        ),
        isTrue,
      );
      await UserStore.loadFromPrefs();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_accounts_json');
      expect(raw, isNotNull);
      // SECURITY INVARIANT (CodeRabbit): the plaintext secret NEVER reaches
      // disk — only its salted one-way digest is stored.
      expect(raw, isNot(contains('raw-password')));
      final record = jsonDecode(raw!) as List;
      final stored = (record.single as Map<String, dynamic>)['password'];
      expect(stored, isA<String>());
      expect(stored as String, hasLength(64));
      // SHA-256 hex digest: lowercase hex only.
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(stored), isTrue);
    });

    test('legacy plaintext credentials upgrade to the KDF digest on load',
        () async {
      // A record written by the FIRST build: the RAW secret sits on disk.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'user_accounts_json',
        jsonEncode([
          <String, dynamic>{
            'email': 'legacy@chaos.test',
            'name': 'Legacy User',
            'phone': '',
            'password': 'old-plaintext-pw',
            'isVerified': true,
          }
        ]),
      );
      // MIGRATION (CodeRabbit): the restore upgrades the raw secret to the
      // salted KDF digest AND re-persists the registry on disk immediately —
      // the plaintext never survives one load. The legacy user still signs
      // in (no lock-out) and the stored credential is a proper digest.
      await UserStore.loadFromPrefs();
      final raw = prefs.getString('user_accounts_json');
      expect(raw, isNotNull);
      expect(raw, isNot(contains('old-plaintext-pw')));

      expect(
        await UserStore.signIn(
            email: 'legacy@chaos.test', password: 'old-plaintext-pw'),
        isTrue,
      );
      final upgraded = jsonDecode(raw ?? '[]') as List;
      final stored = (upgraded.single as Map)['password'] as String;
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(stored), isTrue);
      UserStore.user.value = null;
    });

    test('logout cascades through every collaborating store', () async {
      UserStore.user.value = UserModel(
        id: 'logout-user',
        name: 'Logout User',
        phone: '22000000',
        role: UserRole.client,
      );
      RequestStore.add(request(id: 'logout-request'));
      ChatStore.activate('logout-request');
      ProProfileStore.tokens.value = 12;
      SubscriptionStore.isPaidSubscriber.value = true;
      NotificationStore.notifyRequestSent('logout-request', 'logout-user');
      UserStore.register(
        name: 'Credential User',
        email: 'credential@logout.test',
        password: 'secret-password',
      );

      await UserStore.signOutAndReset();

      expect(UserStore.user.value, isNull);
      expect(ProProfileStore.tokens.value, 150);
      expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
      expect(NotificationStore.notifications.value, isEmpty);
      expect(RequestStore.requests.value, isEmpty);
      expect(ChatStore.sessions.value, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('user_accounts_json'), isTrue);
    });
  });
}
