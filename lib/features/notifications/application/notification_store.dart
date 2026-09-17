import 'dart:async';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart' show appLocale;

import '../domain/notification_model.dart';

/// ─── Remote transport seam (production target: OneSignal) ──────────────────
///
/// Everything [NotificationStore] writes today is LOCAL: the in-app inbox,
/// held in memory. Arrival notifications are the first class of event that also
/// needs a REMOTE leg — the professional's device must reach the CUSTOMER's
/// device, which is what the production OneSignal transport does (server-side
/// fan-out addressed TO the customer id).
///
/// ARCHITECTURE GUARD — do not shortcut this:
///  * The local inbox write always happens first and stays the source of truth
///    for the UI. The remote leg is ADDITIVE and fire-and-forget.
///  * The remote leg is addressed BY [NotificationModel.recipientId]. The pro
///    device NEVER calls `OneSignalService.login()` with the customer identity
///    (see `ProximityService._defaultArrivalNotifier`): a device must never
///    adopt another account's push session.
///  * [deliver] must never throw — a dead network may not break an
///    already-committed local arrival. Bounded retries are the caller's job
///    (see `ProximityService`, which re-dispatches with validated inputs).
///
/// WIRING THE REAL THING: implement [deliver] with the OneSignal REST call and
/// register it through [NotificationStore.setTransport] (tests inject fakes via
/// [NotificationStore.debugSetTransport]). No other file has to change — this
/// stub exists precisely so the local seam can be swapped for transport.
abstract class NotificationTransport {
  /// Whether this build has a usable remote transport (defines/backend wired).
  bool get isConfigured;

  /// Delivers [notification] to its recipient remotely. Must never throw;
  /// returns true only when the remote leg confirmed acceptance.
  Future<bool> deliver(NotificationModel notification);
}

class NotificationStore {
  NotificationStore._();

  static final notifications = ValueNotifier<List<NotificationModel>>([]);

  /// Registered remote transport (production: OneSignal).
  ///
  /// `null` — the default — means a local-only build: notifications reach the
  /// in-app inbox and nothing leaves the device. See [NotificationTransport].
  static NotificationTransport? _transport;

  /// Production wiring point for the remote transport.
  static void setTransport(NotificationTransport transport) {
    _transport = transport;
  }

  /// Test hook: injects (or clears, with `null`) the remote transport.
  @visibleForTesting
  static void debugSetTransport(NotificationTransport? transport) {
    _transport = transport;
  }

  /// Resolves the notification copy from the active app locale at
  /// creation time (notifications persist their final wording).
  static String _text({required String fr, required String ar}) =>
      appLocale.value.languageCode == 'ar' ? ar : fr;

  static void add(NotificationModel notification) {
    final list = List<NotificationModel>.from(notifications.value);
    list.insert(0, notification);
    notifications.value = list;
  }

  /// Writes [notification] to the local inbox FIRST (unless it already landed,
  /// see [local]), then — only when a remote transport is configured — fires
  /// the outgoing remote leg and REPORTS its outcome.
  ///
  /// The local write is never awaited on the network: by the time this returns
  /// the local arrival is already committed, so a slow or absent network can
  /// never delay or lose it.
  ///
  /// Returns true when the arrival is fully handled — the transport confirmed
  /// acceptance, or this is a local-only build (no transport configured).
  /// A refused (`false`) or failed (thrown) remote leg returns false so the
  /// caller's bounded-retry policy (`ProximityService._dispatchArrival`) can
  /// re-dispatch it: swallowing the failure here would make that documented
  /// retry unreachable, silently losing the customer's push.
  static Future<bool> _addLocallyThenDispatchRemote(
    NotificationModel notification, {
    bool local = true,
  }) async {
    if (local) add(notification);
    final transport = _transport;
    if (transport == null || !transport.isConfigured) return true;
    try {
      final delivered = await transport.deliver(notification);
      if (!delivered) {
        AppLogger.warn(
          'NotificationStore',
          'remote transport refused arrival ${notification.id} '
          '(recipient ${notification.recipientId})',
        );
      }
      return delivered;
    } catch (error) {
      // A transport must never be able to break the local inbox write — but a
      // failed remote leg must stay VISIBLE to the retry owner.
      AppLogger.warn(
        'NotificationStore',
        'remote transport failed for ${notification.id}: $error',
      );
      return false;
    }
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

  /// Stable, locale-independent identity of the ARRIVAL event of [requestId].
  ///
  /// Used BOTH as the local record id and as the dedup key, so the key can
  /// never drift from the record it protects. Deliberately NOT derived from:
  ///  * [NotificationModel.title] / [NotificationModel.message] — they are
  ///    resolved from the ACTIVE LOCALE at creation time (see [_text]), so
  ///    switching FR <-> AR would change the key and re-log the same arrival;
  ///  * `requestId + type` alone — every client event of one request shares
  ///    `type == 'request'`, so 'Demande envoyée' would MASK the arrival.
  ///
  /// One order => exactly one arrival record, whatever the locale, the pro's
  /// display name or the number of transport retries.
  static String arrivalKey(String requestId) => 'req_${requestId}__pro_arrived';

  /// Client-facing ARRIVAL notification — the one local event that also owns a
  /// remote leg: it lands in the pro's in-app inbox locally and, once a
  /// [NotificationTransport] is wired, reaches the CUSTOMER's device remotely.
  ///
  /// The local write is authoritative and never waits on the network (see
  /// [_addLocallyThenDispatchRemote]). Returns true when the arrival is fully
  /// handled, false when the remote leg was refused/failed and the caller must
  /// re-dispatch it on its own bounded-retry schedule.
  ///
  /// Idempotent per order: a re-dispatch of a previously failed arrival skips
  /// the local write (it already landed, see [arrivalKey]), so a retry can
  /// never stack a duplicate arrival in the customer's inbox — while the remote
  /// leg is still attempted on every call.
  static Future<bool> notifyProArrived(
      String requestId, String proName, String recipientId) {
    final id = arrivalKey(requestId);
    final notification = NotificationModel(
      id: id,
      title: _text(fr: 'Professionnel arrivé', ar: 'وصل الحرفي'),
      message: _text(
        fr: '$proName est arrivé à votre adresse.',
        ar: 'وصل $proName إلى عنوانك.',
      ),
      type: 'request',
      recipientId: recipientId,
      targetRole: 'client',
      requestId: requestId,
      createdAt: DateTime.now(),
    );
    // Stable key match — never on generated copy (title/message) or on
    // `type`, both of which collide across the events of one request.
    final alreadyLanded = notifications.value.any((n) => n.id == id);
    return _addLocallyThenDispatchRemote(
      notification,
      local: !alreadyLanded,
    );
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
