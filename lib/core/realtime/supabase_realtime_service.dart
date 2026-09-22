import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/application/chat_store.dart';
import '../../features/chat/data/messages_repository.dart';
import '../../features/requests/application/request_store.dart';
import '../../features/requests/data/orders_repository.dart';

/// Supabase Realtime gateway — pushes live `orders` and `messages` changes
/// straight into the local stores so client & pro screens update WITHOUT a
/// manual refresh.
///
/// CHANNELS (both respect the server-side RLS: each identity receives only
/// the rows it may read):
///   • `realtime:public:orders`   → INSERT / UPDATE →
///     [RequestStore.applyRemoteOrder] (pure data merge + chat-gate mirror);
///   • `realtime:public:messages` → INSERT →
///     [ChatStore.applyRemoteMessage] (id-deduped, self-echo suppressed).
///
/// LIFECYCLE: [start] is idempotent (safe to call again) and a no-op when
/// Supabase is not initialized (tests / offline demo builds). [stop] removes
/// the channels — used on sign-out so a signed-out device stops ingesting.
class SupabaseRealtimeService {
  SupabaseRealtimeService._();

  static RealtimeChannel? _ordersChannel;
  static RealtimeChannel? _messagesChannel;

  /// Monotonic BINDING GENERATION.
  ///
  /// Incremented on every [start] and every [stop], and captured by each
  /// callback closure at bind time. A callback whose captured generation no
  /// longer matches the current one is a STALE delivery — an event that was
  /// already in flight while its channel was being removed (sign-out) or
  /// while the subscription was being rebound to another identity — and is
  /// rejected before it can merge a foreign account's row into the stores.
  static int _generation = 0;

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void start() {
    if (!isConfigured) {
      debugPrint('RealtimeService: Supabase not initialized — '
          'channels not bound (local-only mode).');
      return;
    }
    if (_ordersChannel != null) return; // idempotent rebind guard

    final client = Supabase.instance.client;
    // Generation captured by BOTH callbacks below: a delivery that outlives
    // this binding (channel removed, or rebound to another identity) carries
    // a stale generation and is rejected before touching the stores.
    _generation++;
    final generation = _generation;

    // ── ORDERS: instant status changes / new orders ──
    _ordersChannel = client
        .channel('realtime:public:orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            // STALE-CALLBACK GUARD (CodeRabbit): `_ordersChannel` may already
            // have been removed / rebound — a late event from the previous
            // subscription must never be merged into the current session.
            if (generation != _generation) return;
            final row = payload.newRecord;
            if (row.isEmpty) return; // DELETE events: out of scope
            final order = OrdersRepository.fromRow(row.cast<String, dynamic>());
            if (order != null) RequestStore.applyRemoteOrder(order);
          },
        )
        .subscribe();

    // ── MESSAGES: instant chat delivery ──
    _messagesChannel = client
        .channel('realtime:public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (generation != _generation) return; // stale delivery
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final msg = MessagesRepository.fromRow(row.cast<String, dynamic>());
            if (msg != null) ChatStore.applyRemoteMessage(msg);
          },
        )
        .subscribe();

    debugPrint('RealtimeService: channels bound (orders + messages).');
  }

  /// Removes both channels (sign-out) so a signed-out device stops ingesting
  /// realtime data. Idempotent.
  ///
  /// INDEPENDENT TEARDOWN (CodeRabbit): every removal is guarded on its own —
  /// a throwing `removeChannel` for one channel can no longer abort the
  /// sibling removal and leak a LIVE, still-ingesting channel. The generation
  /// bump happens FIRST, so callbacks already in flight are invalidated
  /// synchronously.
  static Future<void> stop() async {
    // STALE-CALLBACK REJECTION: bump before any `await` — the removal below
    // is asynchronous, and an in-flight delivery must not slip through.
    _generation++;

    final client = isConfigured ? Supabase.instance.client : null;
    final orders = _ordersChannel;
    final messages = _messagesChannel;
    _ordersChannel = null;
    _messagesChannel = null;

    if (client == null) {
      debugPrint('RealtimeService.stop: Supabase not initialized — '
          'channels dropped locally.');
      return;
    }

    await _removeChannel(client, orders, 'orders');
    await _removeChannel(client, messages, 'messages');
  }

  /// Removes ONE channel inside its own guard, so a failure never aborts the
  /// teardown of the other channel (or the caller's flow).
  static Future<void> _removeChannel(
    SupabaseClient client,
    RealtimeChannel? channel,
    String label,
  ) async {
    if (channel == null) return;
    try {
      await client.removeChannel(channel);
    } catch (e) {
      debugPrint('RealtimeService.stop: $label channel removal failed: $e');
    }
  }

  /// Test/teardown seam — drops the local channel references without any
  /// client call (no Supabase binding needed).
  @visibleForTesting
  static void debugReset() {
    // Also invalidates every callback closure bound so far: a test that
    // resets the service must not receive deliveries from a previous bind.
    _generation++;
    _ordersChannel = null;
    _messagesChannel = null;
  }
}
