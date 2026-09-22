import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/request_status.dart';
import '../../../core/error/app_error_handler.dart';
import '../models/service_request.dart';

/// Supabase gateway for the live `orders` table.
///
/// MAPPING CONTRACT (`orders` columns ↔ [ServiceRequest]):
///   id (text pk)          ← [ServiceRequest.id] (locally generated id is
///                           kept as the primary key so offline-created
///                           orders reconcile with the remote row 1:1);
///   service_title_fr/ar   ← [ServiceRequest.serviceTitleFr/Ar]
///   professional_id/name  ← [ServiceRequest.professionalId/Name]
///   customer_id/name      ← [ServiceRequest.customerId/Name]
///   scheduled_at (timestamptz) ← [ServiceRequest.dateTime]
///   address, message      ← [ServiceRequest.address/Message]
///   payment_method        ← [ServiceRequest.paymentMethod]
///   photo_paths (jsonb)   ← [ServiceRequest.photoPaths]
///   status (text)         ← [RequestStatus] (snake_case: en_route, in_progress)
///   rating / review_comment ← [ServiceRequest.rating/ReviewComment]
///   created_at (timestamptz) ← [ServiceRequest.createdAt]
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
enum OrderInsertOutcome { inserted, duplicateId, failed, notConfigured }

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
  /// authenticated user — `customer_id` OR `professional_id` must match the
  /// auth identity. Rows that carry no ownership stamps at all are refused
  /// (strict mode): they cannot be tied to this account, and merging them
  /// would leak another account's data into this device's store.
  ///
  /// Returns true when the row is safe to adopt.
  static bool rowBelongsToCurrentUser(Map<String, dynamic> row) {
    final uid = currentAuthUserId();
    if (uid == null) return true; // no verifiable identity → RLS governs
    final customerId = ((row['customer_id'] as String?) ?? '').trim();
    final professionalId = ((row['professional_id'] as String?) ?? '').trim();
    return customerId == uid || professionalId == uid;
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

  static Map<String, dynamic> toRow(ServiceRequest r) => <String, dynamic>{
        'id': r.id,
        'service_title_fr': r.serviceTitleFr,
        'service_title_ar': r.serviceTitleAr,
        'professional_id': r.professionalId,
        'professional_name': r.professionalName,
        'customer_id': r.customerId,
        'customer_name': r.customerName,
        'scheduled_at': r.dateTime.toUtc().toIso8601String(),
        'address': r.address,
        'message': r.message,
        'payment_method': r.paymentMethod,
        'photo_paths': r.photoPaths,
        'status': statusToWire(r.status),
        if (r.rating != null) 'rating': r.rating,
        if (r.reviewComment != null) 'review_comment': r.reviewComment,
        'created_at': r.createdAt.toUtc().toIso8601String(),
      };

  static ServiceRequest? fromRow(Map<String, dynamic> row) {
    try {
      final id = row['id'];
      final status = statusFromWire(row['status']) ?? RequestStatus.pending;
      final scheduled = _parseDate(row['scheduled_at']) ?? DateTime.now();
      final createdAt = _parseDate(row['created_at']) ?? scheduled;
      if (id is! String || id.isEmpty) return null;
      return ServiceRequest(
        id: id,
        serviceTitleFr: (row['service_title_fr'] as String?) ?? '',
        serviceTitleAr: (row['service_title_ar'] as String?) ?? '',
        professionalId: (row['professional_id'] as String?) ?? '',
        professionalName: (row['professional_name'] as String?) ?? '',
        customerId: (row['customer_id'] as String?) ?? '',
        customerName: (row['customer_name'] as String?) ?? '',
        dateTime: scheduled,
        address: (row['address'] as String?) ?? '',
        message: (row['message'] as String?) ?? '',
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
  static Future<OrderInsertOutcome> insertOrderDetailed(
      ServiceRequest request) async {
    if (!isConfigured) return OrderInsertOutcome.notConfigured;
    try {
      await Supabase.instance.client.from(_table).insert(toRow(request));
      return OrderInsertOutcome.inserted;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'OrdersRepository.insertOrder');
      return isDuplicateKey(e)
          ? OrderInsertOutcome.duplicateId
          : OrderInsertOutcome.failed;
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
  /// a recognized status wire string, parsable timestamps, and at least one
  /// user association. Lenient parsing ([fromRow]) stays for display paths.
  static bool isValidRow(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is! String || id.isEmpty) return false;
    if (statusFromWire(row['status']) == null) return false;
    if (_parseDate(row['scheduled_at']) == null) return false;
    if (_parseDate(row['created_at']) == null) return false;
    final customerId = (row['customer_id'] as String?)?.trim() ?? '';
    final professionalId = (row['professional_id'] as String?)?.trim() ?? '';
    if (customerId.isEmpty && professionalId.isEmpty) return false;
    return true;
  }

  /// Identity-footprint match between a remote row and the local order it
  /// claims to be: compares STABLE, immutable identifiers — the exact id, the
  /// immutable `client_id` (or its empty-compatible fallback) and the
  /// `created_at` instant — NOT volatile mutable fields like status or address
  /// (CodeRabbit: a row whose mutable fields drifted is still the SAME order,
  /// but a row under a foreign id / client / timestamp is NOT, even if
  /// coincidence-aligned service/title fields happen to match).
  static bool _sameOrderFootprint(ServiceRequest a, ServiceRequest b) {
    String norm(String s) => s.trim().toLowerCase();

    // Immutable primary + ownership + birth instant. Empty fields on the
    // legacy side cannot disprove identity, so they short-circuit to "compatible".
    bool stableIdMatch = norm(a.id) == norm(b.id);
    bool clientMatch = a.customerId.trim().isEmpty ||
        b.customerId.trim().isEmpty ||
        norm(a.customerId) == norm(b.customerId);
    bool createdMatch = a.createdAt.isAtSameMomentAs(b.createdAt);
    return stableIdMatch && clientMatch && createdMatch;
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
    final patch = <String, dynamic>{
      if (status != null) 'status': statusToWire(status),
      if (rating != null) 'rating': rating,
      if (reviewComment != null) 'review_comment': reviewComment,
    };
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
