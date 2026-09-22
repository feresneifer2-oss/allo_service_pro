import 'package:flutter/foundation.dart';

/// Kinds of critical, offline-capable operations the queue can replay.
///
/// Keep this list SHORT and business-critical: anything queued must be safe to
/// apply later (idempotent executor — see [OfflineQueue.registerExecutor]).
enum QueuedActionType {
  /// `RequestStore.updateStatus` replay (order status transition).
  updateOrderStatus,

  /// Offline order CREATION (`RequestStore.add` while the device had no usable
  /// network): the payload carries the EXACT remote row
  /// (`{'requestId': id, 'row': OrdersRepository.toRow(request)}`) so the
  /// replay is a faithful INSERT once connectivity returns.
  ///
  /// Sharing ONE queue with [updateOrderStatus] is what preserves the
  /// create-then-transition order: a status UPDATE can never be replayed
  /// before the row it targets has been inserted (FIFO + stop-on-first-retry).
  createOrder,
}

/// One locally-stored operation awaiting a network round-trip.
///
/// Immutable value object: every field is `final`, [payload] is a *deep,
/// unmodifiable snapshot* taken at construction time (a later mutation of the
/// caller's map can never rewrite a queued — possibly already persisted —
/// operation), and [attempts] is tracked through [copyWith] so the queue's
/// persisted list stays consistent.
///
/// ORDERING — [seq] first, [createdAtMs] second
/// ----------------------------------------------------------------
/// [seq] is a monotonic counter that IS the true insertion order: strictly
/// increasing within an app run, persisted with the action, and pushed past
/// every restored value on load (see [fromJson]) — so it survives restarts
/// too. [createdAtMs] stays as a coarse, human-readable stamp but can never
/// overrule the sequence: operations enqueued within the same millisecond
/// compare equal on it (and Dart's `List.sort` is explicitly NOT stable), and
/// a skewed clock can even move it backwards. Ordering on the timestamp alone
/// would make an offline replay non-deterministic — an `accepted` could be
/// applied before the `pending` transition it follows — so [compareTo] (the
/// queue's single ordering rule) leads with [seq].
@immutable
class QueuedAction {
  /// Builds an action, taking an IMMUTABLE deep snapshot of [payload].
  ///
  /// Throws an [ArgumentError] when the payload could never be persisted as
  /// JSON (a non-String/empty key, or a value that is not a `String`, `num`,
  /// `bool`, `null`, `Map` or `List`): failing loudly at the call site beats
  /// crashing in the middle of a later, unattended replay.
  QueuedAction({
    required this.id,
    required this.type,
    required Map<String, dynamic> payload,
    required this.createdAtMs,
    this.attempts = 0,
    this.lastError,
    int? seq,
  })  : payload = _snapshotPayload(payload),
        seq = seq ?? _nextSeq();

  /// Internal constructor for the paths that already hold a validated,
  /// immutable payload ([copyWith], [fromJson]): no second snapshot, and the
  /// original sequence is carried over explicitly.
  const QueuedAction._validated({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAtMs,
    required this.seq,
    required this.attempts,
    this.lastError,
  });

  /// Local, monotonic identifier (stable across restarts).
  final String id;
  final QueuedActionType type;

  /// Opaque, JSON-safe arguments for the executor of [type].
  ///
  /// Never a live view of the caller's map: an unmodifiable deep snapshot
  /// (nested maps/lists included) taken when the action was built.
  final Map<String, dynamic> payload;

  /// Creation time (epoch ms) — a coarse wall-clock stamp and the SECONDARY
  /// ordering key (never overrules [seq], see [compareTo]).
  final int createdAtMs;

  /// Monotonic insertion sequence — the PRIMARY ordering key.
  ///
  /// Assigned automatically from a strictly increasing process-wide counter,
  /// so two actions created within the same millisecond (or with a skewed
  /// clock) still have one deterministic order. Persisted with the action, so
  /// that order survives a restart (and is recycled by legacy entries — see
  /// [fromJson]).
  final int seq;

  /// Delivery attempts already performed (bounded by [OfflineQueue.maxAttempts]).
  final int attempts;

  /// Last failure message, for diagnostics only.
  final String? lastError;

  /// The order this operation targets (payload convention for order actions).
  String? get targetOrderId {
    final v = payload['requestId'];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  QueuedAction copyWith({
    int? attempts,
    String? lastError,
    Map<String, dynamic>? payload,
  }) =>
      QueuedAction._validated(
        id: id,
        type: type,
        // The replacement payload goes through the SAME validation/snapshot
        // path as a fresh action (CodeRabbit): a re-keyed — already persisted
        // — entry must never carry a mutable or non-JSON-safe map.
        payload: payload ?? this.payload,
        createdAtMs: createdAtMs,
        seq: seq,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'payload': payload,
        'createdAtMs': createdAtMs,
        'seq': seq,
        'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  /// Tolerant parser: a corrupted/legacy entry yields null and is DROPPED by
  /// the loader instead of bricking the whole queue.
  ///
  /// [fallbackSeq] is used by entries that predate [seq] (legacy queues): the
  /// loader passes the entry's position inside the persisted list, which IS
  /// the order the operations were enqueued in — so a legacy queue keeps its
  /// exact FIFO order instead of collapsing into a timestamp tie.
  static QueuedAction? fromJson(Object? raw, {int fallbackSeq = 0}) {
    // Keys are validated EXPLICITLY, one at a time, into a fresh map: `cast`
    // returns a LAZY view whose type failure would only surface far from here,
    // on the first read, inside an executor — a "never throws" parser must
    // decide right now, while it still can drop the entry.
    if (raw is! Map) return null;
    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) return null;
      map[key] = entry.value;
    }

    final id = map['id'];
    final typeName = map['type'];
    final rawPayload = map['payload'];
    final createdAtMs = map['createdAtMs'];
    if (id is! String || id.trim().isEmpty) return null;
    if (typeName is! String) return null;
    if (rawPayload is! Map) return null;
    // A non-finite timestamp can never be JSON-encoded again, and
    // `(Infinity as num).toInt()` throws: the tolerant parser must answer
    // null (drop the entry), never throw.
    if (createdAtMs is! num || !createdAtMs.isFinite) return null;

    QueuedActionType? type;
    for (final candidate in QueuedActionType.values) {
      if (candidate.name == typeName) {
        type = candidate;
        break;
      }
    }
    if (type == null) return null;

    // Same shape/type validation as the public constructor: a payload that
    // could never be JSON-encoded again (non-String key, non-JSON-safe value)
    // is malformed, so the entry is dropped rather than trusted.
    final Map<String, dynamic> payload;
    try {
      payload = _snapshotPayload(rawPayload);
    } on ArgumentError {
      return null;
    }

    final rawSeq = map['seq'];
    final seq = rawSeq is int && rawSeq >= 0 ? rawSeq : fallbackSeq;
    // Keep the monotonic counter STRICTLY ahead of everything restored from
    // disk: since [seq] is the PRIMARY comparison key, this is what makes an
    // action enqueued right after a relaunch sort AFTER every stored one —
    // regardless of what the (possibly skewed) wall-clock then stamps.
    if (seq >= _seqCounter) _seqCounter = seq + 1;

    final attempts = map['attempts'];
    return QueuedAction._validated(
      id: id,
      type: type,
      payload: payload,
      createdAtMs: createdAtMs.toInt(),
      seq: seq,
      attempts: attempts is int && attempts >= 0 ? attempts : 0,
      lastError: map['lastError'] is String ? map['lastError'] as String : null,
    );
  }

  /// Deterministic FIFO comparator — the queue's single ordering rule.
  ///
  /// [seq] is the ABSOLUTE primary key: it is a per-process monotonic counter,
  /// so it IS the true insertion order — including across a relaunch, where
  /// [fromJson] pushes the counter past every restored value. [createdAtMs] is
  /// only a coarse wall-clock stamp: it ties within the same millisecond (and
  /// Dart's `List.sort` is explicitly NOT stable) and can even move BACKWARDS
  /// (clock skew, NTP correction), so it must never overrule the sequence.
  ///
  /// The remaining keys keep the order TOTAL, so even pathological input (a
  /// hand-crafted entry duplicating a sequence) has exactly one defined order.
  int compareTo(QueuedAction other) {
    final bySeq = seq.compareTo(other.seq);
    if (bySeq != 0) return bySeq;
    final byTime = createdAtMs.compareTo(other.createdAtMs);
    if (byTime != 0) return byTime;
    return id.compareTo(other.id);
  }

  @override
  String toString() => 'QueuedAction(${type.name}, id=$id, '
      'order=$targetOrderId, seq=$seq, attempts=$attempts)';

  // ---------------------------------------------------------------------------
  // Payload snapshot
  // ---------------------------------------------------------------------------

  /// Validates [raw] and returns an IMMUTABLE deep snapshot of it.
  ///
  /// WHY a snapshot: a payload is durable state, not a live view of the
  /// caller's map. Without it, a caller keeping a reference could mutate the
  /// very arguments that a queued — already persisted — action will later be
  /// replayed with: a silent, unreproducible corruption.
  static Map<String, dynamic> _snapshotPayload(Map<Object?, Object?> raw) {
    final snapshot = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        throw ArgumentError.value(
            raw, 'payload', 'keys must be non-empty strings (found: $key)');
      }
      snapshot[key] = _snapshotValue(key, entry.value);
    }
    return Map<String, dynamic>.unmodifiable(snapshot);
  }

  /// Deep copy + JSON-safety check of a single payload value.
  ///
  /// Numbers must be FINITE: `jsonEncode` refuses NaN/±Infinity at persistence
  /// time (`JsonUnsupportedObjectError`), and [OfflineQueue.persistToPrefs]
  /// being best-effort, one poisoned payload would silently disable persistence
  /// for the WHOLE queue. The rejection therefore happens here — once, at
  /// construction, BEFORE anything can be serialized — and since the snapshot
  /// is immutable, a validated value can never turn non-finite afterwards.
  static Object? _snapshotValue(String key, Object? value) {
    if (value == null || value is String || value is bool) {
      return value;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw ArgumentError.value(
          value,
          'payload[$key]',
          'must be a finite number (NaN/Infinity can never be JSON-encoded)',
        );
      }
      return value;
    }
    if (value is Map) return _snapshotPayload(value);
    if (value is List) {
      return List<Object?>.unmodifiable(
        <Object?>[for (final item in value) _snapshotValue(key, item)],
      );
    }
    throw ArgumentError.value(value, 'payload[$key]',
        'must be JSON-safe (String, num, bool, null, Map or List)');
  }

  // ---------------------------------------------------------------------------
  // Monotonic sequence
  // ---------------------------------------------------------------------------

  /// Process-wide sequence source. It only has to be monotonic WITHIN one app
  /// run: [createdAtMs] carries the order across restarts, and [fromJson]
  /// pushes this counter past every restored value.
  static int _seqCounter = 0;

  static int _nextSeq() => ++_seqCounter;

  /// Test hook: restarts the sequence source (touches no persisted data).
  @visibleForTesting
  static void debugResetSequence() {
    _seqCounter = 0;
  }
}

/// Outcome an executor reports for a single replay attempt.
enum QueueExecutionResult {
  /// Operation applied server-side/local-side: remove it from the queue.
  applied,

  /// Transient failure (offline again, timeout, backend hiccup): keep it and
  /// retry later, up to [OfflineQueue.maxAttempts].
  retry,

  /// Non-recoverable: malformed payload or a semantic refusal (e.g. the
  /// professional has no tokens to confirm). Retrying can never help, so the
  /// entry is dropped and logged as an error.
  drop,
}

/// Replays one queued operation. Must never throw:
/// * [QueueExecutionResult.retry] — transient problem;
/// * [QueueExecutionResult.drop]  — permanently unusable;
/// * [QueueExecutionResult.applied] — done.
///
/// Executors MUST be idempotent: an operation may have already been applied
/// optimistically while offline (the local state is authoritative for the UI),
/// so a replay that finds the target in the desired state returns `applied`.
typedef QueuedActionExecutor = Future<QueueExecutionResult> Function(
    QueuedAction action);
