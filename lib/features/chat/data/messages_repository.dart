import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';
import '../models/chat_message.dart';

/// Supabase gateway for the live `messages` table (chat persistence).
///
/// MAPPING CONTRACT (`messages` columns ↔ [ChatMessage]):
///   id (text pk)          ← [ChatMessage.id] (local generation id kept as
///                           the primary key → dedupe across devices is 1:1);
///   request_id            ← [ChatMessage.requestId]
///   sender_id / sender_name ← [ChatMessage.senderId/Name]
///   body                  ← [ChatMessage.text]
///   is_customer (bool)    ← [ChatMessage.isCustomer]
///   type                  ← [ChatMessageType] ('text'|'voice'|'photo'|'location')
///   media_path            ← [ChatMessage.mediaPath]
///   voice_duration_sec    ← [ChatMessage.voiceDurationSec]
///   latitude / longitude  ← [ChatMessage.latitude/Longitude]
///   created_at (timestamptz) ← [ChatMessage.sentAt]
///
/// FAILURE POLICY: failure-tolerant (logged, never thrown into the UI), and
/// a no-op when Supabase is not initialized — the in-memory store stays the
/// single source of truth for the UI.
class MessagesRepository {
  MessagesRepository._();

  static const String _table = 'messages';

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── enum ↔ wire mapping ──────────────────────────────────────────────
  static String typeToWire(ChatMessageType t) => t.name;

  static ChatMessageType typeFromWire(Object? raw) {
    switch (raw) {
      case 'voice':
        return ChatMessageType.voice;
      case 'photo':
        return ChatMessageType.photo;
      case 'location':
        return ChatMessageType.location;
      default:
        return ChatMessageType.text;
    }
  }

  static Map<String, dynamic> toRow(ChatMessage m) => <String, dynamic>{
        'id': m.id,
        'request_id': m.requestId,
        'sender_id': m.senderId,
        'sender_name': m.senderName,
        'body': m.text,
        'is_customer': m.isCustomer,
        'type': typeToWire(m.type),
        if (m.mediaPath != null) 'media_path': m.mediaPath,
        'voice_duration_sec': m.voiceDurationSec,
        if (m.latitude != null) 'latitude': m.latitude,
        if (m.longitude != null) 'longitude': m.longitude,
        'created_at': m.sentAt.toUtc().toIso8601String(),
      };

  static ChatMessage? fromRow(Map<String, dynamic> row) {
    try {
      final id = row['id'];
      final requestId = row['request_id'];
      if (id is! String || id.isEmpty) return null;
      if (requestId is! String || requestId.isEmpty) return null;
      final sentAt =
          DateTime.tryParse((row['created_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now();
      return ChatMessage(
        id: id,
        requestId: requestId,
        senderId: (row['sender_id'] as String?) ?? '',
        senderName: (row['sender_name'] as String?) ?? '',
        text: (row['body'] as String?) ?? '',
        sentAt: sentAt,
        isCustomer: (row['is_customer'] as bool?) ?? false,
        type: typeFromWire(row['type']),
        mediaPath: row['media_path'] as String?,
        voiceDurationSec: (row['voice_duration_sec'] as num?)?.toInt() ?? 0,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('MessagesRepository.fromRow: malformed row skipped: $e');
      return null;
    }
  }

  /// INSERT of a locally sent message (fire-and-forget from [ChatStore]).
  /// RLS scopes the write to participants of the order. Failures are logged
  /// and swallowed — a transient network error must never break the local
  /// send path.
  static Future<bool> insertMessage(ChatMessage message) async {
    if (!isConfigured) return false;
    try {
      await Supabase.instance.client.from(_table).insert(toRow(message));
      return true;
    } catch (e, st) {
      AppErrorHandler.report(e, st,
          context: 'MessagesRepository.insertMessage');
      return false;
    }
  }

  /// SELECT of the history for one chat room (ordered oldest-first).
  static Future<List<ChatMessage>> fetchMessages(String requestId) async {
    if (!isConfigured) return const [];
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('request_id', requestId)
          .order('created_at', ascending: true);
      final out = <ChatMessage>[];
      for (final row in (rows as List)) {
        final m = fromRow((row as Map).cast<String, dynamic>());
        if (m != null) out.add(m);
      }
      return out;
    } catch (e, st) {
      AppErrorHandler.report(e, st,
          context: 'MessagesRepository.fetchMessages');
      return const [];
    }
  }
}
