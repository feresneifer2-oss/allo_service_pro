import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/messages_repository.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../notifications/application/notification_store.dart';
import '../../auth/application/user_store.dart';
import '../../requests/application/request_store.dart';

class ChatStore {
  ChatStore._();

  static final messages = ValueNotifier<Map<String, List<ChatMessage>>>({});

  /// Lifecycle state of every request-bound chat room (admin-manageable).
  static final sessions = ValueNotifier<Map<String, ChatSession>>({});

  /// Auto-expiry window applied to newly opened chats. Admin-configurable,
  /// business range: 48–72 hours (default 48h).
  static int _expiryHours = 96;
  static int get expiryHours => _expiryHours;

  static void setExpiryHours(int hours) {
    if (hours < 48 || hours > 96) return;
    _expiryHours = hours;
  }

  static ChatSession? sessionOf(String requestId) => sessions.value[requestId];

  static List<ChatMessage> forRequest(String requestId) =>
      messages.value[requestId] ?? [];

  /// Opens (or refreshes) an active chat window once an order is confirmed.
  /// Called by [RequestStore] right after the 10-token deduction succeeds.
  static void activate(String requestId) {
    final map = Map<String, ChatSession>.from(sessions.value);
    map[requestId] = ChatSession(
      requestId: requestId,
      activatedAt: DateTime.now(),
      expiryHours: _expiryHours,
    );
    sessions.value = map;
  }

  /// Restores a session VERBATIM — same [ChatSession.activatedAt],
  /// [ChatSession.expiryHours], active flag and close stamp.
  ///
  /// ROLLBACK PATH ONLY (CodeRabbit): when an optimistic order transition is
  /// reverted because its Supabase write was genuinely refused, the chat
  /// window must go back to EXACTLY how it was. Re-opening it through
  /// [activate] would be wrong twice over — it starts a brand-new window
  /// (`activatedAt = now`) and therefore silently EXTENDS the chat expiry for
  /// an order the server never accepted. Passing `null` removes the session
  /// entirely (the pre-transition state when no room existed yet).
  static void restoreSession(String requestId, ChatSession? session) {
    final map = Map<String, ChatSession>.from(sessions.value);
    if (session == null) {
      if (!map.containsKey(requestId)) return;
      map.remove(requestId);
    } else {
      map[requestId] = session;
    }
    sessions.value = map;
  }

  /// Silently marks a session inactive (order reset / cancelled / completed).
  static void deactivate(String requestId) {
    final current = sessions.value[requestId];
    if (current == null || !current.active) return;

    final map = Map<String, ChatSession>.from(sessions.value);
    map[requestId] = ChatSession(
      requestId: requestId,
      active: false,
      activatedAt: current.activatedAt,
      closedAt: DateTime.now(),
      expiryHours: current.expiryHours,
    );
    sessions.value = map;
  }

  /// Admin manually closes a chat: neither party can send until the order is
  /// confirmed again (which charges another 10 tokens). Notifies both sides.
  static void closeByAdmin(String requestId) {
    final current = sessions.value[requestId];
    if (current == null || !current.active) return;

    deactivate(requestId);

    final request = RequestStore.byId(requestId);
    if (request != null) {
      if (request.customerId.isNotEmpty) {
        NotificationStore.notifyChatClosed(
          requestId,
          request.customerId,
          targetRole: 'client',
        );
      }
      NotificationStore.notifyChatClosed(
        requestId,
        request.professionalId,
        targetRole: 'professional',
      );
    }
  }

  /// Why a chat room is unavailable right now (drives UI messaging).
  static ChatClosureReason closureStateOf(String requestId) {
    final s = sessions.value[requestId];
    if (s == null) return ChatClosureReason.none;
    if (!s.active) return ChatClosureReason.adminClosed;
    if (s.isExpired) return ChatClosureReason.expired;
    return ChatClosureReason.none;
  }

  /// A chat can carry messages only while its session is active & unexpired.
  static bool isActive(String requestId) {
    final s = sessions.value[requestId];
    return s != null && s.active && !s.isExpired;
  }

  static void send({
    required String requestId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isCustomer,
  }) {
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      isCustomer: isCustomer,
    );
  }

  /// Sends a recorded voice note. Available to BOTH roles (client & pro) —
  /// the stored structure is identical, only the bubble side differs.
  static void sendVoice({
    required String requestId,
    required String senderId,
    required String senderName,
    required String filePath,
    required int durationSec,
    required bool isCustomer,
  }) {
    final path = filePath.trim();
    if (path.isEmpty) return;
    final seconds =
        durationSec < 1 ? 1 : (durationSec > 600 ? 600 : durationSec);
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.voice,
      mediaPath: path,
      voiceDurationSec: seconds,
    );
  }

  /// Sends an attached photo. Available to BOTH roles as well.
  static void sendPhoto({
    required String requestId,
    required String senderId,
    required String senderName,
    required String filePath,
    required bool isCustomer,
  }) {
    final path = filePath.trim();
    if (path.isEmpty) return;
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.photo,
      mediaPath: path,
    );
  }

  /// Sends a GPS location pin. Available to BOTH roles.
  /// The recipient can tap the bubble to open Google Maps.
  static void sendLocation({
    required String requestId,
    required String senderId,
    required String senderName,
    required double latitude,
    required double longitude,
    required bool isCustomer,
  }) {
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.location,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static int _seq = 0;

  /// Single persistence pipeline shared by text / voice / photo messages.
  /// Defense-in-depth: never persist messages into locked rooms (admin
  /// closure, expiry, or unconfirmed order).
  static void _append({
    required String requestId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isCustomer,
    ChatMessageType type = ChatMessageType.text,
    String? mediaPath,
    int voiceDurationSec = 0,
    double? latitude,
    double? longitude,
  }) {
    if (!RequestStore.isChatAllowed(requestId)) return;

    final msg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      isCustomer: isCustomer,
      type: type,
      mediaPath: mediaPath,
      voiceDurationSec: voiceDurationSec,
      latitude: latitude,
      longitude: longitude,
    );

    final map = Map<String, List<ChatMessage>>.from(messages.value);
    map[requestId] = [...(map[requestId] ?? []), msg];
    messages.value = map;

    // LIVE BACKEND MIRROR (Supabase `messages`): the local append stays
    // synchronous; the row is pushed asynchronously so the OTHER device
    // receives it through the Realtime `messages` channel. No-op / logged
    // when offline or Supabase is not initialized.
    //
    // REMOTE-SAFE MEDIA (CodeRabbit): a DEVICE-LOCAL path must never reach the
    // shared table — it is unreadable for the counterpart. Any local media is
    // uploaded first and the row carries the returned public URL
    // (see [_mirrorToBackend]).
    unawaited(_mirrorToBackend(msg));

    // Send notification about new message, routed to the RECEIVING side:
    // a customer's message alerts the pro, and vice-versa.
    final request = RequestStore.byId(requestId);
    final recipientId =
        isCustomer ? request?.professionalId : request?.customerId;
    if (recipientId != null && recipientId.isNotEmpty) {
      NotificationStore.notifyChatMessage(
        requestId,
        senderName,
        recipientId,
        targetRole: isCustomer ? 'professional' : 'client',
      );
    }
  }

  /// Pushes [msg] to the shared `messages` table, guaranteeing that only
  /// REMOTE-READABLE media references are persisted (CodeRabbit).
  ///
  /// WHY: `mediaPath` is device-local (`/data/user/0/…`, `file://…`, `C:\…`)
  /// whenever the capture upload failed or the device was offline. Persisting
  /// that string remotely produced a message the OTHER party could never
  /// render — an unreadable bubble everywhere but the sender's phone.
  ///
  /// CONTRACT:
  ///   • no media, or already remote (`http(s)://`) → insert as-is;
  ///   • local media → upload to the public `chat-media` bucket FIRST, then
  ///     insert the row carrying the returned PUBLIC URL (and upgrade the local
  ///     bubble in place, so both sides show the very same URL);
  ///   • upload impossible (offline / failure) → the row is NOT inserted: the
  ///     message stays local-only rather than becoming a broken remote row.
  static Future<void> _mirrorToBackend(ChatMessage msg) async {
    final media = msg.mediaPath;
    if (media == null || media.isEmpty || !_isLocalMediaPath(media)) {
      await MessagesRepository.insertMessage(msg);
      return;
    }

    final remoteUrl = await SupabaseStorageService.uploadChatMedia(
      msg.requestId,
      File(media),
      kind: msg.type == ChatMessageType.voice ? 'voice' : 'photo',
    );
    if (remoteUrl == null || remoteUrl.isEmpty) {
      debugPrint('ChatStore: media for "${msg.id}" stayed local — the row is '
          'not mirrored (a device path must never reach the shared table).');
      return;
    }

    _replaceMediaPath(msg.id, remoteUrl);
    await MessagesRepository.insertMessage(msg.copyWith(mediaPath: remoteUrl));
  }

  /// True when [path] is a DEVICE-LOCAL reference rather than a remote URL.
  ///
  /// Deliberately conservative: anything that is not an `http(s)` URL is
  /// treated as local, because persisting it remotely can only ever produce an
  /// unreadable row.
  static bool _isLocalMediaPath(String path) {
    final lower = path.toLowerCase();
    return !lower.startsWith('http://') && !lower.startsWith('https://');
  }

  /// Upgrades the in-memory bubble's [ChatMessage.mediaPath] to the uploaded
  /// URL so the sender's own view and the counterpart's realtime copy agree.
  /// No notifier emission when nothing actually changed.
  static void _replaceMediaPath(String messageId, String remoteUrl) {
    var changed = false;
    final map = <String, List<ChatMessage>>{};
    for (final entry in messages.value.entries) {
      final updated = <ChatMessage>[];
      for (final m in entry.value) {
        if (m.id == messageId && m.mediaPath != remoteUrl) {
          updated.add(m.copyWith(mediaPath: remoteUrl));
          changed = true;
        } else {
          updated.add(m);
        }
      }
      map[entry.key] = updated;
    }
    if (changed) messages.value = map;
  }

  /// REALTIME INGRESS (Supabase `messages` channel): applies a message that
  /// was persisted by the OTHER device.
  ///
  /// ECHO-SAFETY: the sender's own device ALSO receives its INSERT through
  /// the channel (the row was already appended locally by [_append]) — the
  /// id-based dedupe below makes that a no-op instead of a double bubble.
  ///
  /// The local notification fires ONLY for genuinely incoming messages
  /// (sender is the other party), never for the local echo.
  static void applyRemoteMessage(ChatMessage msg) {
    final existing = messages.value[msg.requestId] ?? const <ChatMessage>[];
    if (existing.any((m) => m.id == msg.id)) return; // echo / duplicate

    final map = Map<String, List<ChatMessage>>.from(messages.value);
    map[msg.requestId] = [...existing, msg];
    messages.value = map;

    // Self-echo suppression: the LOCAL session user id is authoritative —
    // a message authored by this very identity (from another device or the
    // realtime echo of a local send) must never notify itself.
    final me = UserStore.user.value?.id;
    if (me != null && me.isNotEmpty && msg.senderId == me) return;

    final request = RequestStore.byId(msg.requestId);
    final recipientId =
        msg.isCustomer ? request?.professionalId : request?.customerId;
    if (recipientId != null && recipientId.isNotEmpty) {
      NotificationStore.notifyChatMessage(
        msg.requestId,
        msg.senderName,
        recipientId,
        targetRole: msg.isCustomer ? 'professional' : 'client',
      );
    }
  }

  static void seedDemo(String requestId) {
    if (forRequest(requestId).isNotEmpty) return;
    send(
      requestId: requestId,
      senderId: 'customer',
      senderName: 'Feres',
      text: 'السلام عليكم، نحب نعرف قداش تقريبًا تاخو وقت الخدمة؟',
      isCustomer: true,
    );
    send(
      requestId: requestId,
      senderId: 'pro',
      senderName: 'Ahmed',
      text: 'وعليكم السلام، تقريبًا نهار.',
      isCustomer: false,
    );
  }

  /// Clears every in-memory chat room and session (used on logout).
  static void reset() {
    messages.value = {};
    sessions.value = {};
  }
}
