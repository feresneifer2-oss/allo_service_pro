import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/request_status.dart';
import '../../../core/error/app_error_handler.dart';
import '../../professionals/data/professionals_repository.dart';
import '../models/service_request.dart';

/// Supabase gateway for the live `orders` table (Phase 3L rich schema).
///
/// MAPPING CONTRACT (LIVE `public.orders` columns ↔ [ServiceRequest]):
///   id (uuid)             ← [ServiceRequest.id] (a client-generated v4 UUID
///                           kept as the primary key so offline-created
///                           orders reconcile with the remote row 1:1);
///   client_id (uuid)      ← [ServiceRequest.customerId] (the authenticated
///                           customer UUID bound from `UserStore`, live
///                           session as fallback — see `_clientId`);
///   pro_id (uuid)         ← [ServiceRequest.professionalAuthUid] — NEVER the
///                           display id; a null uid is refused BEFORE any
///                           network write (mock/legacy pros stay local);
///   status (text)         ← [RequestStatus] (snake_case: en_route, in_progress)
///   description           ← [ServiceRequest.message]
///   created_at (timestamptz) ← [ServiceRequest.createdAt]
///   service_title_fr/ar   ← [ServiceRequest.serviceTitleFr/Ar]
///   client_name           ← [ServiceRequest.customerName]
///   pro_name              ← [ServiceRequest.professionalName]
///   scheduled_at (timestamptz) ← [ServiceRequest.dateTime]
///   address               ← [ServiceRequest.address]
///   photo_paths (jsonb)   ← [ServiceRequest.photoPaths]
///   rating / review_comment ← [ServiceRequest.rating/ReviewComment] (only
///                           when non-null — both columns are nullable);
///   payment_method        ← [ServiceRequest.paymentMethod]
///   updated_at (timestamptz, server default) → NOT sent: this layer does
///                           not manage it (the UPDATE patch never carries it).
///
/// LEGACY COLUMNS ARE NEVER READ OR WRITTEN: `customer_id`, `customer_name`,
/// `professional_id`, `professional_name`, `message` do not exist on the live
/// schema (the table was born empty in Phase 3H — no legacy rows exist).
///
/// HYDRATION: `fromRow` decodes `pro_id` into
/// [ServiceRequest.professionalAuthUid]; the display/routing
/// [ServiceRequest.professionalId] is resolved from the local professional
/// registry (`ProfessionalsRepository`) and stays EMPTY when unknown — a
/// proCode is never fabricated from the UUID.
///
/// FAILURE POLICY: every call is failure-tolerant (logged, never thrown into
/// the UI layer) and a no-op when Supabase is not initialized (tests /
/// offline demo builds) — the in-memory store remains the single source of
/// truth for the UI, the network is an eventually-consistent mirror.
/// Outcome of a single `orders` INSERT attempt.
///
/// The REASON matters (CodeRabbit): [duplicateId] is RECOVERABLE — the row is
/// rejected only because that primary key is already taken, so the caller can
/// re-key the order and retry — while [failed] (RLS / constraint / transport)
/// and [notConfigured] are not.
/// Phase 7-2c-4: server-side trigger refused (pro is offline).
/// Permanent refusal — do NOT retry / enqueue.
enum OrderInsertOutcome {
  inserted,
  duplicateId,
  failed,
  notConfigured,
  proUnavailable,
}

// ─── Duplicate-INSERT verification (CodeRabbit) ─────────────────────────────

/// WHY a duplicate-INSERT verification did not confirm ownership.
///
/// The reason is tracked EXPLICITLY so a re-key attempt can never mask or
/// override a genuine failure:
///   • [OrderVerification.verifiedSameOrder] — the remote row exists and its
///     identity footprint matches the local order (safe to adopt, no re-key);
///   • [OrderVerification.rowMissing] — the backend has no row under this id
///     (the INSERT never landed — re-key + retry is meaningful);
///   • [OrderVerification.dataMismatch] — a row exists but fails the
///     schema/identity checks (NOT this order — the id is taken, re-key is
///     the only path);
///   • [OrderVerification.inconclusiveTransport] — the verification READ
///     itself failed (network/auth hiccup) or no backend is configured: the
///     outcome is AMBIGUOUS and must not trigger a destructive re-key.
enum OrderVerification {
  verifiedSameOrder,
  rowMissing,
  dataMismatch,
  inconclusiveTransport,
}

/// Result of [OrdersRepository.verifyOrderRow] — carries the parsed remote
/// order ONLY when the verification positively identified it as the same
/// request.
class OrderVerificationResult {
  const OrderVerificationResult(this.outcome, {this.order});
  final OrderVerification outcome;

  /// Non-null exclusively for [OrderVerification.verifiedSameOrder].
  final ServiceRequest? order;
}

class OrdersRepository {
  OrdersRepository._();

  static const String _table = 'orders';

  /// Postgres SQLSTATE for a UNIQUE / PRIMARY-KEY violation.
  static const String _uniqueViolation = '23505';

  /// SQLSTATE raised by the orders availability trigger (Phase 7A).
  static const String _proUnavailable = 'P0001';

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ID of the CURRENTLY authenticated Supabase user (null when the client is
  /// not initialized / not signed in — tests and local-only builds).
  static String? currentAuthUserId() {
    try {
      final id = Supabase.instance.client.auth.currentUser?.id;
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// CROSS-ACCOUNT ADOPTION GUARD (CodeRabbit): a remote row may only be
  /// merged into local state when it provably belongs to the CURRENTLY
  /// authenticated user — the live `client_id` OR `pro_id` ownership stamp
  /// must match the auth identity. Rows that carry no ownership stamps at
  /// all are refused (strict mode): they cannot be tied to this account,
  /// and merging them would leak another account's data into this device's
  /// store.
  ///
  /// Phase 3L: the legacy `customer_id` / `professional_id` columns do not
  /// exist on the live schema and are NEVER consulted — a row carrying only
  /// those legacy stamps belongs to no one here.
  ///
  /// Returns true when the row is safe to adopt.
  static bool rowBelongsToCurrentUser(Map<String, dynamic> row) {
    final uid = currentAuthUserId();
    if (uid == null) return true; // no verifiable identity → RLS governs
    return ownershipStampsMatch(row, uid);
  }

  /// Whether [row]'s live ownership stamps (`client_id` / `pro_id`) name
  /// [uid]. Extracted so the ownership rule stays unit-testable without a
  /// signed-in Supabase session (Phase 3L).
  @visibleForTesting
  static bool ownershipStampsMatch(Map<String, dynamic> row, String uid) {
    final clientId = ((row['client_id'] as String?) ?? '').trim();
    final proId = ((row['pro_id'] as String?) ?? '').trim();
    return clientId == uid || proId == uid;
  }

  // ─── enum ↔ wire mapping ──────────────────────────────────────────────
  static String statusToWire(RequestStatus s) {
    switch (s) {
      case RequestStatus.enRoute:
        return 'en_route';
      case RequestStatus.arrived:
        return 'arrived';
      case RequestStatus.inProgress:
        return 'in_progress';
      default:
        return s.name; // pending, accepted, refused, completed, cancelled
    }
  }

  static RequestStatus? statusFromWire(Object? raw) {
    if (raw is! String) return null;
    switch (raw) {
      case 'en_route':
        return RequestStatus.enRoute;
      case 'arrived':
        // ARRIVED (CodeRabbit): the wire value was previously unmapped, so a
        // remote row parked on `arrived` deserialized to null (and the order
        // fell back to `pending`) — desynchronizing the two devices exactly
        // at the pro-on-site transition.
        return RequestStatus.arrived;
      case 'in_progress':
        return RequestStatus.inProgress;
      case 'pending':
        return RequestStatus.pending;
      case 'accepted':
        return RequestStatus.accepted;
      case 'refused':
        return RequestStatus.refused;
      case 'completed':
        return RequestStatus.completed;
      case 'cancelled':
        return RequestStatus.cancelled;
      default:
        return null;
    }
  }

  /// Builds the INSERT payload for the LIVE `orders` schema — ONLY columns
  /// that actually exist on it (Phase 3L). The offline queue serializes this
  /// exact map, so a replayed INSERT is byte-identical to the original
  /// attempt.
  ///
  /// `pro_id` is emitted even when null: the value travels on the queued
  /// payload, and [insertOrderDetailed] refuses the write BEFORE any network
  /// round-trip when it is missing (a mock/legacy professional has no
  /// Supabase identity — it is never invented here).
  static Map<String, dynamic> toRow(ServiceRequest r) => <String, dynamic>{
        'id': r.id,
        'client_id': _clientId(r),
        'pro_id': r.professionalAuthUid,
        'status': statusToWire(r.status),
        'description': r.message,
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'service_title_fr': r.serviceTitleFr,
        'service_title_ar': r.serviceTitleAr,
        'client_name': r.customerName,
        'pro_name': r.professionalName,
        'scheduled_at': r.dateTime.toUtc().toIso8601String(),
        'address': r.address,
        'photo_paths': r.photoPaths,
        if (r.rating != null) 'rating': r.rating,
        if (r.reviewComment != null) 'review_comment': r.reviewComment,
        'payment_method': r.paymentMethod,
      };

  /// `client_id` (uuid NOT NULL): the AUTHENTICATED customer's UUID. The
  /// model carries it from `UserStore` (whose `id` binds to the Supabase
  /// user UUID on sign-in — both creation screens store it at draft time);
  /// the live session is the fallback for a draft created before that bind.
  /// An empty result is rejected by Postgres as an invalid uuid — this layer
  /// never invents an identifier.
  static String _clientId(ServiceRequest r) {
    final fromModel = r.customerId.trim();
    if (fromModel.isNotEmpty) return fromModel;
    return currentAuthUserId() ?? '';
  }

  static ServiceRequest? fromRow(Map<String, dynamic> row) {
    try {
      final id = row['id'];
      final status = statusFromWire(row['status']) ?? RequestStatus.pending;
      final scheduled = _parseDate(row['scheduled_at']) ?? DateTime.now();
      final createdAt = _parseDate(row['created_at']) ?? scheduled;
      if (id is! String || id.isEmpty) return null;
      // Phase 3L: `pro_id` IS the professional's Supabase identity; the
      // display/routing id is resolved from the local registry and stays
      // empty when unknown — a proCode is never fabricated from a UUID.
      final proAuthUid = ((row['pro_id'] as String?) ?? '').trim();
      return ServiceRequest(
        id: id,
        serviceTitleFr: (row['service_title_fr'] as String?) ?? '',
        serviceTitleAr: (row['service_title_ar'] as String?) ?? '',
        professionalId:
            _displayIdForAuthUid(proAuthUid.isEmpty ? null : proAuthUid),
        professionalAuthUid: proAuthUid.isEmpty ? null : proAuthUid,
        professionalName: (row['pro_name'] as String?) ?? '',
        customerId: (row['client_id'] as String?) ?? '',
        customerName: (row['client_name'] as String?) ?? '',
        dateTime: scheduled,
        address: (row['address'] as String?) ?? '',
        message: (row['description'] as String?) ?? '',
        paymentMethod: (row['payment_method'] as String?) ?? 'cash',
        photoPaths: [
          for (final p in (row['photo_paths'] as List? ?? [])) p as String,
        ],
        status: status,
        rating: (row['rating'] as num?)?.toDouble(),
        reviewComment: row['review_comment'] as String?,
        createdAt: createdAt,
      );
    } catch (e) {
      debugPrint('OrdersRepository.fromRow: malformed row skipped: $e');
      return null;
    }
  }

  /// Display/routing id ([ServiceRequest.professionalId]) of the professional
  /// authenticated as [uid]: resolved from the LOCAL registry — the only
  /// place a `PRO-XXXXX` / `pro_N` display id still exists after Phase 3L
  /// dropped the legacy `professional_id` column. Returns '' when the
  /// registry does not know the uid: a proCode is NEVER fabricated from the
  /// UUID, and a mock pro (null authUid) resolves to nothing.
  static String _displayIdForAuthUid(String? uid) {
    if (uid == null || uid.isEmpty) return '';
    try {
      for (final p in ProfessionalsRepository.all) {
        if (p.authUid == uid) return p.id;
      }
    } catch (e, st) {
      AppErrorHandler.report(e, st,
          context: 'OrdersRepository._displayIdForAuthUid');
    }
    return '';
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  // ─── operations ───────────────────────────────────────────────────────

  /// INSERT of a locally created order, reporting WHY it failed.
  ///
  /// A duplicate primary key is the ONE recoverable refusal (CodeRabbit): the
  /// id is already taken, so the caller re-keys the order and retries instead
  /// of dropping the work. Every other failure (RLS refusal, constraint,
  /// transport) is reported as [OrderInsertOutcome.failed].
  ///
  /// Phase 3L — `pro_id` GUARD: an order whose professional carries no
  /// Supabase auth uid (mock catalog pro / legacy draft) can never satisfy
  /// the uuid `pro_id` column. The refusal happens BEFORE any backend work —
  /// no network write is attempted, nothing is derived from `professionalId`
  /// (`pro_N` / `PRO-XXXXX` are not uuids) — and the existing [OrderInsertOutcome.failed]
  /// outcome is returned so callers keep their retry/local-only handling.
  static Future<OrderInsertOutcome> insertOrderDetailed(
      ServiceRequest request) async {
    if ((request.professionalAuthUid ?? '').trim().isEmpty) {
      AppErrorHandler.report(
        StateError('orders INSERT refused for "${request.id}": no '
            'professional auth uid (professionalId="${request.professionalId}")'),
        StackTrace.current,
        context: 'OrdersRepository.insertOrder',
      );
      return OrderInsertOutcome.failed;
    }
    if (!isConfigured) return OrderInsertOutcome.notConfigured;
    try {
      await Supabase.instance.client.from(_table).insert(toRow(request));
      return OrderInsertOutcome.inserted;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.insertOrder');
      if (isProUnavailable(e)) return OrderInsertOutcome.proUnavailable;
      if (isDuplicateKey(e)) return OrderInsertOutcome.duplicateId;
      return OrderInsertOutcome.failed;
    }
  }

  /// INSERT of a locally created order. Row-level security scopes the write
  /// to the authenticated identity; a failure here is logged (the local
  /// order already exists — the OfflineQueue covers true offline cases).
  ///
  /// Boolean façade over [insertOrderDetailed]: every existing caller / test
  /// contract is unchanged.
  static Future<bool> insertOrder(ServiceRequest request) async =>
      await insertOrderDetailed(request) == OrderInsertOutcome.inserted;

  /// True when [error] is a Postgres UNIQUE / PRIMARY-KEY violation
  /// (SQLSTATE `23505`), i.e. this id already exists on the backend.
  static bool isDuplicateKey(Object error) {
    if (error is PostgrestException) {
      if (error.code == _uniqueViolation) return true;
      // Some deployments surface the SQLSTATE in the message only.
      return error.message.contains(_uniqueViolation);
    }
    return error.toString().contains(_uniqueViolation);
  }

  /// Phase 7-2c-4: true when the error is the availability gate refusal
  /// (SQLSTATE P0001 with message 'pro_unavailable'). Mirrors the
  /// isDuplicateKey pattern (code → message fallback).
  static bool isProUnavailable(Object error) {
    if (error is PostgrestException) {
      if (error.code == _proUnavailable) {
        return error.message.contains('pro_unavailable');
      }
      return error.message.contains('pro_unavailable');
    }
    return error.toString().contains('pro_unavailable');
  }

  /// SELECT of a single order by primary key (RLS scopes the read).
  ///
  /// Returns null when the row does not exist OR the read failed (the caller
  /// treats "unverifiable" conservatively). Used by RequestStore to VERIFY a
  /// duplicate-INSERT outcome before re-keying: a reachable row under the same
  /// id means the order already mirrored — never mint a second one.
  static Future<ServiceRequest?> fetchOrderById(String id) async {
    if (!isConfigured) return null;
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('id', id)
          .limit(1);
      for (final row in (rows as List)) {
        return fromRow((row as Map).cast<String, dynamic>());
      }
      return null;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.fetchOrderById');
      return null;
    }
  }

  // ─── Duplicate-INSERT verification (CodeRabbit) ─────────────────────────

  /// STRICT schema gate (CodeRabbit): a remote row may replace local state
  /// only when it carries the mandatory fields with VALID values — a real id,
  /// a recognized status wire string, parsable timestamps, and BOTH live
  /// ownership stamps (`client_id` and `pro_id` are uuid NOT NULL on the
  /// schema — a row missing either cannot exist upstream). Lenient parsing
  /// ([fromRow]) stays for display paths; the legacy `customer_id` /
  /// `professional_id` columns are never consulted (Phase 3L).
  static bool isValidRow(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is! String || id.isEmpty) return false;
    if (statusFromWire(row['status']) == null) return false;
    if (_parseDate(row['scheduled_at']) == null) return false;
    if (_parseDate(row['created_at']) == null) return false;
    final clientId = (row['client_id'] as String?)?.trim() ?? '';
    final proId = (row['pro_id'] as String?)?.trim() ?? '';
    if (clientId.isEmpty || proId.isEmpty) return false;
    return true;
  }

  /// Identity-footprint match between a remote row and the local order it
  /// claims to be: compares STABLE, immutable identifiers — the exact id, the
  /// immutable `client_id` (or its empty-compatible fallback), the `pro_id`
  /// professional stamp (Phase 3L) and the `created_at` instant — NOT
  /// volatile mutable fields like status or address (CodeRabbit: a row whose
  /// mutable fields drifted is still the SAME order, but a row under a
  /// foreign id / client / pro / timestamp is NOT, even if
  /// coincidence-aligned service/title fields happen to match).
  static bool _sameOrderFootprint(ServiceRequest a, ServiceRequest b) {
    String norm(String s) => s.trim().toLowerCase();

    // Immutable primary + ownership + birth instant. Empty fields on the
    // legacy side cannot disprove identity, so they short-circuit to "compatible".
    bool stableIdMatch = norm(a.id) == norm(b.id);
    bool clientMatch = a.customerId.trim().isEmpty ||
        b.customerId.trim().isEmpty ||
        norm(a.customerId) == norm(b.customerId);
    // Phase 3L: the professional stamp joins the footprint — a row assigned
    // to ANOTHER pro can never be adopted as this order (legacy nulls stay
    // compatible: a uid neither side carries proves nothing).
    bool proMatch = (a.professionalAuthUid ?? '').trim().isEmpty ||
        (b.professionalAuthUid ?? '').trim().isEmpty ||
        norm(a.professionalAuthUid!) == norm(b.professionalAuthUid!);
    bool createdMatch = a.createdAt.isAtSameMomentAs(b.createdAt);
    return stableIdMatch && clientMatch && proMatch && createdMatch;
  }

  /// Verifies whether the backend row under [id] IS the local [expected]
  /// order — with the failure reason preserved (CodeRabbit).
  ///
  /// Never throws: a transport/auth failure degrades to
  /// [OrderVerification.inconclusiveTransport] (reported through
  /// [AppErrorHandler], not swallowed), so the caller can distinguish a
  /// transient read problem from a definitive data verdict.
  static Future<OrderVerificationResult> verifyOrderRow({
    required String id,
    required ServiceRequest expected,
  }) async {
    if (!isConfigured) {
      return const OrderVerificationResult(
          OrderVerification.inconclusiveTransport);
    }
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('id', id)
          .limit(1);
      if ((rows as List).isEmpty) {
        return const OrderVerificationResult(OrderVerification.rowMissing);
      }
      final raw = (rows.first as Map).cast<String, dynamic>();
      // STRICT payload validation BEFORE any adoption (CodeRabbit): a row
      // failing the schema is a data mismatch, never silently merged.
      if (!isValidRow(raw)) {
        return const OrderVerificationResult(OrderVerification.dataMismatch);
      }
      final parsed = fromRow(raw);
      if (parsed == null || !_sameOrderFootprint(parsed, expected)) {
        return const OrderVerificationResult(OrderVerification.dataMismatch);
      }
      // CROSS-ACCOUNT GUARD (CodeRabbit): even a footprint-matching row is
      // refused when its ownership stamps do not include the CURRENT auth
      // identity — adoption must never merge another account's order.
      if (!rowBelongsToCurrentUser(raw)) {
        return const OrderVerificationResult(OrderVerification.dataMismatch);
      }
      return OrderVerificationResult(OrderVerification.verifiedSameOrder,
          order: parsed);
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.verifyOrderRow');
      return const OrderVerificationResult(
          OrderVerification.inconclusiveTransport);
    }
  }

  /// UPDATE payload for the mutable order fields (status transition, review) —
  /// ONLY columns that exist on the live `orders` schema (Phase 3L).
  ///
  /// `updated_at` is intentionally ABSENT: this layer does not manage it
  /// (the column keeps its server default/trigger domain — added to the
  /// patch only if a later phase intentionally updates it).
  @visibleForTesting
  static Map<String, dynamic> updatePatch({
    RequestStatus? status,
    double? rating,
    String? reviewComment,
  }) =>
      <String, dynamic>{
        if (status != null) 'status': statusToWire(status),
        if (rating != null) 'rating': rating,
        if (reviewComment != null) 'review_comment': reviewComment,
      };

  /// UPDATE of the mutable order fields (status transition, review).
  ///
  /// Returns `true` ONLY when the backend confirms at least one row changed —
  /// a zero-row outcome (stale id, RLS-scoped-out, or the row was deleted
  /// mid-flight by another device) is a REAL write failure and is reported as
  /// `false` instead of being silently swallowed (CodeRabbit: "assume
  /// success" masked real update losses).
  static Future<bool> updateOrder(
    String id, {
    RequestStatus? status,
    double? rating,
    String? reviewComment,
  }) async {
    if (!isConfigured) return false;
    final patch = updatePatch(
      status: status,
      rating: rating,
      reviewComment: reviewComment,
    );
    if (patch.isEmpty) return true;
    try {
      // Inspect the affected-row count: Supabase's `update(...).eq(...)` returns
      // the modified rows; an empty result means NOTHING matched this id under
      // the current RLS scope — a domain-specific update failure, not a transport
      // error, so it is reported distinctly and never assumed successful.
      final res = await Supabase.instance.client
          .from(_table)
          .update(patch)
          .eq('id', id)
          .select() as List<dynamic>;
      if (res.isEmpty) {
        // No row matched — the order was not updated.
        debugPrint(
            'OrdersRepository.updateOrder: no row affected for id="$id".');
        return false;
      }
      return true;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.updateOrder');
      return false;
    }
  }

  /// Atomic server-side accept: the pro_accept_order RPC performs BOTH the
  /// token deduction (if not paid) AND the pending→accepted transition.
  /// Returns the NEW token balance (int) on success, null on any refusal
  /// (insufficient tokens / not owner / wrong status / offline / unconfigured).
  static Future<int?> acceptOrderWithFee(String orderId) async {
    if (!isConfigured) return null;
    if (orderId.trim().isEmpty) return null;
    if (currentAuthUserId() == null) return null;
    try {
      final answer = await Supabase.instance.client.rpc(
        'pro_accept_order',
        params: <String, dynamic>{'p_order_id': orderId.trim()},
      );
      if (answer is int) return answer;
      if (answer is num) return answer.toInt();
      return null;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'OrdersRepository.acceptOrderWithFee',
      );
      return null;
    }
  }

  /// SELECT of every order visible to the current identity (RLS scopes the
  /// result). Ordered newest-first to match the local list convention.
  static Future<List<ServiceRequest>> fetchOrders() async {
    if (!isConfigured) return const [];
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      final orders = <ServiceRequest>[];
      for (final row in (rows as List)) {
        final mapped = row as Map<String, dynamic>;
        // CROSS-ACCOUNT GUARD (CodeRabbit): rows not owned by the CURRENT
        // authenticated identity are never adopted into the local store —
        // the RLS policy is the primary defense, this is the client-side
        // second layer.
        if (!rowBelongsToCurrentUser(mapped)) continue;
        final parsed = fromRow(mapped);
        if (parsed != null) orders.add(parsed);
      }
      return orders;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.fetchOrders');
      return const [];
    }
  }
}
