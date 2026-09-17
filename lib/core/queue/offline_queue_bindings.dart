import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
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
        // Already in the desired state (optimistic apply was persisted).
        return QueueExecutionResult.applied;
      }

      // Attempt the transition through the real domain path (replay flag
      // prevents the store from re-enqueueing the same operation).
      final ok = RequestStore.applyReplayedStatus(requestId, targetStatus);
      return ok
          ? QueueExecutionResult.applied
          : QueueExecutionResult.retry;
    } catch (error, stackTrace) {
      AppErrorHandler.report(
        error,
        stackTrace,
        context: 'OfflineQueueBindings._replayUpdateOrderStatus',
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
