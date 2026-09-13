import 'package:flutter/material.dart';

import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart' show appLocale;

import '../domain/notification_model.dart';

class NotificationStore {
  NotificationStore._();

  static final notifications = ValueNotifier<List<NotificationModel>>([]);

  /// Resolves the notification copy from the active app locale at
  /// creation time (notifications persist their final wording).
  static String _text({required String fr, required String ar}) =>
      appLocale.value.languageCode == 'ar' ? ar : fr;

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

  /// Role-routed inbox: clients NEVER see professional-targeted
  /// notifications and vice-versa.
  ///
  /// [userId] is kept in the signature for future per-account routing;
  /// visibility is strictly driven by [NotificationModel.targetRole].
  static List<NotificationModel> getNotificationsForUser(
      String userId, UserRole role) {
    final roleKey = role == UserRole.professional ? 'professional' : 'client';
    return notifications.value
        .where((n) => n.targetRole == roleKey)
        .toList();
  }

  /// Convenience overload reading the active session from [UserStore].
  static List<NotificationModel> getNotificationsForCurrentUser() {
    final user = UserStore.user.value;
    if (user == null) return const [];
    return getNotificationsForUser(user.id, user.role ?? UserRole.client);
  }

  static int unreadCountForUser(String userId, UserRole role) =>
      getNotificationsForUser(userId, role).where((n) => !n.isRead).length;

  static List<NotificationModel> forRecipient(String recipientId) =>
      notifications.value.where((n) => n.recipientId == recipientId).toList();

  static void clear() {
    notifications.value = [];
  }

  // ── Client-targeted notifications ────────────────────────────────────
  static void notifyRequestSent(String requestId, String recipientId) {
    add(NotificationModel(
      id: '${DateTime.now().millisecondsSinceEpoch}_sent',
      title: _text(fr: 'Demande envoyée', ar: 'تم إرسال الطلب'),
      message: _text(
        fr: 'Votre demande a été envoyée avec succès — En attente du professionnel.',
        ar: 'تم إرسال طلبك بنجاح — في انتظار قبول الحرفي.',
      ),
      type: 'request',
      recipientId: recipientId,
      targetRole: 'client',
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyRequestAccepted(
      String requestId, String proName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _text(fr: 'Demande acceptée', ar: 'طلب مقبول'),
      message: _text(
        fr: '$proName a accepté votre demande. Vous pouvez discuter avec lui.',
        ar: 'قام $proName بقبول طلبك. يمكنك الآن الدردشة معه.',
      ),
      type: 'request',
      recipientId: recipientId,
      targetRole: 'client',
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyRequestRefused(
      String requestId, String proName, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _text(fr: 'Demande refusée', ar: 'طلب مرفوض'),
      message: _text(
        fr: '$proName a refusé votre demande.',
        ar: 'قام $proName برفض طلبك.',
      ),
      type: 'request',
      recipientId: recipientId,
      targetRole: 'client',
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  // ── Professional-targeted notifications ──────────────────────────────
  static void notifyNewRequest(
      String requestId, String customerName, String recipientId) {
    add(NotificationModel(
      id: '${DateTime.now().millisecondsSinceEpoch}_new',
      title: _text(fr: 'Nouvelle demande', ar: 'طلب جديد'),
      message: _text(
        fr: 'Nouvelle demande de $customerName',
        ar: 'لديك طلب جديد من $customerName',
      ),
      type: 'request',
      recipientId: recipientId,
      targetRole: 'professional',
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyChatMessage(
      String requestId, String senderName, String recipientId,
      {required String targetRole}) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _text(fr: 'Nouveau message', ar: 'رسالة جديدة'),
      message: _text(
        fr: 'Nouveau message de $senderName',
        ar: 'رسالة جديدة من $senderName',
      ),
      type: 'chat',
      recipientId: recipientId,
      targetRole: targetRole,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyTokenDeduction(
      String requestId, int tokensRemaining, String recipientId) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _text(fr: 'Tokens déduits', ar: 'خصم توكن'),
      message: _text(
        fr: '10 tokens déduits pour la confirmation. Solde restant : $tokensRemaining',
        ar: 'تم خصم 10 توكن. الرصيد المتبقي: $tokensRemaining',
      ),
      type: 'system',
      recipientId: recipientId,
      targetRole: 'professional',
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }

  static void notifyChatClosed(String requestId, String recipientId,
      {required String targetRole}) {
    add(NotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _text(fr: 'Conversation clôturée', ar: 'إغلاق المحادثة'),
      message: _text(
        fr: "L'administration a clôturé la conversation de cette demande. L'envoi de nouveaux messages est désactivé.",
        ar: 'قام المشرف بإغلاق محادثة هذا الطلب. لا يمكن إرسال رسائل جديدة.',
      ),
      type: 'system',
      recipientId: recipientId,
      targetRole: targetRole,
      requestId: requestId,
      createdAt: DateTime.now(),
    ));
  }
}
