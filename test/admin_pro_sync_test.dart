import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AdminStore.pendingPros.value = [
      PendingProModel(
        id: 'pp_sync_1',
        name: 'Sync Pro',
        phone: '99111222',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        submittedAt: '01/01/2026',
        docImage: 'assets/images/doc_placeholder.png',
        status: 'pending',
        proCode: 'PRO-00777',
        tokens: 40,
      ),
    ];
    UserStore.user.value = null;
    ProProfileStore.tokens.value = 150;
    SubscriptionStore.isPaidSubscriber.value = false;
    SubscriptionStore.status.value = SubscriptionStatus.active;
    SubscriptionStore.activatedAt.value = null;
  });

  PendingProModel entry() =>
      AdminStore.pendingPros.value.firstWhere((p) => p.id == 'pp_sync_1');

  void loginAsPro() {
    UserStore.set(
      name: 'Sync Pro',
      phone: '99111222',
      email: 'sync@pro.tn',
      role: UserRole.professional,
      proCode: 'PRO-00777',
      verificationStatus: ProVerification.pending,
    );
  }

  test('1 · approvePro flips the LIVE pending session to approved instantly',
      () async {
    loginAsPro();
    expect(UserStore.user.value!.verificationStatus, ProVerification.pending);

    // Admin taps [قبول الحساب] → no re-login needed.
    await AdminStore.approvePro('pp_sync_1');

    expect(entry().status, 'approved');
    expect(entry().badges, contains('cin'));
    expect(UserStore.user.value!.verificationStatus,
        ProVerification.approved); // live session follows
    expect(UserStore.user.value!.needsVerificationGate, isFalse);
    // 150 starter tokens land on the live session too.
    expect(ProProfileStore.tokens.value, 150);
    expect(entry().tokens, 150);
  });

  test('2 · syncSessionStoresForCurrentUser mirrors the registry truth',
      () async {
    // Admin granted a subscription + left 25 tokens on the registry.
    AdminStore.setPaid('pp_sync_1', isPaid: true);
    AdminStore.adjustTokens('pp_sync_1', -15); // 40 → 25
    UserStore.set(
      name: 'Sync Pro',
      phone: '99111222',
      email: 'sync@pro.tn',
      role: UserRole.professional,
      proCode: 'PRO-00777',
      verificationStatus: ProVerification.approved,
    );
    // Session stores still show a stale trial state.
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    expect(ProProfileStore.tokens.value, 150);

    await AdminStore.syncSessionStoresForCurrentUser();

    expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
    expect(ProProfileStore.tokens.value, 25);

    // · an expired subscription reverts the session to trial mode.
    AdminStore.setPaid('pp_sync_1', isPaid: false);
    await AdminStore.syncSessionStoresForCurrentUser();
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
  });

  test('3 · live token depletion is pushed into the admin registry', () async {
    await AdminStore.loadFromPrefs(); // binds the live-token bridge
    loginAsPro();

    // Pro accepts orders → tokens drop to 0.
    ProProfileStore.tokens.value = 0;

    expect(entry().tokens, 0); // admin card sees "Tokens Épuisés" instantly
  });

  test('4 · suspend / reactivate update the registry for the reactive gate',
      () async {
    loginAsPro();
    UserStore.updateProVerification(status: ProVerification.approved);

    await AdminStore.suspendPro('pp_sync_1');
    expect(entry().deactivated, isTrue); // → ProShell gate -1 (Compte Bloqué)

    await AdminStore.reactivatePro('pp_sync_1');
    expect(entry().deactivated, isFalse); // → dashboard restored instantly
  });

  test('4b · repeated suspend / reactivate are IDEMPOTENT (one side effect)',
      () async {
    loginAsPro();
    UserStore.updateProVerification(status: ProVerification.approved);

    final notificationsBefore = NotificationStore.notifications.value.length;
    await AdminStore.suspendPro('pp_sync_1');
    await AdminStore.suspendPro('pp_sync_1');
    expect(entry().deactivated, isTrue);
    // The verification notification fires ONLY on the actual transition —
    // a repeated suspend never duplicates it (CodeRabbit).
    expect(
      NotificationStore.notifications.value.length - notificationsBefore,
      1,
    );

    await AdminStore.reactivatePro('pp_sync_1');
    await AdminStore.reactivatePro('pp_sync_1');
    expect(entry().deactivated, isFalse);
    expect(
      NotificationStore.notifications.value.length - notificationsBefore,
      2,
    );
  });

  test('4c · suspend ⇄ reactivate share ONE sequential lock (deterministic)',
      () async {
    loginAsPro();
    UserStore.updateProVerification(status: ProVerification.approved);

    final notificationsBefore = NotificationStore.notifications.value.length;
    // Concurrent pair: both directions chain onto the SAME pipeline in call
    // order (FIFO), so the outcome is deterministic — suspend lands first,
    // re-activate second, exactly one notification per ACTUAL transition.
    await Future.wait([
      AdminStore.suspendPro('pp_sync_1'),
      AdminStore.reactivatePro('pp_sync_1'),
    ]);
    expect(entry().deactivated, isFalse);
    expect(
      NotificationStore.notifications.value.length - notificationsBefore,
      2,
    );
  });

  test('5 · no pro session → token bridge never pollutes the registry',
      () async {
    await AdminStore.loadFromPrefs();
    // Admin or no session - a stray token change must not touch entries.
    ProProfileStore.tokens.value = 0;
    expect(entry().tokens, 40);
  });

  test('E2E · full Admin↔Pro lifecycle (steps A→F)', () async {
    await AdminStore.loadFromPrefs(); // binds the live-token bridge

    // ── Step A · New Pro registers → status = pending ─────────────────────
    expect(
      UserStore.register(
        name: 'E2E Pro',
        phone: '98765432',
        email: 'e2e@pro.tn',
        password: 'pw123456',
      ),
      isTrue,
    );
    UserStore.setRole(UserRole.professional);
    final registered = AdminStore.registerPro(PendingProModel(
      id: 'draft_e2e',
      name: 'E2E Pro',
      phone: '98765432',
      professionFr: 'Électricien',
      professionAr: 'كهربائي',
      submittedAt: '02/01/2026',
      status: 'pending',
    ));
    await UserStore.bindProAccount(
      proCode: registered.proCode,
      verificationStatus: ProVerification.pending,
    );
    UserStore.set(
      name: 'E2E Pro',
      phone: '98765432',
      email: 'e2e@pro.tn',
      role: UserRole.professional,
      proCode: registered.proCode,
      verificationStatus: ProVerification.pending,
    );
    PendingProModel cur() =>
        AdminStore.pendingPros.value.firstWhere((p) => p.id == registered.id);
    expect(registered.status, 'pending');
    expect(UserStore.user.value!.needsVerificationGate, isTrue); // → gate

    // ── Step B · Admin approves → approved + cin badge ────────────────────
    await AdminStore.approvePro(registered.id);
    expect(cur().status, 'approved');
    expect(cur().badges, contains('cin'));

    // ── Step C · Session auto-routes away from the gate (no re-login) ─────
    expect(UserStore.user.value!.verificationStatus, ProVerification.approved);
    expect(UserStore.user.value!.needsVerificationGate, isFalse);

    // ── Step D · [Activer 30j (+15DT)] → cash log & paywall unlock ────────
    final cashBefore = AdminStore.cashRevenueTnd;
    await AdminStore.grantSubscription(registered.id); // the admin-button path
    expect(AdminStore.cashRevenueTnd, cashBefore + 15);
    expect(cur().isPaid, isTrue);
    expect(cur().paidUntilMs, isNotNull); // 30-day stamp stamped on the pro
    expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
    // Paywall gate: (!isPaid && tokens<=0) → false → dashboard unlocked.
    final paywalled = !SubscriptionStore.isPaidSubscriber.value &&
        ProProfileStore.tokens.value <= 0;
    expect(paywalled, isFalse);

    // ── Step E · [Suspendre] → Compte Bloqué gate ──────────────────────────
    await AdminStore.suspendPro(registered.id);
    expect(cur().deactivated, isTrue); // ProShell gate -1 locks instantly

    // ── Step F · Token depletion → "Tokens Épuisés" on the admin card ─────
    await AdminStore.reactivatePro(registered.id);
    await AdminStore.revokeSubscription(registered.id); // [Expirer] → trial
    expect(cur().isPaid, isFalse);
    expect(cur().paidUntilMs, isNull);
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    ProProfileStore.tokens.value = 0; // pro accepts orders until depletion
    expect(cur().tokens, 0); // registry mirrors → admin badge appears
    // Paywall gate flips back ON: trial + zero tokens.
    final relocked = !SubscriptionStore.isPaidSubscriber.value &&
        ProProfileStore.tokens.value <= 0;
    expect(relocked, isTrue);
  });

  test('6 · session sync NEVER extends an existing paid cycle', () {
    loginAsPro();
    // Admin grants the subscription → cycle seeded once (day 0).
    SubscriptionStore.renew();
    AdminStore.setPaid('pp_sync_1', isPaid: true);
    final cycleStart = SubscriptionStore.activatedAt.value;

    // Pro logs out & back in (or auto-login restore) → sync runs again.
    AdminStore.syncSessionStoresForCurrentUser();

    // .the cycle start is PRESERVED - no +30-day stacking on every sync.
    expect(SubscriptionStore.activatedAt.value, cycleStart);
    expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
  });

  test('7 · suspend / reactivate on an unknown proId exits safely', () {
    final before = AdminStore.pendingPros.value;
    // Must NOT throw (old code: unguarded firstWhere → StateError).
    AdminStore.suspendPro('ghost_id');
    AdminStore.reactivatePro('ghost_id');

    // Registry untouched by the failed lookups.
    expect(AdminStore.pendingPros.value.length, before.length);
    expect(
      AdminStore.pendingPros.value.every((p) => !p.deactivated),
      isTrue,
    );
  });

  test('8 · suspended clients persist across app restarts', () async {
    await AdminStore.suspendClient('client_ban_1');
    await AdminStore.suspendClient('client_ban_2');

    // Cold restart: bans are restored from SharedPreferences.
    AdminStore.suspendedClients.value = [];
    await AdminStore.loadFromPrefs();

    expect(AdminStore.suspendedClients.value,
        containsAll(['client_ban_1', 'client_ban_2']));
    expect(AdminStore.isClientSuspended('client_ban_1'), isTrue);
    expect(AdminStore.isClientSuspended('client_ban_2'), isTrue);
  });
  test('9 · an expired status never leaks into another pro session', () async {
    // ── Previous session on this device: a pro whose 30 days ran out ──────
    await SubscriptionStore.expire();
    expect(SubscriptionStore.status.value, SubscriptionStatus.expired);

    // ── A DIFFERENT pro logs in: their record carries NO paid cycle ───────
    loginAsPro(); // PRO-00777, entry().isPaid == false, paidUntilMs == null
    await AdminStore.syncSessionStoresForCurrentUser();

    // Trial, not "expired": a status left behind by the previous session is
    // never attributed to the pro logging in now.
    expect(SubscriptionStore.isPaidSubscriber.value, isFalse);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active,
        reason: 'a foreign expired state must not leak across sessions');

    // ── But THIS pro's own elapsed cycle still reports the truth ──────────
    await AdminStore.grantSubscription('pp_sync_1', days: -1); // cycle is over
    expect(entry().isPaid, isTrue);
    expect(SubscriptionStore.status.value, SubscriptionStatus.expired,
        reason: "expired only ever comes from this pro's own paid stamp");
  });

  test('10 · renew() attributes the cycle to the LIVE session account', () {
    loginAsPro();
    SubscriptionStore.renew();

    // An UNATTRIBUTED cycle is indistinguishable from legacy data and would
    // therefore be adoptable by whichever account logs in next. renew() must
    // stamp the live session account instead of leaving it owner-less, which is
    // what makes the ownership guard in markPaidPreservingCycle trustworthy.
    expect(SubscriptionStore.debugCycleOwnerId, UserStore.user.value!.id);
    expect(SubscriptionStore.isPaidSubscriber.value, isTrue);
  });

  test(
      '11 · a legacy paid flag re-syncs the cycle for the CURRENT account only',
      () {
    loginAsPro();
    final u = UserStore.user.value!;

    // The pro opens a cycle on this device.
    SubscriptionStore.renew();
    final ownCycleStart = SubscriptionStore.activatedAt.value;

    // .admin re-grants the legacy flag (paid, no expiry stamp) → sync re-opens
    // THIS account's own cycle: never a +30-day extension, never a foreign one.
    AdminStore.setPaid('pp_sync_1', isPaid: true);
    AdminStore.syncSessionStoresForCurrentUser();

    expect(SubscriptionStore.activatedAt.value, ownCycleStart,
        reason: 'the sync never extends (or shifts) an existing cycle');
    expect(SubscriptionStore.debugCycleOwnerId, u.id);
    expect(SubscriptionStore.status.value, SubscriptionStatus.active);
  });
}
