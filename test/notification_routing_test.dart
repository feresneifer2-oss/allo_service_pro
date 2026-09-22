import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Stands in for the production OneSignal transport: records what the remote
/// leg would have sent, and can simulate a dead network.
class _FakeTransport implements NotificationTransport {
  _FakeTransport({this.isConfigured = true, this.throwOnDeliver = false});

  @override
  final bool isConfigured;

  final bool throwOnDeliver;
  final List<NotificationModel> delivered = <NotificationModel>[];

  @override
  Future<bool> deliver(NotificationModel notification) async {
    if (throwOnDeliver) throw StateError('remote transport offline');
    delivered.add(notification);
    return true;
  }
}

void main() {
  setUp(() {
    RequestStore.requests.value = [];
    NotificationStore.clear();
    appLocale.value = const Locale('ar');
  });
  tearDown(() => appLocale.value = const Locale('fr'));

  ServiceRequest request({
    required String customerId,
    required String professionalId,
  }) {
    return ServiceRequest(
      id: 'route-1',
      serviceTitleFr: 'Plomberie',
      serviceTitleAr: 'سباكة',
      professionalId: professionalId,
      professionalName: 'Ahmed',
      customerName: 'Feres',
      customerId: customerId,
      dateTime: DateTime.now(),
      address: 'Ariana',
      message: '',
      createdAt: DateTime.now(),
    );
  }

  test('client request creates TWO role-routed notifications', () {
    RequestStore.add(
      request(customerId: 'user_1', professionalId: 'pro_1'),
    );

    final clientInbox =
        NotificationStore.getNotificationsForUser('user_1', UserRole.client);
    final proInbox = NotificationStore.getNotificationsForUser(
        'pro_1', UserRole.professional);

    // Client sees ONLY the success confirmation.
    expect(clientInbox, isNotEmpty);
    expect(clientInbox.map((n) => n.targetRole), everyElement('client'));
    expect(
      clientInbox.map((n) => n.title),
      contains('تم إرسال الطلب'),
    );
    expect(clientInbox.map((n) => n.title), isNot(contains('طلب جديد')));

    // Pro sees ONLY the incoming-order alert.
    expect(proInbox, isNotEmpty);
    expect(proInbox.map((n) => n.targetRole), everyElement('professional'));
    expect(proInbox.map((n) => n.title), contains('طلب جديد'));
    expect(proInbox.map((n) => n.title), isNot(contains('تم إرسال الطلب')));
  });

  test('pro-targeted notifications NEVER leak into the client inbox', () {
    NotificationStore.notifyNewRequest('r-9', 'Feres', 'pro_1');

    expect(
      NotificationStore.getNotificationsForUser('user_1', UserRole.client),
      isEmpty,
    );
    expect(
      NotificationStore.getNotificationsForUser('pro_1', UserRole.professional)
          .map((n) => n.title),
      contains('طلب جديد'),
    );
  });

  test('client-targeted notifications NEVER leak into the pro inbox', () {
    NotificationStore.notifyRequestSent('r-8', 'user_1');
    NotificationStore.notifyRequestAccepted('r-8', 'Ahmed', 'user_1');

    expect(
      NotificationStore.getNotificationsForUser('pro_1', UserRole.professional),
      isEmpty,
    );
    expect(
      NotificationStore.getNotificationsForUser('user_1', UserRole.client)
          .map((n) => n.targetRole),
      everyElement('client'),
    );
  });

  test('unread badge counts are role-routed too', () {
    NotificationStore.notifyNewRequest('r-9', 'Feres', 'pro_1');
    NotificationStore.notifyRequestSent('r-9', 'user_1');

    expect(
      NotificationStore.unreadCountForUser('user_1', UserRole.client),
      1,
    );
    expect(
      NotificationStore.unreadCountForUser('pro_1', UserRole.professional),
      1,
    );
  });

  group('arrival remote-transport seam (production target: OneSignal)', () {
    tearDown(() => NotificationStore.debugSetTransport(null));

    test('local-only by default: nothing leaves the device', () {
      expect(NotificationTransport, isNotNull); // the seam is documented API
      NotificationStore.notifyProArrived('r-arr', 'Ahmed', 'user_1');

      // The local inbox is the source of truth and is written synchronously.
      expect(NotificationStore.notifications.value, hasLength(1));
      expect(NotificationStore.notifications.value.single.targetRole, 'client');
    });

    test('a wired transport receives the arrival addressed to the customer',
        () async {
      final transport = _FakeTransport();
      NotificationStore.setTransport(transport);

      NotificationStore.notifyProArrived('r-arr', 'Ahmed', 'user_1');

      // Local write happens FIRST: the UI never waits on the network.
      expect(NotificationStore.notifications.value, hasLength(1));

      await Future<void>.delayed(Duration.zero);

      // Remote leg: addressed BY recipient id (OneSignal fan-out target), never
      // by a device-level login on the pro side.
      expect(transport.delivered, hasLength(1));
      final sent = transport.delivered.single;
      expect(sent.recipientId, 'user_1');
      expect(sent.targetRole, 'client');
      expect(sent.requestId, 'r-arr');
    });

    test('an unconfigured transport is never invoked', () async {
      final transport = _FakeTransport(isConfigured: false);
      NotificationStore.setTransport(transport);

      NotificationStore.notifyProArrived('r-off', 'Ahmed', 'user_1');
      await Future<void>.delayed(Duration.zero);

      expect(transport.delivered, isEmpty);
      expect(NotificationStore.notifications.value, hasLength(1));
    });

    test('a failing remote leg never breaks the committed local arrival',
        () async {
      NotificationStore.setTransport(_FakeTransport(throwOnDeliver: true));

      NotificationStore.notifyProArrived('r-fail', 'Ahmed', 'user_1');
      await Future<void>.delayed(Duration.zero);

      // Fire-and-forget contract: the arrival stays delivered locally and the
      // failed remote leg is left to the caller's bounded-retry policy.
      expect(NotificationStore.notifications.value, hasLength(1));
    });

    // ── Stable arrival key (locale-independent dedup) ────────────────────
    test('the arrival key is stable, locale-independent and IS the record id',
        () {
      final key = NotificationStore.arrivalKey('r-key');
      expect(key, contains('r-key'));

      appLocale.value = const Locale('fr');
      expect(NotificationStore.arrivalKey('r-key'), key,
          reason: 'a locale switch must never change the arrival identity');

      NotificationStore.notifyProArrived('r-key', 'Ahmed', 'user_1');
      expect(NotificationStore.notifications.value.single.id, key);
    });

    test('a re-dispatch stays deduped even across an AR->FR locale switch', () {
      NotificationStore.notifyProArrived('r-dup', 'Ahmed', 'user_1');
      expect(NotificationStore.notifications.value, hasLength(1));

      // The generated copy is locale-resolved, so the OLD title-based match
      // would log the same arrival twice after a language change.
      appLocale.value = const Locale('fr');
      NotificationStore.notifyProArrived('r-dup', 'Ahmed', 'user_1');

      expect(NotificationStore.notifications.value, hasLength(1),
          reason: 'one order => exactly one arrival record');
    });

    test('one arrival per order, even if the pro name changes between retries',
        () {
      NotificationStore.notifyProArrived('r-name', 'Ahmed', 'user_1');
      NotificationStore.notifyProArrived('r-name', 'Ahmed Ben Ali', 'user_1');

      expect(NotificationStore.notifications.value, hasLength(1));
      // The first, delivered wording is kept — a retry never rewrites history.
      expect(NotificationStore.notifications.value.single.message,
          contains('Ahmed'));
    });

    test('another client event of the SAME request never masks the arrival',
        () {
      // 'Demande envoyée' shares requestId, type 'request' and targetRole with
      // the arrival: keying on requestId + type alone would swallow it.
      NotificationStore.notifyRequestSent('r-shared', 'user_1');
      NotificationStore.notifyProArrived('r-shared', 'Ahmed', 'user_1');

      expect(NotificationStore.notifications.value, hasLength(2));
      expect(
        NotificationStore.notifications.value.map((n) => n.id),
        contains(NotificationStore.arrivalKey('r-shared')),
      );
    });

    test('a distinct order still gets its own arrival record', () {
      NotificationStore.notifyProArrived('r-a', 'Ahmed', 'user_1');
      NotificationStore.notifyProArrived('r-b', 'Ahmed', 'user_1');

      expect(NotificationStore.notifications.value, hasLength(2));
    });
  });
}
