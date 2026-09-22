import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/notifications/application/notification_store.dart';
import '../../features/requests/application/request_store.dart';
import '../../features/requests/models/service_request.dart';
import '../models/request_status.dart';

/// Client-side geo target for one order session.
class ProximityTarget {
  /// Client latitude / longitude (null when unknown — service aborts).
  final double? clientLat;
  final double? clientLng;

  /// Client identity for the push (customer id + optional display name).
  final String customerId;
  final String customerName;

  /// Order the target belongs to. Optional identity pin: when set, the
  /// service rejects targets resolved for a different request (Guard 5).
  final String? requestId;

  const ProximityTarget({
    required this.clientLat,
    required this.clientLng,
    required this.customerId,
    this.requestId,
    this.customerName = '',
  });

  /// Both coordinates present, in range, and not the (0, 0) null-island.
  bool get hasValidCoordinates =>
      clientLat != null &&
      clientLng != null &&
      clientLat!.isFinite &&
      clientLng!.isFinite &&
      clientLat! >= -90.0 &&
      clientLat! <= 90.0 &&
      clientLng! >= -180.0 &&
      clientLng! <= 180.0 &&
      (clientLat != 0.0 || clientLng != 0.0);
}

/// Resolves an order to its client geo target (null when unknown).
typedef ProximityTargetResolver = ProximityTarget? Function(
    ServiceRequest order);

/// Fires the arrival push for an order (injectable for tests).
typedef ProximityArrivalNotifier = Future<void> Function(
  ServiceRequest order,
  ProximityTarget target,
);

/// Computes meters between two WGS84 points (injectable for tests).
typedef ProximityDistanceCalculator = double Function(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
);

/// GPS proximity check + auto-arrival service for Allo Service Pro.
///
/// The pro app feeds live positions via [onProPosition]; when the pro gets
/// within [arrivalRadiusMeters] of the client's coordinates the service
/// flips the order to [RequestStatus.arrived] and fires the client push.
///
/// Everything is static + in-memory (matches the local-architecture
/// constraint): sessions reset via [reset]/[resetSession], so logout and
/// tests never leak state. Never throws — every entry point is guarded.
class ProximityService {
  ProximityService._();

  /// Arrival radius in meters (spec: <= 20 m triggers).
  static const double arrivalRadiusMeters = 20.0;

  /// Sessions already notified (exactly-once per order session).
  static final Set<String> _notifiedSessions = <String>{};

  /// Optional external target resolver (order id -> client lat/lng).
  ///
  /// The local [ServiceRequest] model carries no coordinates, so by default
  /// [_lookupTarget] yields null and [onProPosition] safely no-ops. Screens
  /// backed by a geo-aware model (or the Supabase layer later) inject a
  /// resolver via [debugSetTargetResolver]; tests inject fakes the same way.
  static ProximityTargetResolver? _targetResolver;

  /// Called on every provider position fix (e.g. geolocator stream).
  ///
  /// Resolves the order + client coordinates, applies the strict guard
  /// clauses, computes [Geolocator.distanceBetween], and triggers
  /// [notifyArrival] + status flip when within [arrivalRadiusMeters].
  /// Never throws.
  static Future<void> onProPosition({
    required String requestId,
    required double proLat,
    required double proLng,
  }) async {
    try {
      // Guard 0: the session id IS the dispatch identity — a blank id can
      // never address an order and would poison the retry ledger key
      // (`_notifyAttempts['']`), so it is rejected before anything else.
      if (requestId.trim().isEmpty) return;

      // Guard 0b: session already notified -> exactly-once. If the push
      // failed earlier, opportunistically retry it on this fresh fix
      // (bounded attempts) before returning. Retries re-validate their
      // inputs: a cancelled/completed order is never pushed, and the fresh
      // target must still be a well-formed payload for THIS order.
      if (_notifiedSessions.contains(requestId)) {
        if (_notifyAttempts.containsKey(requestId)) {
          final retryOrder = RequestStore.byId(requestId);
          if (retryOrder != null && !_isTerminal(retryOrder)) {
            final retryTarget = _lookupTarget(retryOrder);
            if (retryTarget != null) {
              await _dispatchArrival(retryOrder, retryTarget);
            }
          } else if (retryOrder != null) {
            // Terminal order: the queued retry can never be valid.
            _notifyAttempts.remove(requestId);
          }
        }
        return;
      }

      // Guard 1: resolve order; unknown id -> abort.
      final ServiceRequest? order = RequestStore.byId(requestId);
      if (order == null) return;

      // Guard 2 (CRUCIAL): terminal orders never trigger anything.
      // 'annulée' (cancelled) or 'terminée' (completed, manual or via
      // auto-expiration timer) -> abort immediately.
      if (_isTerminal(order)) return;

      // Guard 3: only live, accepted-side orders can auto-arrive.
      // (pending/refused have no trip; arrived/inProgress already arrived.)
      if (order.status != RequestStatus.accepted &&
          order.status != RequestStatus.enRoute) {
        return;
      }

      // Guard 4: client coordinates must exist and be valid.
      final target = _lookupTarget(order);
      if (target == null || !target.hasValidCoordinates) return;
      if (!_isValidCoordinate(proLat, proLng)) return;

      // Proximity check (< 20 m triggers).
      final distance = distanceBetweenMeters(
        proLat,
        proLng,
        target.clientLat!,
        target.clientLng!,
      );
      if (distance > arrivalRadiusMeters) return;

      // Arrival (commit-before-notify): persist the 'arrivé' status
      // FIRST, then latch + fire the outgoing notification.

      // Guard 5: verify target identity & live status immediately before
      // committing (TOCTOU protection). The order may have been cancelled,
      // completed or reassigned between the first lookup and this commit;
      // the resolved target must also belong to THIS order — never to a
      // different request, and never to the professional himself.
      final fresh = RequestStore.byId(requestId);
      if (fresh == null) return;
      if (fresh.status != RequestStatus.accepted &&
          fresh.status != RequestStatus.enRoute) {
        return;
      }
      // Guard 5b: validate the payload right before the commit + dispatch —
      // non-empty order/recipient ids, well-formed coordinates, and a target
      // that legally belongs to THIS order (order pin matches, and the push is
      // never addressed to the professional himself).
      if (!_isDispatchable(fresh, target)) return;

      final committed = await RequestStore.updateStatus(
        requestId,
        RequestStatus.arrived,
      );
      if (!committed) return;
      _notifiedSessions.add(requestId);
      // Notification failures never lose the committed status: the dispatch
      // result is queued for bounded retries on subsequent position fixes.
      await _dispatchArrival(fresh, target);
    } catch (e) {
      debugPrint('[Proximity] onProPosition failed (non-fatal): $e');
    }
  }

  /// Max notification delivery attempts before giving up on an order.
  static const int _maxNotifyAttempts = 3;

  /// Orders whose arrival notification failed and are awaiting retry.
  static final Map<String, int> _notifyAttempts = {};

  /// Dispatches the arrival notification with bounded retry accounting.
  /// Returns true when the notifier confirmed delivery.
  ///
  /// INPUT VALIDATION (defensive, applies to the FIRST attempt and to every
  /// RETRY alike): the payload must carry a non-empty order id, a non-empty
  /// recipient id, well-formed/organic coordinates, and — when pinned — a
  /// target that belongs to this very order. Anything else is refused before
  /// the notifier is reached.
  ///
  /// A refused dispatch is intentionally NOT written to the retry ledger:
  /// malformed input cannot be repaired by trying again, and an empty order
  /// id would corrupt the ledger key itself.
  static Future<bool> _dispatchArrival(
    ServiceRequest order,
    ProximityTarget target,
  ) async {
    if (!_isDispatchable(order, target)) {
      debugPrint(
        '[Proximity] arrival dispatch refused: malformed id/coordinates.',
      );
      return false;
    }
    final id = order.id;
    try {
      await _arrivalNotifier(order, target);
      _notifyAttempts.remove(id);
      return true;
    } catch (e) {
      final next = (_notifyAttempts[id] ?? 0) + 1;
      if (next < _maxNotifyAttempts) {
        _notifyAttempts[id] = next;
        debugPrint(
          '[Proximity] arrival notify failed; '
          'retry $next/$_maxNotifyAttempts queued: $e',
        );
      } else {
        _notifyAttempts.remove(id);
        debugPrint(
          '[Proximity] arrival notify failed; '
          'giving up after $next attempts: $e',
        );
      }
      return false;
    }
  }

  /// Fires the client arrival push as a pure OUTGOING trigger.
  ///
  /// The professional's device NEVER links to the customer identity:
  /// no login / session switch happens here. The default notifier only
  /// writes the role-routed in-app notification addressed to the client id
  /// (server-side OneSignal REST fan-out reads that id as a *target*, not
  /// as a local auth session). Injectable via [debugSetArrivalNotifier].
  /// Never throws; returns true when the notifier confirmed delivery —
  /// false results are queued for bounded retries (see [_dispatchArrival]).
  ///
  /// The payload is validated first (see [_isDispatchable]): a call carrying
  /// a blank order/recipient id or unverifiable coordinates returns false
  /// without ever reaching the notifier.
  static Future<bool> notifyArrival(
    ServiceRequest order,
    ProximityTarget target,
  ) =>
      _dispatchArrival(order, target);

  /// Default arrival notifier: local client notification ONLY.
  ///
  /// SECURITY: must never call OneSignalService.login() — the pro device
  /// must not adopt the customer identity. Any remote fan-out is an
  /// outgoing server-side trigger addressed TO the customer id.
  ///
  /// TRANSPORT: this is the local half of the arrival seam. The remote half
  /// lives in `NotificationStore` behind the documented `NotificationTransport`
  /// interface (production target: OneSignal) — see that class before adding
  /// any network call here.
  ///
  /// Defense in depth: the ids are re-checked here, right before the store
  /// write, so a notification can never be addressed to nobody even if a
  /// future caller bypasses [_dispatchArrival].
  static Future<void> _defaultArrivalNotifier(
    ServiceRequest order,
    ProximityTarget target,
  ) async {
    if (order.id.trim().isEmpty || target.customerId.trim().isEmpty) {
      debugPrint('[Proximity] default notifier skipped: blank id.');
      return;
    }
    final delivered = await NotificationStore.notifyProArrived(
      order.id,
      order.professionalName,
      target.customerId,
    );
    // NOTE: intentionally no OneSignalService.login() here — see above.
    if (!delivered) {
      // The local arrival is already committed, but the CUSTOMER's remote push
      // was refused or lost. Surface it to [_dispatchArrival]'s bounded-retry
      // ledger instead of reporting a success that never reached the client.
      throw StateError(
        '[Proximity] arrival remote transport failed for order ${order.id}',
      );
    }
  }

  static ProximityArrivalNotifier _arrivalNotifier = _defaultArrivalNotifier;

  /// Pure, injectable distance helper (defaults to the real geolocator
  /// implementation). Tests override via [debugSetDistanceCalculator].
  static double distanceBetweenMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) =>
      _distanceCalculator(startLat, startLng, endLat, endLng);

  static ProximityDistanceCalculator _distanceCalculator =
      Geolocator.distanceBetween;

  /// Whether [requestId] already fired its arrival notification.
  /// A blank id is not a session: it answers false (and never matches the
  /// ledger), so a malformed id can never appear "already notified".
  static bool hasNotified(String requestId) =>
      requestId.trim().isNotEmpty && _notifiedSessions.contains(requestId);

  /// Clears one session (e.g. order reopened by admin reset) — including any
  /// pending retry, which would otherwise linger as an orphan ledger entry.
  static void resetSession(String requestId) {
    _notifiedSessions.remove(requestId);
    _notifyAttempts.remove(requestId);
  }

  /// Clears all sessions (logout / test setup).
  static void reset() {
    _notifiedSessions.clear();
    _notifyAttempts.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static ProximityTarget? _lookupTarget(ServiceRequest order) =>
      _targetResolver?.call(order);

  static bool _isValidCoordinate(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90.0 &&
      lat <= 90.0 &&
      lng >= -180.0 &&
      lng <= 180.0 &&
      (lat != 0.0 || lng != 0.0);

  /// Terminal orders ('annulée' / 'terminée') must never trigger a dispatch —
  /// neither a first arrival nor a queued retry.
  static bool _isTerminal(ServiceRequest order) =>
      order.status == RequestStatus.cancelled ||
      order.status == RequestStatus.completed;

  /// True when [target] is a legally addressable payload for [order]:
  /// the optional order pin must match, and the target must never point at
  /// the professional himself (a self-addressed push is meaningless).
  static bool _belongsToOrder(ServiceRequest order, ProximityTarget target) {
    final orderId = order.id.trim();
    final pinned = target.requestId?.trim();
    if (pinned != null && pinned.isNotEmpty && pinned != orderId) {
      return false;
    }
    final recipient = target.customerId.trim();
    if (recipient.isNotEmpty && recipient == order.professionalId.trim()) {
      return false;
    }
    return true;
  }

  /// Validates a dispatch payload BEFORE any delivery or retry accounting.
  ///
  /// Refuses, in order: a blank order id (it keys the status commit and the
  /// retry ledger), a blank recipient id (a push addressed to nobody), a
  /// target whose coordinates are missing / non-finite / out of range / the
  /// null-island placeholder (see [ProximityTarget.hasValidCoordinates]), and
  /// a target that does not legally belong to [order].
  static bool _isDispatchable(ServiceRequest order, ProximityTarget target) =>
      order.id.trim().isNotEmpty &&
      target.customerId.trim().isNotEmpty &&
      target.hasValidCoordinates &&
      _belongsToOrder(order, target);

  /// Test hook: injects the order -> client-coordinate resolver.
  @visibleForTesting
  static void debugSetTargetResolver(ProximityTargetResolver? resolver) {
    _targetResolver = resolver;
  }

  /// Test hook: injects the arrival notifier (e.g. record calls, no plugin).
  @visibleForTesting
  static void debugSetArrivalNotifier(ProximityArrivalNotifier notifier) {
    _arrivalNotifier = notifier;
  }

  /// Test hook: restores the default arrival notifier.
  @visibleForTesting
  static void debugResetArrivalNotifier() {
    _arrivalNotifier = _defaultArrivalNotifier;
  }

  /// Test hook: injects a fake distance calculator.
  @visibleForTesting
  static void debugSetDistanceCalculator(ProximityDistanceCalculator fn) {
    _distanceCalculator = fn;
  }

  /// Test hook: restores the real geolocator distance calculator.
  @visibleForTesting
  static void debugResetDistanceCalculator() {
    _distanceCalculator = Geolocator.distanceBetween;
  }
}
