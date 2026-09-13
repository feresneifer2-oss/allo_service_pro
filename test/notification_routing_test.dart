import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

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

    final clientInbox = NotificationStore.getNotificationsForUser(
        'user_1', UserRole.client);
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
}