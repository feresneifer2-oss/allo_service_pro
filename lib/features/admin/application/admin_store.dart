import 'package:flutter/foundation.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:allo_service_pro/features/requests/application/request_store.dart';

// ─── Admin identity ────────────────────────────────────────────────────────
// it delegates every check to the AdminAuth boundary
// (see features/admin/data/admin_auth_repository.dart), which owns the
// environment configuration and the production server-side target.
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

  // ─── Admin identity (Phase 1 — SERVER-SIDE ONLY) ─────────────────────────
  // AdminStore holds NO credential and performs NO comparison: membership is
  // decided by the backend (`public.is_admin()`, keyed on `auth.uid()`)
  // through the AdminAuth boundary — see
  // features/admin/data/admin_auth_repository.dart and
  // supabase/migrations/20260927173046_phase1_admin_authorization.sql.
  /// Server-side check for the CURRENT authenticated identity: `true` iff the
  /// backend confirms it is enrolled as an administrator. FAIL-CLOSED on
  /// every error (offline, RPC failure, no Supabase session).
  static Future<bool> isAdminSignedIn() => AdminAuth.instance.isAdmin();

  // Global stats — LIVE DERIVED METRICS ONLY (audit remediation):
  // the previous build seeded hardcoded demo KPIs (1240 users / 347 pros /
  // 892 requests) that could never reflect reality. Every dashboard card now
  // reads a live getter derived from real registries (see `totalClients`,
  // `totalProsCount`, `acceptedOrdersToday`, `cashRevenueTnd`).
  //
  // `totalPros` is kept as a live COUNTER (starts at 0, incremented once per
  // real approval) so the idempotency test contract
  // (`approvePro` twice → counter +1 exactly once) stays observable.
  static final totalPros = ValueNotifier<int>(0);

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
      .where((r) => _liveStatuses.contains(r.status) && _isToday(r.createdAt))
      .length;

  /// Orders refused today.
  static int get refusedOrdersToday => RequestStore.requests.value
      .where((r) => r.status == RequestStatus.refused && _isToday(r.createdAt))
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
  // ─── Sequential execution guard (CodeRabbit) ─────────────────────────────
  // Renew / expire (and every other async mutation) are chained through a
  // single tail so two overlapping calls can never interleave their
  // read-modify-write cycles mid-flight.
  static Future<void> _opTail = Future<void>.value();

  static Future<T> _sequential<T>(Future<T> Function() op) {
    final stage = _opTail.then((_) => op());
    // A failed stage must not poison the chain for the next caller.
    _opTail = stage.then((_) {}, onError: (_) {});
    return stage;
  }

  /// Test hook: drains every scheduled mutation (renew / expire chains).
  @visibleForTesting
  static Future<void> debugDrainOperations() => _opTail;

  /// Suspends (bans) a professional — IDEMPOTENT (CodeRabbit).
  ///
  /// Suspending an ALREADY-suspended pro re-runs no side effect: the
  /// verification notification is emitted only on the actual transition,
  /// so repeat calls never duplicate the warning message.
  static Future<void> suspendPro(String id) => _sequential(() async {
        // Guard: unknown proId → exit safely instead of throwing a
        // StateError from an unguarded firstWhere.
        final idx = pendingPros.value.indexWhere((p) => p.id == id);
        if (idx == -1) return;
        // IDEMPOTENT (CodeRabbit): suspending an ALREADY-suspended pro
        // re-runs no side effect — the verification notification is emitted
        // only on the actual transition, so repeat calls never duplicate it.
        if (pendingPros.value[idx].deactivated) return;
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
        await persistToPrefs();
      });

  /// Re-activates a suspended professional — SAME SHARED LOCK as [suspendPro]
  /// (CodeRabbit): the suspend ⇄ unsuspend transition is a read-modify-write
  /// on ONE registry row, so both directions run strictly one after the other
  /// through the [_sequential] pipeline — a concurrent suspend/re-activate
  /// pair can never interleave their state mutations. IDEMPOTENT too: an
  /// ALREADY-active entry replays no notification.
  static Future<void> reactivatePro(String id) => _sequential(() async {
        // Guard: unknown proId → exit safely instead of throwing a
        // StateError from an unguarded firstWhere.
        final idx = pendingPros.value.indexWhere((p) => p.id == id);
        if (idx == -1) return;
        if (!pendingPros.value[idx].deactivated) return;
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
        await persistToPrefs();
      });

  // ─── Two-way verification messaging (AlloService ↔ Pro) ───────────────
  /// Messages are stored on the pro registry entry as "sender|text" lines.
  static Future<void> sendVerificationMessage(String proId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final idx = pendingPros.value.indexWhere((p) => p.id == proId);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      adminMessages: [...list[idx].adminMessages, 'AlloService|$t'],
    );
    pendingPros.value = list;
    await persistToPrefs();
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

  /// Whether a registry record carries a usable authentication e-mail.
  ///
  /// Drives the credential-sync boundary: a record WITH an identity is synced
  static bool _hasEmail(String? email) =>
      email != null && email.trim().isNotEmpty;

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
  /// Approves a pending professional — IDEMPOTENT (CodeRabbit).
  ///
  /// The first call performs every side effect (activation, badge, tokens,
  /// notification, KPIs). Any repeat call on an ALREADY-approved entry
  /// performs none of them and returns success — no duplicate tokens,
  /// badges, notifications or inflated KPI counters.
  ///
  /// PHASE 3P — SERVER-FIRST: the local approval runs ONLY after the backend
  /// RPC `public.admin_provision_professional` confirmed the professional row
  /// (`public.professionals.id = authUid`, created/verified server-side for an
  /// authenticated admin). Without that confirmation NOTHING local changes:
  /// the entry stays `pending` with no tokens, no badge and no success state,
  /// so the UI can never show an approved professional the server ignores.
  ///
  /// Returns `true` when the professional IS approved (fresh approval or an
  /// idempotent replay of one); `false` when the entry is unknown, carries no
  /// usable `authUid`, or the server provisioning failed.
  static Future<bool> approvePro(String id, {String? badge}) =>
      _sequential(() => _approveProOnce(id, badge));

  static Future<bool> _approveProOnce(String id, String? badge) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return false;
    // IDEMPOTENT (CodeRabbit): an ALREADY-approved entry replays none of the
    // side effects below (no duplicate tokens/badges/notifications, no
    // inflated KPI counter, no redundant server round-trip) and reports
    // success.
    if (pendingPros.value[idx].status == 'approved') return true;

    // ── PHASE 3P — SERVER PROVISIONING FIRST ──────────────────────────────
    // The backend owns the `public.professionals` row: the admin-only RPC
    // creates/verifies it for `authUid` and is idempotent, so a retry after
    // ANY later failure is always safe. Until it confirms, the local state
    // must not move (fail-closed).
    if (!await _provisionProfessionalServer(pendingPros.value[idx])) {
      return false;
    }

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
    // AWAITED (CodeRabbit): the caller may reload prefs right after approval
    // (logout/restart simulations) — a fire-and-forget write races the read.
    await persistToPrefs();
    // Sync the credential record: a returning pro whose account has just
    // been approved logs in straight to the dashboard (no pending gate).
    //
    // The e-mail is the authentication identity (Email OTP), so it is the
    // PRIMARY lookup. The phone sync is a LEGACY-ONLY fallback: it may run
    // exclusively when the record carries NO e-mail identity, so an e-mail
    // account can never be reached — or cross-matched — through a phone
    // number that happens to be shared.
    if (_hasEmail(list[idx].email)) {
      await UserStore.syncAccountVerificationByEmail(
        list[idx].email,
        status: ProVerification.approved,
        // Approval clears any stale rejection reason on the record too.
        clearReason: true,
      );
    } else {
      await UserStore.syncAccountVerificationByPhone(
        list[idx].phone,
        status: ProVerification.approved,
        clearReason: true,
      );
    }
    // Live session sync: if THIS pro is the currently logged-in user, flip
    // their verification state + grant the 150 starter tokens instantly —
    // any pending-approval gate on screen disappears without a re-login.
    if (_matchesCurrentSession(list[idx])) {
      await UserStore.updateProVerification(
        status: ProVerification.approved,
        proofPath: list[idx].docImage,
        clearReason: true,
      );
      ProProfileStore.tokens.value = list[idx].tokens;
      await ProProfileStore.persistToPrefs();
    }
    return true;
  }

  /// PHASE 3P — server-side provisioning gate for [entry].
  ///
  /// FAIL-CLOSED CONTRACT:
  ///  * `authUid` missing / blank / not a UUID → `false` and the RPC is
  ///    NEVER called (legacy seeds, admin drafts and offline records carry no
  ///    server identity to provision — the local approval must not run).
  ///  * RPC failure (offline, revoked admin, unknown profile, any error) →
  ///    `false`; the boundary reports the error (it is never swallowed) and
  ///    the professional stays PENDING locally.
  ///  * RPC success (the server returned the VERIFIED professional row) →
  ///    `true`, and only then does the local approval run.
  static Future<bool> _provisionProfessionalServer(
      PendingProModel entry) async {
    final uid = _uuidOrNull(entry.authUid);
    if (uid == null) return false;
    final provisionedId = await AdminAuth.instance.provisionProfessional(
      userId: uid,
      specialty: _provisionSpecialty(entry),
      bio: _provisionBio(entry),
    );
    return provisionedId != null;
  }

  /// UUID-shape gate for the RPC's `uuid` parameter: a local non-UUID
  /// identity (the offline registration fallback) would be rejected by the
  /// server anyway — it is refused here FIRST so the RPC is never called
  /// with it.
  static final RegExp _uuidShape = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? _uuidOrNull(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return _uuidShape.hasMatch(trimmed) ? trimmed : null;
  }

  /// `dd/MM/yyyy` display label for [PendingProModel.submittedAt] — the SAME
  /// shape the seeded registry records and the wizard drafts already use, so
  /// a hydrated entry sorts/reads identically to a locally registered one.
  static String _todayLabel() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year}';
  }

  /// `p_specialty`: the registration's specialty chips joined with ", " when
  /// present, else the profession label; `null` when both are empty (the RPC
  /// then stores null / preserves an already-stored value).
  static String? _provisionSpecialty(PendingProModel entry) {
    final chips = <String>[
      for (final s in entry.specialtiesFr)
        if (s.trim().isNotEmpty) s.trim(),
    ];
    if (chips.isNotEmpty) return chips.join(', ');
    final fallback = entry.professionFr.trim();
    return fallback.isEmpty ? null : fallback;
  }

  /// `p_bio`: the registration wizard's free-text description; `null` when
  /// blank — never an empty string.
  static String? _provisionBio(PendingProModel entry) {
    final bio = entry.description?.trim();
    return (bio == null || bio.isEmpty) ? null : bio;
  }

  /// NON-EMPTY IDENTIFIER GUARD (CodeRabbit): a live-session match is only
  /// real when a genuinely-populated identifier agrees. Two records both
  /// carrying `proCode == null` (or `''`) are NOT the same account — matching
  /// on an empty/null value would flip the wrong session's verification
  /// state, and `session.id == entry.id` only counts when the entry id is a
  /// real registry id (not the transient `draft_*` placeholder).
  static bool _matchesCurrentSession(PendingProModel entry) {
    final session = UserStore.user.value;
    if (session == null) return false;
    bool nonEmpty(String? s) => s != null && s.trim().isNotEmpty;
    if (nonEmpty(entry.proCode) && session.proCode == entry.proCode) {
      return true;
    }
    if (nonEmpty(entry.id) &&
        !entry.id.startsWith('draft_') &&
        session.id == entry.id) {
      return true;
    }
    if (nonEmpty(entry.id) && session.proCode == entry.id) {
      return true;
    }
    return false;
  }

  /// Rejects with a visible reason; the Pro can re-upload proof later.
  ///
  /// PHASE 3P — SERVER WRITE FIRST (fail-closed), mirroring [approvePro]:
  /// when the backend is reachable, the admin-only RPC
  /// `admin_reject_professional` must CONFIRM the rejection before any local
  /// state moves. A refused/failed call — or an entry without a usable
  /// server-side `authUid` — returns `false` and the local entry keeps its
  /// status and reason untouched.
  ///
  /// When Supabase is NOT configured, the server call is skipped entirely and
  /// the legacy local-only path below runs unchanged (offline / admin-seed
  /// fallback stays fully functional).
  ///
  /// Returns `true` when the rejection WAS applied (server-confirmed or
  /// local-only fallback); `false` when the entry is unknown or the server
  /// refused it.
  static Future<bool> rejectPro(String id, {String? reason}) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return false;

    // ── PHASE 3P — SERVER REJECTION FIRST ──────────────────────────────────
    // The backend owns `public.professionals.status` + `rejection_reason`:
    // the admin-only RPC writes them first, and until it confirms, the local
    // state must not move (fail-closed). An UNCONFIGURED boundary skips the
    // round-trip and falls through to the local-only behaviour below.
    if (SupabaseAuthService.isConfigured) {
      final targetUserId = _uuidOrNull(pendingPros.value[idx].authUid);
      // No server identity to reject (legacy seed / draft / offline record):
      // exactly like _provisionProfessionalServer, the RPC is NEVER called
      // without a real uuid — and the local rejection is refused too.
      if (targetUserId == null) return false;
      final ok = await AdminAuth.instance.rejectProfessional(
        userId: targetUserId,
        // The parameter is non-null by contract; a reason-less rejection
        // travels as an empty string (the session sync below keeps its own
        // nullable `reason`).
        reason: reason ?? '',
      );
      if (!ok) return false; // fail-closed: server refused → no local change
    }

    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(status: 'rejected', rejectionReason: reason);
    pendingPros.value = list;
    await persistToPrefs();
    if (_hasEmail(list[idx].email)) {
      // AWAITED (CodeRabbit): the credential write must settle before the
      // caller (or a prefs reload in a restart simulation) reads it back.
      await UserStore.syncAccountVerificationByEmail(
        list[idx].email,
        status: ProVerification.rejected,
        // The reason travels with the record so a re-login always shows WHY.
        reason: reason,
      );
    } else {
      await UserStore.syncAccountVerificationByPhone(
        list[idx].phone,
        status: ProVerification.rejected,
        reason: reason,
      );
    }
    // Live session sync (parity with approvePro): a currently logged-in pro
    // sees the rejection — WITH its reason — without re-login. The match
    // goes through the NON-EMPTY identifier guard, never a raw null/empty
    // comparison that could flip an unrelated session.
    if (_matchesCurrentSession(list[idx])) {
      await UserStore.updateProVerification(
        status: ProVerification.rejected,
        reason: reason,
      );
    }
    return true;
  }

  /// Pro re-submits proof after a rejection — back to the review queue.
  ///
  /// Returns `true` when the pending entry was found AND the server accepted
  /// the reset (Phase 3Q), `false` when no entry matches [id] or the server
  /// refused — fail-closed. Callers MUST check the result and skip their
  /// local account/profile updates on `false` (CodeRabbit): mutating the
  /// session when the repository accepted nothing would desync the two.
  static Future<bool> resubmitProof(String id, {String? proofPath}) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return false;

    // ── PHASE 3Q — SERVER RESET FIRST (fail-closed) ─────────────────────────
    // The authoritative status lives in Supabase: the pro's OWN row can only
    // be moved back to 'pending' by `public.professional_resubmit_own_proof()`
    // (keyed on auth.uid() — 'rejected' → 'pending', idempotent on 'pending',
    // 'approved' refused server-side). Only a server-confirmed reset lets the
    // local mutations below run; `false` (offline / refused / approved)
    // aborts BEFORE any local write, mirroring rejectPro — the registry,
    // prefs and local session must never run ahead of the server.
    if (SupabaseAuthService.isConfigured) {
      final ok = await ProfileRepository.resubmitOwnProfessionalProof(
        proofPath: proofPath,
      );
      if (!ok) return false;
    }

    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      status: 'pending',
      rejectionReason: null,
      docImage: proofPath,
    );
    pendingPros.value = list;
    await persistToPrefs();
    if (_hasEmail(list[idx].email)) {
      // AWAITED (CodeRabbit): the credential write must settle before the
      // caller (or a prefs reload in a restart simulation) reads it back.
      await UserStore.syncAccountVerificationByEmail(
        list[idx].email,
        status: ProVerification.pending,
        // Re-submission strips the old reason and re-binds the new proof.
        clearReason: true,
        proofPath: proofPath,
      );
    } else {
      await UserStore.syncAccountVerificationByPhone(
        list[idx].phone,
        status: ProVerification.pending,
        clearReason: true,
        proofPath: proofPath,
      );
    }
    // Live session sync (parity with approvePro/rejectPro): a currently
    // logged-in pro sees the pending state instantly — WITHOUT a re-login.
    // The match goes through the NON-EMPTY identifier guard, never a raw
    // null/empty comparison that could flip an unrelated session.
    if (_matchesCurrentSession(list[idx])) {
      await UserStore.updateProVerification(
        status: ProVerification.pending,
        clearReason: true,
        proofPath: proofPath,
      );
    }
    return true;
  }

  /// Persists the DURABLE remote handle of an uploaded proof into the dossier
  /// (CodeRabbit): a device-local path dies with the device — the registry
  /// must also carry the backend path the admin can resolve from ANY device.
  ///
  /// Pure registry write: no status change, no notifications, fully awaited
  /// so the caller knows the handle is durable before it leaves the flow.
  static Future<void> attachProofRemotePath(
    String id, {
    required String remotePath,
  }) async {
    if (remotePath.trim().isEmpty) return;
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(proofImagePath: remotePath.trim());
    pendingPros.value = list;
    await persistToPrefs();
  }

  /// Manual token adjustment from the admin detail modal (+/-).
  ///
  /// PHASE 3S — SERVER-FIRST: with a configured backend the RPC
  /// `admin_adjust_tokens` is the source of truth; the local registry only
  /// mirrors the balance the server returned. Fail-closed: a refused RPC
  /// returns null and leaves the local state untouched. An UNCONFIGURED
  /// (local-only) build keeps the legacy clamp behavior.
  static Future<int?> adjustTokens(String id, int delta) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return null;
    if (SupabaseAuthService.isConfigured) {
      final target = pendingPros.value[idx];
      final uid = _uuidOrNull(target.authUid ?? '') ?? target.id;
      final newBalance = await AdminAuth.instance.adjustTokens(
        userId: uid,
        delta: delta,
      );
      if (newBalance == null) return null; // fail-closed: no local change
      // The SERVER value is the source of truth for the local mirror.
      final list = List<PendingProModel>.from(pendingPros.value);
      list[idx] = list[idx].copyWith(tokens: newBalance);
      pendingPros.value = list;
      await persistToPrefs();
      return newBalance;
    }
    final list = List<PendingProModel>.from(pendingPros.value);
    final next = (list[idx].tokens + delta).clamp(0, 9999);
    list[idx] = list[idx].copyWith(tokens: next);
    pendingPros.value = list;
    persistToPrefs();
    return next;
  }

  /// Toggles the 30-day unlimited paid plan for a specific Pro.
  /// Low-level registry toggle kept for tests/legacy callers that do not
  /// carry an expiry timestamp (the preserved-cycle path is used on sync).
  ///
  /// PHASE 3S — SERVER-FIRST: with a configured backend the toggle is pushed
  /// to `admin_set_subscription` BEFORE any local change (grant → now+30d,
  /// revoke → null); a refused RPC leaves the registry untouched
  /// (fail-closed). An UNCONFIGURED (local-only) build keeps the legacy
  /// local-only behavior.
  static Future<bool> setPaid(String id, {required bool isPaid}) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return false;
    if (SupabaseAuthService.isConfigured) {
      final target = pendingPros.value[idx];
      final uid = _uuidOrNull(target.authUid ?? '') ?? target.id;
      final until =
          isPaid ? DateTime.now().add(const Duration(days: 30)) : null;
      final ok = await AdminAuth.instance.setSubscription(
        userId: uid,
        until: until,
      );
      if (!ok) return false; // fail-closed: no local change
    }
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(isPaid: isPaid);
    pendingPros.value = list;
    persistToPrefs();
    return true;
  }

  /// Grants a full [days]-day paid cycle for ONE pro (default 30d). The
  /// expiration timestamp is stored on the pro's own registry record, so the
  /// admin never mutates the logged-in session's global subscription store —
  /// and [syncSessionStoresForCurrentUser] preserves this exact expiry on
  /// every later login (no stacking of +30 days per sync).
  ///
  /// PHASE 3S — SERVER-FIRST: with a configured backend the cycle is granted
  /// through `admin_set_subscription` BEFORE any local change; a refused RPC
  /// leaves the registry untouched (fail-closed). An UNCONFIGURED
  /// (local-only) build keeps the legacy local-only behavior.
  static Future<bool> grantSubscription(String id, {int days = 30}) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return false;
    final until = DateTime.now().add(Duration(days: days));
    if (SupabaseAuthService.isConfigured) {
      final target = pendingPros.value[idx];
      final uid = _uuidOrNull(target.authUid ?? '') ?? target.id;
      final ok = await AdminAuth.instance.setSubscription(
        userId: uid,
        until: until,
      );
      if (!ok) return false; // fail-closed: no local change
    }
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      isPaid: true,
      paidUntilMs: until.millisecondsSinceEpoch,
    );
    pendingPros.value = list;
    await _syncSubscriptionForSession(list[idx]);
    await persistToPrefs();
    return true;
  }

  /// Reverts/expires the paid cycle of ONE pro — removes the paid flag and
  /// the expiry so the pro drops back to trial mode on next sync.
  static Future<void> revokeSubscription(String id) async {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(isPaid: false, paidUntilMs: null);
    pendingPros.value = list;
    await _syncSubscriptionForSession(list[idx]);
    await persistToPrefs();
  }

  /// Live-session mirror for the pro that is CURRENTLY logged in on this
  /// device: opening the cycle at the persisted start date keeps the exact
  /// expiration (never extends it); revoking drops straight to trial mode.
  /// No-op for any other registry entry (incl. the admin's own session), so a
  /// mutation can never touch a state that belongs to another account.
  static Future<void> _syncSubscriptionForSession(PendingProModel entry) async {
    final u = UserStore.user.value;
    if (u == null || !u.isProfessional) return;
    // IDENTIFIER GUARD (CodeRabbit): the same non-empty rule [entryForUser]
    // enforces is applied HERE too — the comparison below used to accept a
    // `null == null` / `'' == ''` match, so an identifier-less session (no PRO
    // code, blank id) matched an entry that also carries none and the admin
    // mutation leaked into an unrelated session's subscription state.
    final sessionCode = (u.proCode ?? '').trim();
    final sessionId = u.id.trim();
    if (sessionCode.isEmpty && sessionId.isEmpty) return;
    final entryCode = (entry.proCode ?? '').trim();
    final matches = (sessionCode.isNotEmpty && entryCode == sessionCode) ||
        (sessionId.isNotEmpty &&
            (entry.id == sessionId ||
                (entryCode.isNotEmpty && entryCode == sessionId)));
    if (!matches) return;
    if (entry.isPaid && entry.paidUntilMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(entry.paidUntilMs!);
      final start =
          until.subtract(const Duration(days: SubscriptionStore.durationDays));
      // SEQUENTIAL renew→expire (CodeRabbit): both writers mutate the same
      // subscription state — run them strictly one after the other so two
      // overlapping calls can never interleave their read-modify-write
      // cycles (the previous Future.wait raced renew() against expire()).
      await SubscriptionStore.renew(at: start, ownerId: u.id);
      // Same rule as [syncSessionStoresForCurrentUser]: an ALREADY-ELAPSED
      // stamp must report 'expired' instead of silently re-opening a cycle
      // that is over (renew() flips the status back to 'active').
      if (SubscriptionStore.isCycleOver(start, DateTime.now())) {
        await SubscriptionStore.expire();
      }
    } else {
      await SubscriptionStore.reset();
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

  /// Finds the registry entry matching the CURRENT pro session.
  ///
  /// IDENTIFIER-GUARDED MATCHING (CodeRabbit): a null/blank/whitespace
  /// identifier is NEVER used for matching. Without that guard,
  /// `p.proCode == u.proCode` evaluates as `null == null` for an
  /// admin-seeded record that carries no PRO code, so a pro whose own code is
  /// absent would be matched with a FOREIGN dossier (wrong approval state,
  /// wrong token balance, wrong proof). A valid, NON-EMPTY PRO code is
  /// required for a code match; the account id is accepted only as a legacy
  /// fallback and must be non-empty as well.
  static PendingProModel? entryForUser(UserModel? u) {
    if (u == null || !u.isProfessional) return null;
    final proCode = (u.proCode ?? '').trim();
    final accountId = u.id.trim();
    // Nothing usable to match on: never fall back to a `null == null`
    // comparison — an identifier-less session owns no dossier.
    if (proCode.isEmpty && accountId.isEmpty) return null;
    for (final p in pendingPros.value) {
      final entryCode = (p.proCode ?? '').trim();
      // PRO-code match: both sides must carry a real code.
      if (proCode.isNotEmpty && entryCode == proCode) return p;
      // Legacy id fallback: the session id (or, for records written before
      // the PRO code existed, the entry's code) must be a real identifier.
      if (accountId.isNotEmpty &&
          (p.id == accountId ||
              (entryCode.isNotEmpty && entryCode == accountId))) {
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
  static Future<void> syncSessionStoresForCurrentUser() async {
    final u = UserStore.user.value;
    final entry = entryForUser(u);
    if (u == null || entry == null) {
      // No registry mirror to apply — the SERVER still decides whether a
      // professional session may be opened (fail-closed when unresolved).
      await _applyServerVerificationAuthority();
      return;
    }

    // Subscription: scoped STRICTLY to THIS pro's registry record.
    //
    // The session store is device-global (its prefs carry no account key), so
    // a status left behind by a PREVIOUS session on this device - the admin's
    // own session, or another pro whose 30 days ran out - must never be
    // attributed to the pro logging in now. The registry entry is the only
    // truth: a paid stamp opens that exact cycle, anything else means trial.
    if (entry.isPaid && entry.paidUntilMs != null) {
      // Exact expiry on the record -> re-open the same cycle at its original
      // start date so the expiration is NEVER shifted by a re-login/sync.
      final until = DateTime.fromMillisecondsSinceEpoch(entry.paidUntilMs!);
      final start =
          until.subtract(const Duration(days: SubscriptionStore.durationDays));
      await SubscriptionStore.renew(at: start, ownerId: u.id);
      // An ALREADY-ELAPSED cycle must stay expired: renew() flips the status
      // back to 'active' unconditionally, which would silently un-paywall a
      // pro whose 30 days are over. Restore the truthful 'expired' state -
      // derived from THIS pro's own stamp, never from the session notifier.
      if (SubscriptionStore.isCycleOver(start, DateTime.now())) {
        await SubscriptionStore.expire();
      }
    } else if (entry.isPaid) {
      // Legacy granted flag without an expiry timestamp -> preserve the cycle
      // ONLY when its ownership is validated for THIS account. A cycle left
      // behind by a previous session on this device (the admin's own, or
      // another pro) is never inherited: it belongs to that account, not to the
      // pro logging in now. See [SubscriptionStore.markPaidPreservingCycle].
      //
      // The opt-in below is the EXPLICIT owner validation guard required for
      // UNOWNED/legacy cycles: [entry] was matched to this session by
      // [entryForUser] (PRO code / account id) and carries the paid stamp, so
      // the registry - the authoritative source - confirms this account owns
      // the granted access. Without it the guard refuses and seeds a fresh
      // cycle rather than inheriting unattributed time.
      await SubscriptionStore.markPaidPreservingCycle(
        ownerId: u.id,
        adoptUnownedLegacyCycle: true,
      );
    } else {
      // Trial: this pro owns NO paid cycle, so the session must show the clean
      // trial defaults. Any leftover 'expired' status is deliberately
      // discarded: 'expired' is only ever derived from the CURRENT pro's own
      // paid stamp (branch above), so a foreign session can never leak a
      // paywall into this one.
      await SubscriptionStore.reset();
    }
    await SubscriptionStore.persistToPrefs();

    // Tokens: mirror the registry balance into the session store.
    if (ProProfileStore.tokens.value != entry.tokens) {
      ProProfileStore.tokens.value = entry.tokens;
      await ProProfileStore.persistToPrefs();
    }

    // Verification: the registry is authoritative. If the admin approved or
    // re-queued the account since the session snapshot was saved, the live
    // session follows immediately (no re-login required).
    final approved = entry.status == 'approved';
    if (approved && !u.verificationStatus.isApproved) {
      await UserStore.updateProVerification(
        status: ProVerification.approved,
        proofPath: entry.docImage,
      );
    } else if (!approved &&
        u.verificationStatus.isApproved &&
        (entry.status == 'pending' || entry.status == 'rejected')) {
      await UserStore.updateProVerification(
        status: entry.status == 'rejected'
            ? ProVerification.rejected
            : ProVerification.pending,
      );
    }

    // SERVER AUTHORITY — LAST WORD (pro pending-approval routing). The local
    // mirrors above may only REFLECT the registry; whether this professional
    // may open the dashboard is decided by the SERVER's
    // `public.professionals.is_verified`, read AFTER every local mirror so a
    // stale local or registry "approved" can never win over the server — and
    // so an unresolved answer fails closed (no dashboard from local state
    // alone).
    await _applyServerVerificationAuthority();
  }

  /// Server-authoritative approval state for the CURRENT professional session.
  ///
  /// Contract (see [ProfileRepository.fetchOwnProfessionalStatus]):
  ///  * Supabase not initialized (local demo builds / tests): there IS no
  ///    server — the existing local behavior stands, unchanged;
  ///  * `status == 'approved'` → the session is (re)opened as approved — the
  ///    server can lift a stale local pending/rejected state;
  ///  * `status == 'rejected'` → the session follows the server into
  ///    [ProVerification.rejected], persisting `rejection_reason` (a server
  ///    rejection with NO reason STRIPS any stale local text instead of
  ///    inheriting it through the copyWith merge);
  ///  * `status == 'pending'` → the session is gated as pending, demoting a
  ///    stale local approved;
  ///  * TRANSIENT FAILURE (`statusMap == null` — network / timeout / RLS /
  ///    unconfigured): the current status is PRESERVED and the session is
  ///    flagged `verificationUnconfirmed = true`; the VerifyingScreen
  ///    retries non-blockingly (Phase 7-5). The status is NEVER downgraded
  ///    on a transient failure.
  ///  * SERVER ANOMALY (`statusMap` exists but 'status' is null or
  ///    unknown): we still fail CLOSED to 'pending' — the server responded
  ///    but with unexpected data, and guessing 'approved' would be unsafe.
  ///
  /// Never throws: an unreachable backend degrades to FAIL CLOSED.
  ///
  /// REGISTRY HYDRATION (Phase 2 · Step 6b): on top of syncing the SESSION,
  /// an existing server row whose dossier is missing from the LOCAL registry
  /// (cleared app data / brand-new device) seeds a local `PendingProModel`
  /// mirror for ALL THREE statuses — without it, `entryForUser` resolves
  /// null on such a device and the verification gate refuses the proof
  /// re-submission BEFORE `resubmitProof` (and its server-side RPC) is ever
  /// reached, leaving the server stuck on 'rejected'. Fail-closed on an
  /// unresolved read; idempotent on repeat logins.
  static Future<void> _applyServerVerificationAuthority() async {
    if (!SupabaseAuthService.isConfigured) return;
    final u = UserStore.user.value;
    if (u == null || !u.isProfessional) return;
    final statusMap = await ProfileRepository.fetchOwnProfessionalStatus(
      id: SupabaseAuthService.currentUserId ?? '',
    );

    // The await may have interleaved with other session writes — re-read.
    final session = UserStore.user.value;
    if (session == null || !session.isProfessional) return;

    // Three-state parse of the server row. A CLEAR answer (approved /
    // rejected / pending) is authoritative. A transient read failure is
    // handled in the `else if` branch below (early return + unconfirmed
    // flag). A malformed row (statusMap exists but status missing or
    // unknown) fails CLOSED to pending — never approved.
    final rawStatus = statusMap?['status'];
    final ProVerification newStatus;
    if (rawStatus == 'approved') {
      newStatus = ProVerification.approved;
    } else if (rawStatus == 'rejected') {
      newStatus = ProVerification.rejected;
    } else if (rawStatus == 'pending') {
      newStatus = ProVerification.pending;
    } else if (statusMap == null) {
      // Phase 7-5 (P5b): TRANSIENT FAILURE (network / timeout / RLS /
      // unconfigured). Do NOT downgrade — flag unconfirmed and let the
      // VerificationSyncService retry non-blockingly.
      await UserStore.markVerificationUnconfirmed();
      return; // no further processing on a failed read
    } else {
      // SERVER ANOMALY (statusMap exists but rawStatus is null or
      // unknown). This is NOT a network issue — the server explicitly
      // returned a row. Fail-closed to pending (safer than guessing).
      newStatus = session.verificationStatus.isRejected
          ? ProVerification.rejected
          : ProVerification.pending;
    }

    // Phase 7-5 (P5b): we have a CLEAR server answer — mark the audit
    // confirmed (unconfirmed=false) and stamp the timestamp.
    await UserStore.markVerificationConfirmed();

    // Refresh the persisted reason only on an EXPLICIT server rejection:
    // the fail-closed branch above can map to `rejected` solely when the
    // session already holds it (no status change), and that path has no
    // server row — it must never strip the local reason on a failed read.
    final reasonRaw = statusMap?['rejection_reason'];
    final serverReason = reasonRaw is String ? reasonRaw : null;
    final reasonChanged = statusMap != null &&
        rawStatus == 'rejected' &&
        serverReason != session.rejectionReason;

    if (newStatus != session.verificationStatus || reasonChanged) {
      if (newStatus == ProVerification.rejected) {
        // Mirrored into BOTH the session and the credential record by
        // updateProVerification, so the reason survives sign-out → sign-in
        // and restarts. clearReason strips a stale local text when the
        // server carries none.
        await UserStore.updateProVerification(
          status: newStatus,
          reason: serverReason,
          clearReason: serverReason == null,
        );
      } else {
        await UserStore.updateProVerification(status: newStatus);
      }
    }

    // ── REGISTRY HYDRATION (Phase 2 · Step 6b) ─────────────────────────────
    // A returning professional can land on a device whose local registry
    // never held their dossier (cleared app data, brand-new phone). Without a
    // local entry, `entryForUser` resolves null and the verification gate
    // refuses the proof re-submission BEFORE `resubmitProof` — and therefore
    // BEFORE the server-side `professional_resubmit_own_proof()` RPC — is
    // ever reached: the server then stays 'rejected' forever. The SAME
    // server row read above therefore seeds a local mirror for ALL THREE
    // statuses (the gate needs the entry to exist even while rejected).
    //
    // FAIL-CLOSED: an unresolved server read (`statusMap == null`) creates
    // NOTHING — a local guess must never fabricate a dossier.
    // IDEMPOTENT: `entryForUser` is checked after the awaits resolved and
    // re-checked with NO await before the insert, so repeated logins can
    // never duplicate the entry, overwrite an existing one, or touch the
    // demo seed (its ids/proCodes never match this session).
    final hydratedSession = UserStore.user.value;
    final hydratedId = hydratedSession?.id.trim() ?? '';
    final hydratedCode = (hydratedSession?.proCode ?? '').trim();
    if (statusMap != null &&
        hydratedSession != null &&
        hydratedSession.isProfessional &&
        // Identifier guard (mirrors `entryForUser`): at least one non-empty
        // side is required — an identifier-less session owns no dossier.
        (hydratedId.isNotEmpty || hydratedCode.isNotEmpty) &&
        entryForUser(hydratedSession) == null) {
      final specialtyRaw = statusMap['specialty'];
      final specialty = specialtyRaw is String ? specialtyRaw.trim() : '';
      final bioRaw = statusMap['bio'];
      final hydrated = PendingProModel(
        // The SAME identity `entryForUser` matches on: the trimmed session
        // id (legacy fallback path) plus the session PRO code — BOTH lookup
        // paths therefore find this entry on the very next sync.
        id: hydratedId,
        name: hydratedSession.name,
        phone: hydratedSession.phone,
        email: hydratedSession.email,
        // The server stores ONE specialty label — mirrored into both
        // required language slots (empty → '').
        professionFr: specialty,
        professionAr: specialty,
        description:
            bioRaw is String && bioRaw.trim().isNotEmpty ? bioRaw.trim() : null,
        city: hydratedSession.governorateAr ?? hydratedSession.governorateFr,
        submittedAt: _todayLabel(),
        // Server truth, already parsed fail-closed into [newStatus] above.
        status: newStatus.name,
        rejectionReason:
            newStatus == ProVerification.rejected ? serverReason : null,
        proCode: hydratedSession.proCode,
        authUid: _uuidOrNull(hydratedSession.id),
        // The device-local proof path is NOT stored server-side.
        docImage: null,
      );
      // Re-read after the awaits above: insert ONLY if the session is still a
      // professional with no dossier (no await between check and mutation).
      final stillSession = UserStore.user.value;
      if (stillSession != null &&
          stillSession.isProfessional &&
          entryForUser(stillSession) == null) {
        pendingPros.value = [hydrated, ...pendingPros.value];
        await persistToPrefs();
      }
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

  /// Phase 4C: hydrate the client-facing registry from Supabase.
  /// Merges approved pros into pendingPros. Idempotent (updates in place).
  /// Returns count synced.
  static Future<int> hydrateApprovedProsFromSupabase() async {
    if (!SupabaseAuthService.isConfigured) return 0;
    if (SupabaseAuthService.currentUserId == null) return 0;
    try {
      final answer =
          await Supabase.instance.client.rpc('list_approved_professionals');
      if (answer is! List) return 0;

      final existing = List<PendingProModel>.from(pendingPros.value);
      final byId = <String, int>{
        for (var i = 0; i < existing.length; i++) existing[i].id: i,
      };

      var synced = 0;
      for (final raw in answer) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final id = (row['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;

        final specialty = (row['specialty'] as String?)?.trim() ?? '';
        final bio = (row['bio'] as String?)?.trim() ?? '';
        final name = (row['name'] as String?)?.trim() ?? '';
        final phone = (row['phone'] as String?)?.trim() ?? '';
        final email = (row['email'] as String?)?.trim();
        final categoryId = (row['category_id'] as String?)?.trim();

        final serviceIdsRaw = row['service_ids'];
        final serviceIds = serviceIdsRaw is List
            ? serviceIdsRaw.whereType<String>().toList(growable: false)
            : const <String>[];

        final workImagesRaw = row['work_images'];
        final galleryPhotos = workImagesRaw is List
            ? workImagesRaw.whereType<String>().toList(growable: false)
            : const <String>[];

        final badgesRaw = row['badges'];
        final badges = badgesRaw is List
            ? badgesRaw.whereType<String>().toList(growable: false)
            : const <String>[];

        final pricingType = (row['pricing_type'] as String?)?.trim();
        final priceFromRaw = row['price_from'];
        final priceFrom = priceFromRaw is num ? priceFromRaw.toInt() : null;

        // Phase 4D: server-computed aggregates (tolerant — missing → 0.0/0).
        final ratingRaw = row['rating'];
        final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;
        final reviewCountRaw = row['review_count'];
        final reviewCount = reviewCountRaw is num ? reviewCountRaw.toInt() : 0;

        // Phase 4G: parse zones from the server (badges already parsed above).
        final zonesRaw = row['zones'];
        final zones = zonesRaw is List
            ? zonesRaw.whereType<String>().toList(growable: false)
            : const <String>[];

        final model = PendingProModel(
          id: id,
          name: name,
          phone: phone,
          email: (email != null && email.isNotEmpty) ? email : null,
          professionFr: specialty,
          professionAr: specialty,
          submittedAt: _todayLabel(),
          status: 'approved',
          authUid: _uuidOrNull(id),
          categoryId: categoryId,
          serviceIds: serviceIds,
          galleryPhotos: galleryPhotos,
          badges: badges,
          zones: zones,
          // Phase 4G: derive city from the first zone (backward-compat with
          // the city-based live getter).
          city: zones.isNotEmpty ? zones.first : null,
          description: bio,
          pricingType: pricingType,
          priceFrom: priceFrom,
          rating: rating,
          reviewCount: reviewCount,
        );

        final idx = byId[id];
        if (idx == null) {
          existing.add(model);
          byId[id] = existing.length - 1;
        } else {
          existing[idx] = model;
        }
        synced++;
      }

      pendingPros.value = existing;
      await persistToPrefs();
      return synced;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'AdminStore.hydrateApprovedProsFromSupabase',
      );
      return 0;
    }
  }
}
