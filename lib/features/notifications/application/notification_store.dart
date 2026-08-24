import 'package:flutter/material.dart';
import '../domain/notification_model.dart';

class NotificationStore {
  NotificationStore._();

  static final notifications = ValueNotifier<List<NotificationModel>>([]);

  static void add(NotificationModel notification) {
    final list = List<NotificationModel>.from(notifications.value);
    list.insert(0, notification);
    notifications.value = list;
  }

  static void markAsRead(String id) {
    notifications.value = notifications.value
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
  }

  static void markAllAsRead() {
    notifications.value =
        notifications.value.map((n) => n.copyWith(isRead: true)).toList();
  }

  static int get unreadCount =>
      notifications.value.where((n) => !n.isRead).length;

  static List<NotificationModel> forRecipient(String recipientId) =>
      notifications.value.where((n) => n.recipientId == recipientId).toList();

  static void clear() {
    notifications.value = [];
  }

  // Helper methods to create specific notifications
  static void notifyRequestAccepted(
      String requestId, String proName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'طلب مقبول',
      message: 'قام $proName بقبول طلبك. يمكنك الآن الدردشة معه.',
      type: 'request',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyRequestRefused(
      String requestId, String proName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'طلب مرفوض',
      message: 'قام $proName برفض طلبك.',
      type: 'request',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyNewRequest(
      String requestId, String customerName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'طلب جديد',
      message: 'لديك طلب جديد من $customerName',
      type: 'request',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyChatMessage(
      String requestId, String senderName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'رسالة جديدة',
      message: 'رسالة جديدة من $senderName',
      type: 'chat',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyTokenDeduction(
      String requestId, int tokensRemaining, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'خصم توكن',
      message: 'تم خصم 10 توكن. الرصيد المتبقي: $tokensRemaining',
      type: 'system',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyChatClosed(String requestId, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'إغلاق المحادثة',
      message: 'قام المشرف بإغلاق محادثة هذا الطلب. لا يمكن إرسال رسائل جديدة.',
      type: 'system',
      recipientId: recipientId,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }
}
