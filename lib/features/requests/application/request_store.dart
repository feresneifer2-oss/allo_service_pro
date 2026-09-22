import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../../../core/error/app_error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/request_status.dart';
import '../../../core/network/connectivity_store.dart';
import '../../../core/queue/offline_queue.dart';
import '../../../core/queue/queued_action.dart';
import '../../anti_abuse/application/anti_abuse_store.dart';
import '../../chat/application/chat_store.dart';
import '../../notifications/application/notification_store.dart';
import '../../pro_dashboard/application/pro_profile_store.dart';
import '../../pro_dashboard/application/subscription_store.dart';
import '../data/orders_repository.dart';

class RequestStore {
  RequestStore._();

  static final requests = ValueNotifier<List<ServiceRequest>>([]);

  /// Shared creation path (CodeRabbit): the local commit stays SYNCHRONOUS
  /// (offline-first, instant UI — every existing caller and test keeps its
  /// behaviour), then the Supabase mirror is AWAITED whenever the backend is
  /// configured. Online → a direct `orders` INSERT settles before the
  /// caller reports success; offline → local-only (the queue only supports
  /// status replays today, so creations are not enqueued).
  ///
  /// RETURNS the mirror outcome — the INSERT failure is no longer discarded:
  ///   • `true`  → durably handled: mirrored, or deliberately local-only
  ///               (offline / backend unconfigured) or an idempotent
  ///               duplicate (the row already exists under that id);
  ///   • `false` → the backend was reachable AND configured but REFUSED the
  ///               INSERT (RLS / constraint / transport). The optimistic
  ///               local row is NEVER rolled back — the caller surfaces an
  ///               actionable retry instead of a phantom success.
  static Future<bool> add(ServiceRequest request) async {
    if (requests.value.any((existing) => existing.id == request.id)) {
      // IDEMPOTENT by id: a double-tap / replayed submission adds nothing and
      // is already durable, so the caller must not be told it failed.
      //
      // UNMIRRORED-DRAFT GUARD (CodeRabbit): that early success must not
      // mask a draft that never reached the backend (created offline before
      // the queue existed, a lost replay, or the Supabase binding arriving
      // after the fact). When the backend is reachable, re-mirror —
      // fire-and-forget. `_mirror` is idempotent (its duplicate-id
      // verification adopts the confirmed row), so a double-tap can never
      // create a second remote order.
      if (ConnectivityStore.isOnline.value && OrdersRepository.isConfigured) {
        unawaited(_mirror(request));
      }
      return true;
    }
    final list = List<ServiceRequest>.from(requests.value);
    list.insert(0, request);
    requests.value = list;

    // Role-routed notifications:
    // • PRO-facing alert targeting the professional account only.
    NotificationStore.notifyNewRequest(
      request.id,
      request.customerName,
      request.professionalId,
    );
    // • CLIENT-facing confirmation ("تم إرسال طلبك بنجاح...").
    NotificationStore.notifyRequestSent(request.id, request.customerId);

    // Local-only paths (offline, or a build with no Supabase binding) are a
    // SUCCESS by contract: the order lives in the in-memory store and the UI
    // must proceed — nothing was refused.
    //
    // DURABLE COMMIT FIRST (CodeRabbit): an OFFLINE creation is written to the
    // offline queue (SharedPreferences) and AWAITED before success is
    // reported. It used to live only in memory, so a kill / restart silently
    // lost the order and the professional never learned about it. The queue now
    // owns it and pushes the row the moment connectivity returns. A build with
    // no Supabase binding has nothing to replay into, so nothing is queued.
    if (!ConnectivityStore.isOnline.value) {
      await _persistPendingCreation(request);
      return true;
    }
    if (!OrdersRepository.isConfigured) return true;

    // PERSISTENCE MIRROR (CodeRabbit): the INSERT is awaited so the shared
    // creation path (booking screen / confirm screen) can never report the
    // order as sent before the backend accepted it.
    final mirrored = await _mirror(request);
    if (!mirrored) {
      // PROPAGATED (CodeRabbit): a REFUSED insert used to be swallowed — the
      // caller navigated to the success screen while the backend owned no
      // row. It is now reported (diagnostics + explicit `false`) so the UI
      // can tell the user the order is stored locally and pending sync.
      AppErrorHandler.report(
        StateError('orders INSERT refused for "${request.id}" '
            '(professional="${request.professionalId}")'),
        StackTrace.current,
        context: 'RequestStore.add',
      );
      // Zero data loss: the refused row is queued as well, so a transient
      // refusal (RLS hiccup, transport reset) is retried automatically on the
      // next connectivity window instead of dying with the process.
      await _persistPendingCreation(request);
    }
    return mirrored;
  }

  /// Client-generated, collision-resistant id (RFC-4122 v4 shape) used when an
  /// order has to be RE-KEYED.
  ///
  /// Why a UUID and not another epoch stamp: the ids this app mints are
  /// `millisecondsSinceEpoch` strings — precisely what collides across devices
  /// and replays. A v4 UUID keeps the replacement unique with no new
  /// dependency.
  @visibleForTesting
  static String newClientId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10, 16).join()}';
  }

  /// Persists a creation that could not be mirrored right now.
  ///
  /// The payload is the EXACT remote row ([OrdersRepository.toRow]), so the
  /// replay is a faithful INSERT. It shares ONE FIFO queue with the status
  /// transitions — a queued `accepted` can therefore never overtake the
  /// creation it depends on.
  ///
  /// AWAITED by [add] before success is reported. Returns false only when the
  /// queue could not take it (no executor bound), which leaves the local-only
  /// commit standing as before.
  static Future<bool> _persistPendingCreation(ServiceRequest request) async {
    try {
      final queued = await OfflineQueue.enqueue(
        QueuedAction(
          // Deterministic id: re-adding the same order never enqueues twice.
          id: 'create_order_${request.id}',
          type: QueuedActionType.createOrder,
          payload: <String, dynamic>{
            'requestId': request.id,
            'row': OrdersRepository.toRow(request),
          },
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!queued) {
        debugPrint('RequestStore: creation "${request.id}" kept local-only '
            '(no createOrder executor bound to the offline queue).');
      }
      return queued;
    } catch (error, stackTrace) {
      AppErrorHandler.report(error, stackTrace,
          context: 'RequestStore._persistPendingCreation');
      return false;
    }
  }

  /// REPLAY ENTRY POINT for the `createOrder` queue executor: mirrors a
  /// creation that never reached the backend when it was submitted.
  ///
  /// Returns true when the backend now durably owns the row (inserted, or
  /// re-keyed then inserted); `false` asks the queue to retry later.
  static Future<bool> mirrorPendingCreation(Map<String, dynamic> row) async {
    final request = OrdersRepository.fromRow(row);
    if (request == null) {
      AppErrorHandler.report(
        StateError('createOrder replay carries an unreadable row'),
        StackTrace.current,
        context: 'RequestStore.mirrorPendingCreation',
      );
      return false;
    }
    return _mirror(request);
  }

  /// Mirrors [request] to the backend, re-keying it only as a LAST RESORT.
  ///
  /// The local ids are `millisecondsSinceEpoch` strings, so an id minted
  /// offline can already exist on the server (another device, a replayed
  /// action, a clock collision). But a duplicate response does NOT always
  /// mean a foreign row (CodeRabbit): the most common cause is a REPLAY — the
  /// first INSERT actually succeeded (lost response, double submission,
  /// replayed queue action) and the row already exists under THIS id.
  /// Blindly re-keying every duplicate would materialize a SECOND order on
  /// the backend for one user intent.
  ///
  /// So the duplicate is VERIFIED first:
  ///   1. local check — a draft no longer in the store (logout / already
  ///      adopted) has nothing left to re-key: the outcome is idempotent;
  ///   2. remote check — a reachable row under the same id is the authoritative
  ///      truth and is MERGED into the local state (no new key minted);
  ///   3. only when the duplicate cannot be tied to an existing row does the
  ///      previous behavior stand: re-key once with a fresh v4 UUID and retry
  ///      the INSERT exactly once. Any other refusal fails this pass.
  static Future<bool> _mirror(ServiceRequest request) async {
    final outcome = await OrdersRepository.insertOrderDetailed(request);
    switch (outcome) {
      case OrderInsertOutcome.inserted:
        return true;
      case OrderInsertOutcome.notConfigured:
        // No backend to sync into: the local commit IS the durable state.
        return true;
      case OrderInsertOutcome.duplicateId:
        break; // verified below, re-keyed only as a last resort
      case OrderInsertOutcome.failed:
        return false;
    }

    // 1) LOCAL STATE FIRST (CodeRabbit): the draft this mirror belongs to may
    // already be gone from the local store (logout reset, or a remote merge
    // adopted it). There is no local order left to keep in sync, so minting a
    // new key would only invent an order nobody owns — treat as idempotent.
    if (!requests.value.any((r) => r.id == request.id)) {
      AppLogger.warn(
        'RequestStore',
        'duplicate INSERT for "${request.id}" whose local draft is gone — '
            'treated as idempotent, no re-key',
      );
      return true;
    }

    // 2) REMOTE VERIFICATION (CodeRabbit): the outcome is classified
    // explicitly — the row may be adopted ONLY when it is provably this
    // order, and the mirror's failure reason is preserved (never masked).
    final verification = await OrdersRepository.verifyOrderRow(
      id: request.id,
      expected: request,
    );
    switch (verification.outcome) {
      case OrderVerification.verifiedSameOrder:
        // The backend row IS this order (schema-valid + matching footprint):
        // merge the authoritative server state — no new key minted, no
        // duplicate order created.
        AppLogger.warn(
          'RequestStore',
          'order "${request.id}" already mirrored — adopting the remote row, '
              'no re-key',
        );
        applyRemoteOrder(verification.order!);
        return true;
      case OrderVerification.inconclusiveTransport:
        // DO NOT re-key on an ambiguous read (CodeRabbit): a transport/auth
        // hiccup proves nothing about the row. Re-keying here would fork the
        // user's order into a second backend row on a mere guess. The local
        // draft stays pending and the mirror is retried on a later pass.
        AppLogger.warn(
          'RequestStore',
          'duplicate INSERT for "${request.id}" could not be verified '
              '(transport/auth) — mirror left pending, no re-key',
        );
        return false;
      case OrderVerification.dataMismatch:
        // Conclusive: the id is taken by a DIFFERENT request — re-keying is
        // the only path (handled in step 3 below).
        break;
      case OrderVerification.rowMissing:
        // Conclusive: the id is definitively FREE (the original INSERT never
        // landed). The correct repair is a plain retry under the SAME key —
        // re-keying here would needlessly diverge the local/remote ids.
        final retried = await OrdersRepository.insertOrderDetailed(request);
        if (retried == OrderInsertOutcome.inserted ||
            retried == OrderInsertOutcome.notConfigured) {
          return true;
        }
        AppErrorHandler.report(
          StateError('same-key retry for "${request.id}" failed: $retried'),
          StackTrace.current,
          context: 'RequestStore._mirror',
        );
        return false;
    }

    // 3) The id is CONCLUSIVELY taken by a different order: re-key once with
    // a fresh v4 UUID and retry the INSERT exactly once. Any other refusal
    // fails this pass.
    final reKeyed = request.copyWith(id: newClientId());
    AppLogger.warn(
      'RequestStore',
      'order "${request.id}" already exists on the backend — re-keyed as '
          '"${reKeyed.id}" and retrying the INSERT',
    );
    _adoptNewId(request.id, reKeyed);

    final retried = await OrdersRepository.insertOrderDetailed(reKeyed);
    if (retried == OrderInsertOutcome.inserted ||
        retried == OrderInsertOutcome.notConfigured) {
      return true;
    }
    if (retried == OrderInsertOutcome.duplicateId) {
      // A fresh v4 UUID colliding twice is astronomically unlikely: reported
      // once, never looped.
      AppErrorHandler.report(
        StateError('re-keyed order "${reKeyed.id}" collided again'),
        StackTrace.current,
        context: 'RequestStore._mirror',
      );
    }
    return false;
  }

  /// Applies a RE-KEY to the local store so the remote row and the local one
  /// stay 1:1 (otherwise the realtime merge would materialize a second,
  /// server-owned order next to the local draft).
  ///
  /// Only a never-mirrored CREATION reaches this path — an order still
  /// `pending`, whose chat room has never opened (chat requires an accepted
  /// order), so no session / message key has to follow the new id.
  static void _adoptNewId(String oldId, ServiceRequest reKeyed) {
    final list = List<ServiceRequest>.from(requests.value);
    final index = list.indexWhere((r) => r.id == oldId);
    if (index == -1) return;
    list[index] = reKeyed;
    requests.value = list;

    // QUEUED-ACTION RE-KEY (CodeRabbit): queued status transitions carrying
    // the OLD id would replay against an id that no longer exists —
    // `updateOrder` would match zero rows, the action would burn its retry
    // budget and be dropped, and the backend would never learn the
    // transition. Re-point every queued action to the fresh id (the payload
    // goes through the same immutable snapshot validation), then persist
    // once so the rewrite survives a kill.
    var requeued = 0;
    for (final action in OfflineQueue.pending.value) {
      if (action.type != QueuedActionType.updateOrderStatus) continue;
      if (action.payload['requestId'] != oldId) continue;
      OfflineQueue.replace(
        action.copyWith(
          payload: <String, dynamic>{
            ...action.payload,
            'requestId': reKeyed.id,
          },
        ),
      );
      requeued++;
    }
    if (requeued > 0) {
      AppLogger.warn(
        'RequestStore',
        're-keyed "$oldId" → "${reKeyed.id}": '
            '$requeued queued transition(s) re-pointed',
      );
      unawaited(OfflineQueue.persistToPrefs());
    }
  }

  // True while a queued replay is applying a status. The flag is READ by the
  // replay path below (prevents a replayed transition from re-enqueueing
  // itself) and SET around every replayed application in
  // [applyReplayedStatus].
  static bool _replaying = false;

  /// Returns true when the transition succeeded.
  ///
  /// Confirming a pending order (`accepted`) deducts exactly 10 tokens from
  /// the professional's balance and unlocks the chat for both parties inside
  /// the admin-defined time window. Without enough tokens the confirmation
  /// is refused (returns false).
  ///
  /// When the device is offline the local state is still applied (optimistic
  /// UI) and the transition is persisted on [OfflineQueue] for automatic
  /// replay once connectivity returns.
  // Rollback-aware remote confirm
  // Online + configured: the online write is attempted FIRST — BEFORE any
  // optimistic session mutation. Success commits the full local patch;
  // a genuinely REFUSED write returns false with local state untouched
  // (the previous status, chat session, notifications and token balance
  // are never touched — no rollback needed because nothing was mutated).
  // Offline-but-configured stays optimistic-first (local-first UX) and the
  // transition is enqueued for replay — NOT a failure.
  // Local-only (Supabase unconfigured, tests) commits locally with no mirror.
  static Future<bool> updateStatus(String id, RequestStatus status) async {
    final request = byId(id);
    if (request == null) return false;
    final prevStatus = request.status;
    if (!_isValidTransition(prevStatus, status)) return false;

    // TOKEN RESERVATION STRICTLY BEFORE BACKEND ACCEPTANCE (CodeRabbit):
    // the 10-token confirmation fee is RESERVED (deducted) BEFORE the
    // backend write and REFUNDED when the write is refused. A mere balance
    // CHECK here (the previous order) left a race window — a concurrent
    // confirmation could drain the balance between the check and the
    // post-write deduction. Reserving first makes the sequence strictly
    // serialized, and a refused write never leaves a phantom charge.
    if (status == RequestStatus.accepted &&
        request.status == RequestStatus.pending &&
        !SubscriptionStore.isPaidSubscriber.value) {
      final deducted = await ProProfileStore.deductTokens(10);
      if (!deducted) {
        debugPrint('RequestStore.updateStatus: trial out of tokens — '
            'acceptance of "$id" refused BEFORE any backend write.');
        return false;
      }
    }

    // MIRROR-FIRST GATE: when the write lands on the backend, the local
    // commit below runs on a confirmed row; when the backend refuses, local
    // state is never touched — and the token reservation is REFUNDED, so a
    // refused acceptance never leaves a phantom charge on the balance.
    if (ConnectivityStore.isOnline.value && OrdersRepository.isConfigured) {
      final confirmed = await _mirrorStatusTransition(id, status);
      if (!confirmed) {
        if (status == RequestStatus.accepted &&
            request.status == RequestStatus.pending &&
            !SubscriptionStore.isPaidSubscriber.value) {
          await ProProfileStore.addTokens(10);
        }
        debugPrint('RequestStore.updateStatus: backend refused "$id" → '
            '"${status.name}" — local state untouched '
            '(still "${prevStatus.name}"), token reservation refunded.');
        return false;
      }
    }

    // Notifications for the confirmed acceptance — the fee was already
    // RESERVED above (never deducted twice on this path).
    if (status == RequestStatus.accepted &&
        request.status == RequestStatus.pending) {
      if (!SubscriptionStore.isPaidSubscriber.value) {
        NotificationStore.notifyTokenDeduction(
          id,
          ProProfileStore.tokens.value,
          request.professionalId,
        );
      }
      NotificationStore.notifyRequestAccepted(
        id,
        request.professionalName,
        request.customerId,
      );
      // Unlock the chat for both parties (auto-expires after 48–72h).
      ChatStore.activate(id);
    } else if (status == RequestStatus.refused &&
        request.status == RequestStatus.pending) {
      NotificationStore.notifyRequestRefused(
        id,
        request.professionalName,
        request.customerId,
      );
    }

    final endingLiveJob = (status == RequestStatus.cancelled ||
            status == RequestStatus.completed) &&
        (request.status == RequestStatus.accepted ||
            request.status == RequestStatus.enRoute ||
            request.status == RequestStatus.arrived ||
            request.status == RequestStatus.inProgress);
    if (endingLiveJob) {
      ChatStore.deactivate(id);
    }

    // Anti-abuse: silently record every client cancellation (`annulée`).
    // Never shown in the UI — the counter lives only in AntiAbuseStore.
    if (status == RequestStatus.cancelled &&
        request.status != RequestStatus.cancelled) {
      // Invoked (not awaited) so the in-memory tally updates synchronously
      // for the caller, while persistence continues in the background.
      unawaited(AntiAbuseStore.recordCancellation(
        clientId: request.customerId,
      ));
    }

    requests.value = requests.value
        .map((r) => r.id == id ? r.copyWith(status: status) : r)
        .toList();

    // OFFLINE ENQUEUE GUARDS: (1) `_replaying` — a replayed transition must
    // never re-enqueue itself (infinite flush loop); (2) queueing is keyed on
    // connectivity ONLY — an unconfigured backend still queues (replay later
    // becomes a local no-op through the idempotent executor), matching the
    // contracted "offline → queued → replayed" behavior exercised in tests.
    if (!_replaying && !ConnectivityStore.isOnline.value) {
      unawaited(_enqueueStatusUpdate(id, status));
    }
    return true;
  }

  /// Applies a queued status transition without re-enqueueing it.
  static Future<bool> applyReplayedStatus(
    String id,
    RequestStatus status,
  ) async {
    _replaying = true;
    try {
      return await updateStatus(id, status);
    } finally {
      _replaying = false;
    }
  }

  /// BACKEND-SYNC-ONLY replay leg (CodeRabbit): pushes an ALREADY-APPLIED
  /// local transition to the backend. Deliberately NOT the standard
  /// [updateStatus] path: the local mutation (status, chat gate, token fee,
  /// notifications) was applied exactly once when the device went offline —
  /// replaying the standard path would re-fire every side effect (a double
  /// 10-token charge, duplicate notifications, an expired chat re-opened)
  /// and echo the row back over realtime. Returns `true` only when the
  /// backend owns the status — or there is no backend to sync into.
  static Future<bool> syncReplayedStatus(
    String id,
    RequestStatus status,
  ) async {
    if (!OrdersRepository.isConfigured) {
      return true; // local-only build: nothing to sync into
    }
    if (!ConnectivityStore.isOnline.value) {
      return false; // transport unavailable — retry on the next window
    }
    final ok = await OrdersRepository.updateOrder(id, status: status);
    if (!ok) {
      AppLogger.warn(
        'RequestStore',
        'replayed status sync for "$id" ($status) was refused — retry later',
      );
    }
    return ok;
  }

  // Confirmed-write mirror shared with [updateStatus].
  //
  // Returns `true` ONLY when the write lands on the backend — `false` means
  // a genuine REFUSAL (RLS/JWT/constraint/transport failure) and the caller
  // must not declare success. Offline-but-configured transitions are
  // enqueued for replay and report success (the optimistic patch stays —
  // local-first UX, NOT a failure).
  static Future<bool> _mirrorStatusTransition(
    String id,
    RequestStatus status,
  ) async {
    if (!OrdersRepository.isConfigured) return true;
    if (!ConnectivityStore.isOnline.value) {
      unawaited(_enqueueStatusUpdate(id, status));
      return true;
    }
    return OrdersRepository.updateOrder(id, status: status);
  }

  static Future<void> _enqueueStatusUpdate(
    String requestId,
    RequestStatus status,
  ) async {
    await AppErrorHandler.runGuarded('RequestStore.enqueueStatusUpdate', () {
      return OfflineQueue.enqueue(
        QueuedAction(
          id: '${requestId}_${status.name}_${DateTime.now().microsecondsSinceEpoch}',
          type: QueuedActionType.updateOrderStatus,
          payload: <String, dynamic>{
            'requestId': requestId,
            'status': status.name,
          },
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  // Admin reset reopens the order as pending: the chat locks again until
  // the professional re-confirms it (charging 10 additional tokens).
  static bool adminResetAcceptance(String id) {
    final request = byId(id);
    if (request == null || request.status != RequestStatus.accepted) {
      return false;
    }

    ChatStore.deactivate(id);
    requests.value = requests.value
        .map((r) => r.id == id ? r.copyWith(status: RequestStatus.pending) : r)
        .toList();
    return true;
  }

  /// Records the customer's review. ONLY fully-completed orders are ratable
  /// (CodeRabbit): a service that is merely accepted / en-route / arrived /
  /// in-progress has nothing to review yet, and silently flipping it to
  /// `completed` from the rating sheet corrupted the state machine.
  ///
  /// Returns `true` when the review was recorded locally (and mirrored to
  /// the backend when configured), `false` when the request is not
  /// completed — the UI must surface that instead of a phantom thank-you.
  static Future<bool> rate(String id, double rating, String comment) async {
    final request = byId(id);
    if (request == null || request.status != RequestStatus.completed) {
      debugPrint('RequestStore.rate: "$id" is not completed '
          '(status: ${request?.status.name ?? 'missing'}) — review refused.');
      return false;
    }
    requests.value = requests.value
        .map((r) =>
            r.id == id ? r.copyWith(rating: rating, reviewComment: comment) : r)
        .toList();
    // Mirror the review to the backend row when it exists there (offline /
    // unconfigured stays local — the same contract as status transitions).
    if (ConnectivityStore.isOnline.value && OrdersRepository.isConfigured) {
      final mirrored = await OrdersRepository.updateOrder(
        id,
        rating: rating,
        reviewComment: comment,
      );
      if (!mirrored) {
        debugPrint('RequestStore.rate: backend refused the review for '
            '"$id" — local review kept.');
      }
    }
    return true;
  }

  static bool _isValidTransition(RequestStatus from, RequestStatus to) {
    if (from == to) return false;
    switch (from) {
      case RequestStatus.pending:
        return to == RequestStatus.accepted ||
            to == RequestStatus.refused ||
            to == RequestStatus.cancelled;
      case RequestStatus.accepted:
        // `arrived` is a REACHABLE transition from `accepted` (CodeRabbit):
        // ProximityService fires the arrival when the pro reaches the site
        // even if the `enRoute` tap never happened (app killed / replay after
        // a restart) — refusing it would strand the order one stage early.
        return to == RequestStatus.enRoute ||
            to == RequestStatus.arrived ||
            to == RequestStatus.cancelled ||
            to == RequestStatus.completed;
      case RequestStatus.enRoute:
        return to == RequestStatus.arrived || to == RequestStatus.cancelled;
      case RequestStatus.arrived:
        return to == RequestStatus.inProgress || to == RequestStatus.cancelled;
      case RequestStatus.inProgress:
        return to == RequestStatus.completed || to == RequestStatus.cancelled;
      case RequestStatus.refused:
      case RequestStatus.completed:
      case RequestStatus.cancelled:
        return false;
    }
  }

  static ServiceRequest? byId(String id) {
    try {
      return requests.value.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<ServiceRequest> forProfessional(String proId) =>
      requests.value.where((r) => r.professionalId == proId).toList();

  static List<ServiceRequest> forCustomer(String name) =>
      requests.value.where((r) => r.customerName == name).toList();

  /// Check if chatting is allowed for a request right now.
  ///
  /// Two layers must pass:
  /// 1. Status layer — only live orders carry a chat (pending/refused/
  ///    completed/cancelled never do).
  /// 2. Session layer — admin closure and the 48–72h auto-expiry window.
  static bool isChatAllowed(String requestId) {
    final request = byId(requestId);
    if (request == null) return false;

    final statusOk = request.status == RequestStatus.accepted ||
        request.status == RequestStatus.enRoute ||
        request.status == RequestStatus.arrived ||
        request.status == RequestStatus.inProgress;

    return statusOk && ChatStore.isActive(requestId);
  }

  /// REALTIME INGRESS (Supabase `orders` channel): applies an order row that
  /// was created/transitioned on ANOTHER device.
  ///
  /// This is a PURE DATA MERGE — deliberately NOT routed through
  /// [updateStatus]:
  ///   • no token deduction (the 10-token fee is charged once, on the device
  ///     that performed the transition);
  ///   • no status notifications (both parties were already notified by the
  ///     actor device through its local path);
  ///   • no remote UPDATE (a merge caused by a remote event must never
  ///     echo the same row back to the server — that would loop).
  ///
  /// What IS mirrored: the row itself, plus the CHAT GATE so a pro accepting
  /// on their phone instantly unlocks the client's chat on the client's
  /// phone (and a terminal status re-locks it).
  static void applyRemoteOrder(ServiceRequest remote) {
    final list = List<ServiceRequest>.from(requests.value);
    final idx = list.indexWhere((r) => r.id == remote.id);
    if (idx == -1) {
      list.insert(0, remote);
    } else {
      list[idx] = remote;
    }
    requests.value = list;

    // Chat-gate mirroring (data-plane only):
    //   live status  → ensure the room is open;
    //   terminal     → re-lock it.
    //
    // EXPIRY GUARD (CodeRabbit): an EXPIRED chat window must never be
    // resurrected by a remote merge. `isActive` answers false for an expired
    // session exactly like for a missing one — activating from that signal
    // alone would start a brand-new window and silently EXTEND the expiry
    // long after the 48–72h window closed. Only a room that was never opened
    // (or explicitly closed) may be opened by the merge; an expired one
    // stays expired until the professional re-confirms the order (which
    // charges a fresh 10-token fee and legitimately starts a new window).
    final wasLive = ChatStore.isActive(remote.id);
    final session = ChatStore.sessionOf(remote.id);
    final expired = session != null && session.isExpired;
    if (remote.status.isActive && !wasLive && !expired) {
      ChatStore.activate(remote.id);
    } else if (remote.status.isDone && wasLive) {
      ChatStore.deactivate(remote.id);
    }
  }

  /// Clears every in-memory order (used on logout).
  static void reset() => requests.value = [];

  /// LIVE BACKEND HYDRATION (Supabase `orders`): pulls the rows the current
  /// identity may see (RLS-scoped SELECT) and merges them into the local
  /// list.
  ///
  /// MERGE RULES:
  ///   • remote rows REPLACE local rows with the same id (the server is the
  ///     authoritative history — an offline device that just reconnected
  ///     adopts the truth, including transitions made from another device);
  ///   • local-only rows are KEPT at the top (they were created offline and
  ///     their INSERT is still queued / in flight — dropping them would lose
  ///     work);
  ///   • newest-first ordering (remote `created_at` order, locals prepended).
  ///
  /// No-op / returns false when Supabase is not configured or the fetch
  /// failed — the local list is left untouched.
  static Future<bool> hydrateFromSupabase() async {
    if (!OrdersRepository.isConfigured) return false;
    final remote = await OrdersRepository.fetchOrders();
    if (remote.isEmpty) return false;

    final remoteById = {for (final r in remote) r.id: r};
    final merged = <ServiceRequest>[
      // Local-only first (offline-created, still pushing).
      for (final r in requests.value)
        if (!remoteById.containsKey(r.id)) r,
      // Then the authoritative remote history.
      ...remote,
    ];
    requests.value = merged;
    return true;
  }
}
