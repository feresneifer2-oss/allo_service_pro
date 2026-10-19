import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/pro_dashboard/data/pro_availability_repository.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';

/// Wires [OfflineQueue] executors to domain stores.
///
/// This file is the ONLY place that knows about business semantics —
/// the queue itself is store-agnostic and never imports domain code.
/// Registering an executor binds a [QueuedActionType] to the concrete
/// replay logic, so the queue can replay stored operations without
/// importing any feature layer.
class OfflineQueueBindings {
  OfflineQueueBindings._();

  /// Registers all domain-aware executors.
  /// Safe to call multiple times (replaces existing handlers).
  static void registerAll() {
    OfflineQueue.registerExecutor(
      QueuedActionType.updateOrderStatus,
      _replayUpdateOrderStatus,
    );
    OfflineQueue.registerExecutor(
      QueuedActionType.createOrder,
      _replayCreateOrder,
    );
    OfflineQueue.registerExecutor(
      QueuedActionType.updateProAvailability,
      _replayUpdateProAvailability,
    );
  }

  /// Arms the CONNECTIVITY-DRIVEN REPLAY (CodeRabbit).
  ///
  /// Registering executors is only half of the wiring: the queue reaches the
  /// backend solely while its connectivity listener is bound. That listener —
  /// plus the boot drain of work left over from a previous run — lives in
  /// [OfflineQueue.init], so this is the single step that guarantees an
  /// executor exists for every queued type AND a processor is listening for
  /// reconnection (a queued transition is otherwise never sent).
  ///
  /// Deliberately a SEPARATE, awaitable step instead of a hidden side effect of
  /// [registerAll]: tests register executors without arming an auto-flush that
  /// would drain their fixtures behind their backs, while `main()` awaits both
  /// in one place. Idempotent — [OfflineQueue.init] returns immediately once
  /// armed.
  static Future<void> armAutoFlush() => OfflineQueue.init();

  /// Replays an offline order CREATION.
  ///
  /// The payload carries the exact remote row, so the replay is a plain INSERT.
  /// [RequestStore.mirrorPendingCreation] owns the idempotency details (a
  /// duplicate primary key is re-keyed and retried once): `applied` means the
  /// backend durably owns the row, `retry` keeps the entry for the next
  /// connectivity window, and a payload without a row map is unusable → drop.
  static Future<QueueExecutionResult> _replayCreateOrder(
    QueuedAction action,
  ) async {
    try {
      final rawRow = action.payload['row'];
      if (rawRow is! Map) {
        AppLogger.error(
          'OfflineQueue',
          'non-map createOrder payload: row=${rawRow.runtimeType}',
        );
        return QueueExecutionResult.drop;
      }

      final mirrored = await RequestStore.mirrorPendingCreation(
        rawRow.cast<String, dynamic>(),
      );
      return mirrored
          ? QueueExecutionResult.applied
          : QueueExecutionResult.retry;
    } catch (error, stackTrace) {
      AppErrorHandler.report(
        error,
        stackTrace,
        context: 'OfflineQueueBindings._replayCreateOrder',
      );
      return QueueExecutionResult.retry;
    }
  }

  /// Replays an `updateOrderStatus` action.
  ///
  /// Idempotent: if the order is already in the target status, returns
  /// [QueueExecutionResult.applied] without side effects.
  static Future<QueueExecutionResult> _replayUpdateOrderStatus(
    QueuedAction action,
  ) async {
    try {
      final payload = action.payload;
      final rawRequestId = payload['requestId'];
      final rawStatus = payload['status'];

      // Type-guards FIRST: persisted payloads may come from an older/foreign
      // writer, so never touch `.trim()`/parsing before proving the shape.
      if (rawRequestId is! String || rawStatus is! String) {
        AppLogger.error(
          'OfflineQueue',
          'non-string updateOrderStatus payload: '
              'req=${rawRequestId.runtimeType}, status=${rawStatus.runtimeType}',
        );
        return QueueExecutionResult.drop;
      }

      final requestId = rawRequestId.trim();
      final targetStatus = _statusFromName(rawStatus);

      if (requestId.isEmpty || targetStatus == null) {
        // Malformed payload: permanently unusable, drop it.
        AppLogger.error(
          'OfflineQueue',
          'malformed updateOrderStatus payload: req=$requestId, status=$rawStatus',
        );
        return QueueExecutionResult.drop;
      }

      final current = RequestStore.byId(requestId);
      if (current == null) {
        // Order no longer exists locally: nothing to confirm, treat as applied.
        return QueueExecutionResult.applied;
      }

      if (current.status == targetStatus) {
        // The optimistic apply already mutated the local store when the
        // device went offline — the queued action's REMAINING work is the
        // BACKEND SYNC ONLY (CodeRabbit): replaying the standard mutation
        // path would re-fire notifications, re-open/expire chat rooms and
        // re-charge the 10-token fee. Sync the row, then report the result.
        final synced =
            await RequestStore.syncReplayedStatus(requestId, targetStatus);
        return synced
            ? QueueExecutionResult.applied
            : QueueExecutionResult.retry;
      }

      // Divergent edge (store reset between enqueue and replay): the local
      // mutation genuinely still has to happen — guarded full path.
      final ok =
          await RequestStore.applyReplayedStatus(requestId, targetStatus);
      return ok ? QueueExecutionResult.applied : QueueExecutionResult.retry;
    } catch (error, stackTrace) {
      AppErrorHandler.report(
        error,
        stackTrace,
        context: 'OfflineQueueBindings._replayUpdateOrderStatus',
      );
      return QueueExecutionResult.retry;
    }
  }

  /// Replays an offline availability toggle (`pro_availability`).
  ///
  /// Idempotent BY CONSTRUCTION: the executor performs the exact same UPSERT
  /// the online path performs, keyed by `pro_id` — replaying it once or ten
  /// times converges on the same row, and no duplicate can ever be created.
  ///
  /// The payload carries the value the pro last chose; `ProProfileStore`
  /// re-keys the single pending entry per professional on every new toggle, so
  /// the replayed value is always the LATEST action — the final persisted state
  /// and the local switch can therefore never disagree.
  ///
  /// A payload that can never be replayed (missing uid / non-bool flag) is
  /// dropped; a backend that did not answer keeps the entry for the next
  /// connectivity window.
  static Future<QueueExecutionResult> _replayUpdateProAvailability(
    QueuedAction action,
  ) async {
    try {
      final payload = action.payload;
      final rawProId = payload['proId'];
      final rawFlag = payload['isAvailable'];

      // Type-guards FIRST: a persisted payload may come from an older writer.
      if (rawProId is! String || rawFlag is! bool) {
        AppLogger.error(
          'OfflineQueue',
          'non-string updateProAvailability payload: '
              'proId=${rawProId.runtimeType}, flag=${rawFlag.runtimeType}',
        );
        return QueueExecutionResult.drop;
      }
      final proId = rawProId.trim();
      if (proId.isEmpty) {
        AppLogger.error(
          'OfflineQueue',
          'malformed updateProAvailability payload: empty proId',
        );
        return QueueExecutionResult.drop;
      }

      // Phase 7-3: session guard — never replay an availability entry
      // under the wrong session (prevents the stale `true` bug).
      // No verified session (boot before auth restore / local-only mode):
      // KEEP the entry for a later window — the backend refuses
      // unauthenticated writes anyway, and dropping it would lose the pro's
      // offline choice. Only a mismatched session is unrecoverable.
      final currentUid = SupabaseAuthService.currentUserId;
      if (currentUid == null) {
        return QueueExecutionResult.retry;
      }
      if (currentUid != proId) {
        return QueueExecutionResult.drop;
      }

      final rawCode = payload['proCode'];
      final applied = await ProAvailabilityRepository.upsertAvailability(
        proId: proId,
        proCode: rawCode is String ? rawCode : null,
        isAvailable: rawFlag,
      );
      return applied
          ? QueueExecutionResult.applied
          : QueueExecutionResult.retry;
    } catch (error, stackTrace) {
      AppErrorHandler.report(
        error,
        stackTrace,
        context: 'OfflineQueueBindings._replayUpdateProAvailability',
      );
      return QueueExecutionResult.retry;
    }
  }

  /// Parses a stored status name back to [RequestStatus].
  static RequestStatus? _statusFromName(String? name) {
    if (name == null) return null;
    for (final s in RequestStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
