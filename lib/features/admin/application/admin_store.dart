import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:allo_service_pro/features/requests/application/request_store.dart';

// ─── Admin Credentials ──────────────────────────────────────────────────────
// ─── Reported-content model ──────────────────────────────────────────────────
class ReportModel {
  final String id;
  final String reportedBy;
  final String about;
  final String reason;
  final String date;
  bool resolved;

  ReportModel({
    required this.id,
    required this.reportedBy,
    required this.about,
    required this.reason,
    required this.date,
    this.resolved = false,
  });
}

// ─── Admin Store ─────────────────────────────────────────────────────────────
class AdminStore {
  AdminStore._();

  // Admin credentials (single admin session).
  // (Demo-grade: production should authenticate against Firebase/backend.)
  static const String adminEmail = 'feres.neifer2@gmail.com';
  static const String adminPassword = '24449959';

  static bool matchesAdmin(String email, String password) =>
      email == adminEmail && password == adminPassword;

  // Global stats
  static final totalUsers = ValueNotifier<int>(1240);
  static final totalPros = ValueNotifier<int>(347);
  static final totalRequests = ValueNotifier<int>(892);
  static final totalRevenue = ValueNotifier<double>(0.0);

  // Pending professionals
  static final pendingPros = ValueNotifier<List<PendingProModel>>([
    PendingProModel(
      id: 'pp_1',
      name: 'Mohamed Jaziri',
      phone: '+21620123456',
      professionFr: 'Plombier',
      professionAr: 'سبّاك',
      city: 'Tunis',
      submittedAt: '10/08/2026',
      docImage: null,
      status: 'pending',
    ),
    PendingProModel(
      id: 'pp_2',
      name: 'Sonia Belhaj',
      phone: '+21650987654',
      professionFr: 'Femme de ménage',
      professionAr: 'عاملة نظافة',
      city: 'Ariana',
      submittedAt: '10/08/2026',
      docImage: null,
      status: 'pending',
    ),
  ]);

  // ─── Live KPI metrics (derived from RequestStore / registry) ──────────
  static const List<RequestStatus> _liveStatuses = [
    RequestStatus.accepted,
    RequestStatus.enRoute,
    RequestStatus.arrived,
    RequestStatus.inProgress,
    RequestStatus.completed,
  ];

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// All-time accepted (live or completed) orders.
  static int get acceptedOrdersAllTime => RequestStore.requests.value
      .where((r) => _liveStatuses.contains(r.status))
      .length;

  /// Orders accepted today (created today and still/completed accepted).
  static int get acceptedOrdersToday => RequestStore.requests.value
      .where((r) =>
          _liveStatuses.contains(r.status) && _isToday(r.createdAt))
      .length;

  /// Orders refused today.
  static int get refusedOrdersToday => RequestStore.requests.value
      .where((r) =>
          r.status == RequestStatus.refused && _isToday(r.createdAt))
      .length;

  /// 💰 Cash revenue log: paid/renewed subscriptions × 15 DT.
  static int get cashRevenueTnd =>
      pendingPros.value.where((p) => p.isPaid).length * 15;

  static int get totalClients => UserStore.registeredClients.value.length;

  static int get totalProsCount =>
      pendingPros.value.where((p) => p.status == 'approved').length;

  // ─── Client suspension registry (persisted) ───────────────────────────
  static final suspendedClients = ValueNotifier<List<String>>([]);
  static const String _kSuspendedClients = 'admin_suspended_clients';

  static bool isClientSuspended(String? clientId) =>
      clientId != null && suspendedClients.value.contains(clientId);

  static Future<void> suspendClient(String clientId) async {
    if (suspendedClients.value.contains(clientId)) return;
    suspendedClients.value = [...suspendedClients.value, clientId];
    await _persistSuspendedClients();
  }

  static Future<void> reactivateClient(String clientId) async {
    suspendedClients.value =
        suspendedClients.value.where((c) => c != clientId).toList();
    await _persistSuspendedClients();
  }

  static Future<void> _persistSuspendedClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSuspendedClients, suspendedClients.value);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  // ─── Pro suspension with notification (persisted via registry) ────────
  static void suspendPro(String id) {
    // Guard: unknown proId → exit safely instead of throwing a
    // StateError from an unguarded firstWhere.
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final target = pendingPros.value[idx];
    setDeactivated(id, deactivated: true);
    NotificationStore.add(
      NotificationModel(
        id: '${DateTime.now().millisecondsSinceEpoch}_susp',
        title: 'تم تجميد حسابك',
        message: 'تم تجميد حسابك من طرف الإدارة. تواصل مع الدعم للمزيد.',
        type: 'system',
        recipientId: target.proCode ?? target.id,
        targetRole: 'professional',
        createdAt: DateTime.now(),
      ),
    );
  }

  static void reactivatePro(String id) {
    // Guard: unknown proId → exit safely instead of throwing a
    // StateError from an unguarded firstWhere.
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final target = pendingPros.value[idx];
    setDeactivated(id, deactivated: false);
    NotificationStore.add(
      NotificationModel(
        id: '${DateTime.now().millisecondsSinceEpoch}_react',
        title: 'تم إعادة تفعيل حسابك',
        message: 'تم إعادة تفعيل حسابك بنجاح. مرحباً بعودتك!',
        type: 'system',
        recipientId: target.proCode ?? target.id,
        targetRole: 'professional',
        createdAt: DateTime.now(),
      ),
    );
  }

  // ─── Two-way verification messaging (AlloService ↔ Pro) ───────────────
  /// Messages are stored on the pro registry entry as "sender|text" lines.
  static void sendVerificationMessage(String proId, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final idx = pendingPros.value.indexWhere((p) => p.id == proId);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      adminMessages: [...list[idx].adminMessages, 'AlloService|$t'],
    );
    pendingPros.value = list;
    persistToPrefs();
  }

  static void proReply(String proId, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final idx = pendingPros.value.indexWhere((p) => p.id == proId);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      adminMessages: [...list[idx].adminMessages, 'pro|$t'],
    );
    pendingPros.value = list;
    persistToPrefs();
  }

  static void setBadge(String id, String badge) {
    final list = List<PendingProModel>.from(pendingPros.value);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(badge: badge);
      pendingPros.value = list;
    }
  }

  static int get pendingCount =>
      pendingPros.value.where((p) => p.status == 'pending').length;

  // Admin function to reset request acceptance and deduct tokens again
  static void resetRequestAcceptance(String requestId) {
    RequestStore.adminResetAcceptance(requestId);
  }

  // ─── Registration gatekeeping · PRO-XXXXX lifecycle ─────────────────

  static int _proSeq = 1;
  static const String _kRegistry = 'admin_pending_pros_json';
  static const String _kSeq = 'admin_pro_seq';

  /// Generates the next unique non-repeating identifier (PRO-00001…).
  static String _nextProCode() {
    final used = pendingPros.value.map((p) => p.proCode).toSet();
    var n = _proSeq;
    String code() => 'PRO-${n.toString().padLeft(5, '0')}';
    while (used.contains(code())) {
      n++;
    }
    _proSeq = n + 1;
    return code();
  }

  /// Registers a new professional: assigns the unique PRO-XXXXX code,
  /// defaults to `status = pending`, no tokens, no badges, not paid.
  static PendingProModel registerPro(PendingProModel draft) {
    final code = _nextProCode();
    final pro = draft.copyWith(
      proCode: code,
      status: 'pending',
      tokens: 0,
      isPaid: false,
      badges: const [],
    );
    pendingPros.value = [pro, ...pendingPros.value];
    persistToPrefs();
    return pro;
  }

  /// Admin approval: unlocks the account and grants 150 initial tokens.
  static void approvePro(String id, {String? badge}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    // Official badge #1 is granted automatically on first approval.
    final badges = List<String>.from(list[idx].badges);
    if (!badges.contains('cin')) badges.add('cin');
    list[idx] = list[idx].copyWith(
      status: 'approved',
      tokens: 150,
      rejectionReason: null,
      badge: badge,
      badges: badges,
    );
    pendingPros.value = list;
    totalPros.value++;
    persistToPrefs();
    // Sync the credential record: a returning pro whose account has just
    // been approved logs in straight to the dashboard (no pending gate).
    UserStore.syncAccountVerificationByPhone(
      list[idx].phone,
      status: ProVerification.approved,
    );
    // Live session sync: if THIS pro is the currently logged-in user, flip
    // their verification state + grant the 150 starter tokens instantly —
    // any pending-approval gate on screen disappears without a re-login.
    final session = UserStore.user.value;
    final isCurrentSession = session != null &&
        (session.proCode == list[idx].proCode ||
            session.id == list[idx].id ||
            session.proCode == list[idx].id);
    if (isCurrentSession) {
      UserStore.updateProVerification(
        status: ProVerification.approved,
        proofPath: list[idx].docImage,
      );
      ProProfileStore.tokens.value = list[idx].tokens;
      ProProfileStore.persistToPrefs();
    }
  }

  /// Rejects with a visible reason; the Pro can re-upload proof later.
  static void rejectPro(String id, {String? reason}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(status: 'rejected', rejectionReason: reason);
    pendingPros.value = list;
    persistToPrefs();
    UserStore.syncAccountVerificationByPhone(
      list[idx].phone,
      status: ProVerification.rejected,
    );
  }

  /// Pro re-submits proof after a rejection — back to the review queue.
  static void resubmitProof(String id, {String? proofPath}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      status: 'pending',
      rejectionReason: null,
      docImage: proofPath,
    );
    pendingPros.value = list;
    persistToPrefs();
    UserStore.syncAccountVerificationByPhone(
      list[idx].phone,
      status: ProVerification.pending,
    );
  }

  /// Manual token adjustment from the admin detail modal (+/-).
  static void adjustTokens(String id, int delta) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final next = (list[idx].tokens + delta).clamp(0, 9999);
    list[idx] = list[idx].copyWith(tokens: next);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Toggles the 30-day unlimited paid plan for a specific Pro.
  /// Low-level registry toggle kept for tests/legacy callers that do not
  /// carry an expiry timestamp (the preserved-cycle path is used on sync).
  static void setPaid(String id, {required bool isPaid}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(isPaid: isPaid);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Grants a full [days]-day paid cycle for ONE pro (default 30d). The
  /// expiration timestamp is stored on the pro's own registry record, so the
  /// admin never mutates the logged-in session's global subscription store —
  /// and [syncSessionStoresForCurrentUser] preserves this exact expiry on
  /// every later login (no stacking of +30 days per sync).
  static void grantSubscription(String id, {int days = 30}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final until = DateTime.now().add(Duration(days: days));
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      isPaid: true,
      paidUntilMs: until.millisecondsSinceEpoch,
    );
    pendingPros.value = list;
    persistToPrefs();
    _syncSubscriptionForSession(list[idx]);
  }

  /// Reverts/expires the paid cycle of ONE pro — removes the paid flag and
  /// the expiry so the pro drops back to trial mode on next sync.
  static void revokeSubscription(String id) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(isPaid: false, paidUntilMs: null);
    pendingPros.value = list;
    persistToPrefs();
    _syncSubscriptionForSession(list[idx]);
  }

  /// Live-session mirror for the pro that is CURRENTLY logged in on this
  /// device: opening the cycle at the persisted start date keeps the exact
  /// expiration (never extends it); revoking drops straight to trial mode.
  /// No-op for any other registry entry (incl. the admin's own session).
  static void _syncSubscriptionForSession(PendingProModel entry) {
    final u = UserStore.user.value;
    if (u == null || !u.isProfessional) return;
    if (entry.proCode != u.proCode && entry.id != u.id && entry.proCode != u.id) {
      return;
    }
    if (entry.isPaid && entry.paidUntilMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(entry.paidUntilMs!);
      final start =
          until.subtract(const Duration(days: SubscriptionStore.durationDays));
      SubscriptionStore.renew(at: start);
    } else {
      SubscriptionStore.reset();
    }
  }

  /// Admin deactivation switch: a deactivated pro loses dashboard access
  /// and disappears from client listings until re-activated.
  static void setDeactivated(String id, {required bool deactivated}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(deactivated: deactivated);
    pendingPros.value = list;
    persistToPrefs();
  }

  // ─── Real-time session sync (Admin ↔ Pro lifecycle) ────────────────────
  // Single source of truth: the persisted registry [admin_pending_pros_json]
  // (account status · subscription · tokens · badges). The live session
  // stores (UserStore / SubscriptionStore / ProProfileStore) are MIRRORS of
  // the current pro's record — refreshed on login, on auto-login restore and
  // on every admin mutation touching the current session.

  /// Finds the registry entry matching the CURRENT pro session
  /// (matched by PRO code or account id).
  static PendingProModel? entryForUser(UserModel? u) {
    if (u == null || !u.isProfessional) return null;
    for (final p in pendingPros.value) {
      if (p.proCode == u.proCode ||
          p.id == u.id ||
          p.proCode == u.id) {
        return p;
      }
    }
    return null;
  }

  /// Mirrors the persisted registry record into the LIVE session stores.
  /// Called on every pro login and on auto-login restore, so a
  /// paid/activated pro always lands with the right subscription, token
  /// balance and approval state — even when the previous session on this
  /// device belonged to another account (e.g. the admin).
  static void syncSessionStoresForCurrentUser() {
    final u = UserStore.user.value;
    final entry = entryForUser(u);
    if (u == null || entry == null) return;

    // Subscription: paid → mirror the paid state WITHOUT extending the
    // existing cycle (the persisted paidUntil/expiration timestamp is
    // preserved across syncs). Not paid → trial mode.
    if (entry.isPaid && entry.paidUntilMs != null) {
      // Exact expiry on the record → re-open the same cycle at its original
      // start date so the expiration is NEVER shifted by a re-login/sync.
      final until = DateTime.fromMillisecondsSinceEpoch(entry.paidUntilMs!);
      final start =
          until.subtract(const Duration(days: SubscriptionStore.durationDays));
      SubscriptionStore.renew(at: start);
      // An ALREADY-ELAPSED cycle must stay expired: renew() flips the status
      // back to 'active' unconditionally, which would silently un-paywall a
      // pro whose 30 days are over. Restore the truthful 'expired' state.
      if (SubscriptionStore.isCycleOver(start, DateTime.now())) {
        SubscriptionStore.expire();
      }
    } else if (entry.isPaid) {
      // Legacy granted flag without an expiry timestamp → preserve whatever
      // cycle already exists in the session (or seed one from now).
      SubscriptionStore.markPaidPreservingCycle();
    } else if (SubscriptionStore.status.value ==
        SubscriptionStatus.expired) {
      // Trial downgrade of a session whose previous paid cycle already ran
      // out: keep the 'expired' status (the paywall stays honest) instead of
      // letting reset() stomp it back to the default 'active' state.
      SubscriptionStore.isPaidSubscriber.value = false;
      SubscriptionStore.persistToPrefs();
    } else {
      SubscriptionStore.reset();
    }

    // Tokens: mirror the registry balance into the session store.
    if (ProProfileStore.tokens.value != entry.tokens) {
      ProProfileStore.tokens.value = entry.tokens;
      ProProfileStore.persistToPrefs();
    }

    // Verification: the registry is authoritative. If the admin approved or
    // re-queued the account since the session snapshot was saved, the live
    // session follows immediately (no re-login required).
    final approved = entry.status == 'approved';
    if (approved && !u.verificationStatus.isApproved) {
      UserStore.updateProVerification(
        status: ProVerification.approved,
        proofPath: entry.docImage,
      );
    } else if (!approved &&
        u.verificationStatus.isApproved &&
        entry.status == 'pending') {
      UserStore.updateProVerification(status: ProVerification.pending);
    }
  }

  // Live-token bridge: whenever the session pro's balance changes (order
  // acceptance deduction, admin grant…), the registry is updated so the
  // admin "Professionnels" tab reflects depletion in real time.
  static bool _tokensBridgeBound = false;

  /// Binds the one-time listener that pushes live token changes from the
  /// session store into the admin registry. Called from [loadFromPrefs].
  static void bindLiveTokenBridge() {
    if (_tokensBridgeBound) return;
    _tokensBridgeBound = true;
    ProProfileStore.tokens.addListener(_pushLiveTokensToRegistry);
  }

  static void _pushLiveTokensToRegistry() {
    final entry = entryForUser(UserStore.user.value);
    if (entry == null) return; // no pro session (or admin) → nothing to sync
    if (entry.tokens == ProProfileStore.tokens.value) return;
    final idx = pendingPros.value.indexWhere((p) => p.id == entry.id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(tokens: ProProfileStore.tokens.value);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Adds a badge to the pro (no-op if already present).
  static void addBadge(String id, String badge) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final badges = List<String>.from(list[idx].badges);
    if (badges.contains(badge)) return;
    badges.add(badge);
    list[idx] = list[idx].copyWith(badges: badges);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Removes a badge from the pro (no-op if absent).
  static void removeBadge(String id, String badge) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final badges = List<String>.from(list[idx].badges)..remove(badge);
    list[idx] = list[idx].copyWith(badges: badges);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Adds or removes a manual badge (`verified` / `master` / `top_rated`).
  static void toggleBadge(String id, String badge) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final current = Set<String>.from(list[idx].badges);
    if (!current.add(badge)) current.remove(badge);
    list[idx] = list[idx].copyWith(badges: current.toList());
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Pre-filled WhatsApp inquiry text for a given Pro.
  static String whatsappMessage({
    required String name,
    required String profession,
    required String proCode,
  }) =>
      'مرحبا، أنا $name — $profession.\n'
      'معرّفي المهني: $proCode\n'
      'أرجو مراجعة طلب تفعيل حسابي. 🙏';

  // ─── Local persistence (SharedPreferences) ──────────────────────────

  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kRegistry,
        jsonEncode(pendingPros.value.map((p) => p.toJson()).toList()),
      );
      await prefs.setInt(_kSeq, _proSeq);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<void> loadFromPrefs() async {
    // Bind the live-token bridge once so session token changes flow into
    // the admin registry in real time.
    bindLiveTokenBridge();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Restore the suspended/banned client list FIRST — bans must survive
      // restarts even when the pro registry itself is empty or missing.
      suspendedClients.value =
          prefs.getStringList(_kSuspendedClients) ?? const <String>[];
      final raw = prefs.getString(_kRegistry);
      if (raw == null) return;
      final decoded = (jsonDecode(raw) as List)
          .map((e) => PendingProModel.fromJson(e as Map<String, dynamic>))
          .toList();
      pendingPros.value = decoded;
      _proSeq = (prefs.getInt(_kSeq) ?? decoded.length + 1).clamp(1, 999999);
    } catch (_) {
      // Corrupted registry: keep seeded demo data.
    }
  }
}
