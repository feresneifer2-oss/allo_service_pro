import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../../notifications/application/notification_store.dart';
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
        NotificationStore.notifyChatClosed(requestId, request.customerId);
      }
      NotificationStore.notifyChatClosed(requestId, request.professionalId);
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
    // Defense-in-depth: never persist messages into locked rooms (admin
    // closure, expiry, or unconfirmed order).
    if (!RequestStore.isChatAllowed(requestId)) return;

    final msg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      isCustomer: isCustomer,
    );

    final map = Map<String, List<ChatMessage>>.from(messages.value);
    map[requestId] = [...(map[requestId] ?? []), msg];
    messages.value = map;

    // Send notification about new message
    final request = RequestStore.byId(requestId);
    final recipientId =
        isCustomer ? request?.professionalId : request?.customerId;
    if (recipientId != null && recipientId.isNotEmpty) {
      NotificationStore.notifyChatMessage(requestId, senderName, recipientId);
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
}
