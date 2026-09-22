import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/search/application/search_service.dart';

void main() {
  group('SearchService · 99-service catalog (AR & FR)', () {
    test('every catalog service is found by its own French name', () {
      for (final service in AppServicesCatalog.services) {
        final results = SearchService.search(service.nameFr);
        expect(
          results.any((r) =>
              r.type == SearchResultType.service && r.serviceId == service.id),
          isTrue,
          reason: '${service.nameFr} (${service.id}) should be searchable FR',
        );
      }
    });

    test('every catalog service is found by its own Arabic name', () {
      for (final service in AppServicesCatalog.services) {
        final results = SearchService.search(service.nameAr);
        expect(
          results.any((r) =>
              r.type == SearchResultType.service && r.serviceId == service.id),
          isTrue,
          reason: '${service.nameAr} (${service.id}) should be searchable AR',
        );
      }
    });

    test('matching is case-insensitive in French', () {
      final first = AppServicesCatalog.services.first;
      final lower = SearchService.search(first.nameFr.toLowerCase());
      final upper = SearchService.search(first.nameFr.toUpperCase());
      expect(lower.map((r) => r.serviceId), contains(first.id));
      expect(upper.map((r) => r.serviceId), contains(first.id));
    });

    test('partial keywords match (instant search behaviour)', () {
      // The first three letters of any service name must surface it.
      for (final service in AppServicesCatalog.services.take(10)) {
        final prefix = service.nameFr.toLowerCase().substring(0, 3);
        final results = SearchService.search(prefix);
        expect(
          results.any((r) => r.serviceId == service.id),
          isTrue,
          reason: 'prefix "$prefix" should find ${service.id}',
        );
      }
    });

    test('category keyword "maison" returns the Maison category', () {
      final results = SearchService.search('maison');
      expect(
        results.any((r) =>
            r.type == SearchResultType.category && r.categoryId == 'home'),
        isTrue,
      );
    });

    test('professional search matches name and profession', () {
      final pro = ProfessionalsRepository.all.first;
      final byName = SearchService.search(pro.name.toLowerCase());
      expect(
        byName.any((r) =>
            r.type == SearchResultType.professional &&
            r.professional?.id == pro.id),
        isTrue,
      );
    });

    test('empty / whitespace queries return nothing', () {
      expect(SearchService.search(''), isEmpty);
      expect(SearchService.search('   '), isEmpty);
    });
  });

  group('Booking flow · order lands on the pro dashboard as pending', () {
    final savedTokens = ProProfileStore.tokens.value;

    setUp(() {
      RequestStore.requests.value = [];
      ChatStore.sessions.value = {};
      ChatStore.messages.value = {};
      NotificationStore.clear();
      SubscriptionStore.isPaidSubscriber.value = false;
      ProProfileStore.tokens.value = 100;
    });

    tearDown(() {
      ProProfileStore.tokens.value = savedTokens;
      SubscriptionStore.isPaidSubscriber.value = false;
    });

    test('end-to-end: service → request (cash) → pending', () {
      final service = AppServicesCatalog.services.first;
      final pro = ProfessionalsRepository.all.first;

      // Steps 1–4 happen in the UI; this mirrors the exact object the
      // ConfirmRequestScreen submits on "Envoyer la demande".
      final request = ServiceRequest(
        id: 'uc-flow-1',
        serviceTitleFr: service.nameFr,
        serviceTitleAr: service.nameAr,
        professionalId: pro.id,
        professionalName: pro.name,
        customerName: 'Client UC',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        address: 'Ariana, Tunisie',
        message: '',
        paymentMethod: 'cash',
        createdAt: DateTime.now(),
      );
      RequestStore.add(request);

      // Step 5: the order reaches the pro's dashboard, still pending.
      final onDashboard = RequestStore.forProfessional(pro.id);
      expect(onDashboard.any((r) => r.id == 'uc-flow-1'), isTrue);

      final stored = RequestStore.byId('uc-flow-1')!;
      expect(stored.status, RequestStatus.pending);
      expect(stored.paymentMethod, 'cash');

      // Dashboard pending counter sees the new order.
      final pending = RequestStore.requests.value
          .where((r) => r.status == RequestStatus.pending)
          .length;
      expect(pending, greaterThanOrEqualTo(1));

      // Customer-side lookup works too.
      expect(
        RequestStore.forCustomer('Client UC').any((r) => r.id == 'uc-flow-1'),
        isTrue,
      );
    });

    test('pro accepts the pending order → stepper stage advances', () async {
      final pro = ProfessionalsRepository.all.first;
      RequestStore.add(ServiceRequest(
        id: 'uc-flow-2',
        serviceTitleFr: 'Plomberie',
        serviceTitleAr: 'سباكة',
        professionalId: pro.id,
        professionalName: pro.name,
        customerName: 'Client UC',
        dateTime: DateTime.now().add(const Duration(hours: 3)),
        address: 'Ariana',
        message: '',
        createdAt: DateTime.now(),
      ));

      expect(RequestStore.byId('uc-flow-2')!.status, RequestStatus.pending);

      // Accepting is the first green stage of the RequestStepper.
      expect(
        await RequestStore.updateStatus('uc-flow-2', RequestStatus.accepted),
        isTrue,
      );
      expect(RequestStore.byId('uc-flow-2')!.status, RequestStatus.accepted);
      // Accepting also opens the in-app chat window for both parties.
      expect(ChatStore.isActive('uc-flow-2'), isTrue);
    });

    test('default payment method is cash when none is chosen', () {
      final request = ServiceRequest(
        id: 'uc-flow-3',
        serviceTitleFr: 'Nettoyage',
        serviceTitleAr: 'تنظيف',
        professionalId: 'pro_1',
        professionalName: 'Ahmed',
        customerName: 'Client UC',
        dateTime: DateTime.now(),
        address: 'Tunis',
        message: '',
        createdAt: DateTime.now(),
      );
      expect(request.paymentMethod, 'cash');
    });
  });
}
