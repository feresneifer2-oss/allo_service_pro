import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/search/application/search_service.dart';

void main() {
  setUp(() {
    UserStore.user.value = null;
    RequestStore.requests.value = [];
  });

  test('UserStore keeps the current local user', () {
    UserStore.set(
        name: 'Feres Test', phone: '+21600000000', email: 'test@example.com');

    expect(UserStore.displayName, 'Feres');
    expect(UserStore.user.value?.email, 'test@example.com');
  });

  test('RequestStore updates status and rating', () async {
    final request = ServiceRequest(
      id: 'request-1',
      serviceTitleFr: 'Électricité',
      serviceTitleAr: 'كهرباء',
      professionalId: 'pro-1',
      professionalName: 'Sami',
      customerName: 'Feres',
      dateTime: DateTime(2026, 8, 13),
      address: 'Ariana',
      message: 'Installation',
      createdAt: DateTime(2026, 8, 12),
    );

    await RequestStore.add(request);
    // AWAITED + REACHABLE PATH (CodeRabbit): `updateStatus` validates the
    // state machine — `pending → completed` is refused, so the test walks
    // the real lifecycle: accept the order first.
    expect(
      await RequestStore.updateStatus('request-1', RequestStatus.accepted),
      isTrue,
    );
    // RATING GATE (CodeRabbit): only FULLY COMPLETED orders are ratable —
    // `accepted → completed` is a legal transition, and rating no longer
    // flips the status itself.
    expect(
      await RequestStore.updateStatus('request-1', RequestStatus.completed),
      isTrue,
    );
    expect(
      await RequestStore.rate('request-1', 4.5, 'Très bon service'),
      isTrue,
    );

    final saved = RequestStore.requests.value.single;
    expect(saved.status, RequestStatus.completed);
    expect(saved.rating, 4.5);
    expect(saved.reviewComment, 'Très bon service');
  });

  test('SearchService returns nothing for an empty query', () {
    expect(SearchService.search('   '), isEmpty);
  });

  test('SearchService finds services from the full 99-service catalog', () {
    final results = SearchService.search('maçon');
    expect(results, isNotEmpty);
    expect(results.any((r) => r.serviceId == 'macon'), isTrue);
  });
}
