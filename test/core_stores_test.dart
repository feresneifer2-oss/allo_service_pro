import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/booking/application/booking_store.dart';
import 'package:allo_service_pro/features/booking/models/booking_model.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/search/application/search_service.dart';

void main() {
  setUp(() {
    UserStore.user.value = null;
    BookingStore.bookings.value = [];
    RequestStore.requests.value = [];
  });

  test('UserStore keeps the current local user', () {
    UserStore.set(name: 'Feres Test', phone: '+21600000000', email: 'test@example.com');

    expect(UserStore.displayName, 'Feres');
    expect(UserStore.user.value?.email, 'test@example.com');
  });

  test('BookingStore inserts the newest booking first', () {
    final booking = BookingModel(
      id: 'booking-1',
      serviceTitle: 'Plomberie',
      professionalName: 'Ahmed',
      address: 'Tunis',
      dateTime: DateTime(2026, 8, 13),
      note: 'Urgent',
    );

    BookingStore.add(booking);

    expect(BookingStore.bookings.value, hasLength(1));
    expect(BookingStore.bookings.value.first.id, 'booking-1');
    expect(BookingStore.bookings.value.first.status, 'pending');
  });

  test('RequestStore updates status and rating', () {
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

    RequestStore.add(request);
    RequestStore.updateStatus('request-1', RequestStatus.completed);
    RequestStore.rate('request-1', 4.5, 'Très bon service');

    final saved = RequestStore.requests.value.single;
    expect(saved.status, RequestStatus.completed);
    expect(saved.rating, 4.5);
    expect(saved.reviewComment, 'Très bon service');
  });

  test('SearchService returns nothing for an empty query', () {
    expect(SearchService.search('   '), isEmpty);
  });
}
