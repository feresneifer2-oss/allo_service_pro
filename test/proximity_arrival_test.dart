import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/services/proximity_service.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

/// GPS proximity + auto-arrival regression tests.
///
/// Covers the strict guard clauses (cancelled/completed abort, exactly-once
/// flag), the < 20 m trigger with status flip to 'arrivé', the far-away
/// no-op, and the client notification routing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clientLat = 36.81897;
  const clientLng = 10.16579;

  ServiceRequest orderWithStatus(RequestStatus status) {
    return ServiceRequest(
      id: 'prox-1',
      serviceTitleFr: 'Plomberie',
      serviceTitleAr: 'سباكة',
      professionalId: 'pro_1',
      professionalName: 'Ahmed',
      customerName: 'Feres',
      customerId: 'user_1',
      dateTime: DateTime.now(),
      address: 'Ariana',
      message: '',
      createdAt: DateTime.now(),
      status: status,
    );
  }

  void seedOrder(RequestStatus status) {
    RequestStore.reset();
    NotificationStore.clear();
    ProximityService.reset();
    RequestStore.add(orderWithStatus(status));
    NotificationStore.clear(); // drop the add() chatter; isolate arrival
    ProximityService.debugSetTargetResolver(
      (order) => const ProximityTarget(
        clientLat: clientLat,
        clientLng: clientLng,
        customerId: 'user_1',
        customerName: 'Feres',
      ),
    );
    ProximityService.debugSetDistanceCalculator(
      (a, b, c, d) => 10.0, // inside the 20 m radius
    );
    ProximityService.debugSetArrivalNotifier((order, target) async {
      NotificationStore.notifyProArrived(
        order.id,
        order.professionalName,
        target.customerId,
      );
    });
  }

  tearDown(() {
    ProximityService.debugSetTargetResolver(null);
    ProximityService.debugResetDistanceCalculator();
    ProximityService.debugResetArrivalNotifier();
    ProximityService.reset();
  });

  group('guard clauses: terminal orders never trigger', () {
    test("cancelled ('annulée') aborts immediately", () async {
      seedOrder(RequestStatus.cancelled);
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(ProximityService.hasNotified('prox-1'), isFalse);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.cancelled);
      expect(NotificationStore.notifications.value, isEmpty);
    });

    test("completed ('terminée') aborts immediately", () async {
      seedOrder(RequestStatus.completed);
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(ProximityService.hasNotified('prox-1'), isFalse);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.completed);
      expect(NotificationStore.notifications.value, isEmpty);
    });

    test('unknown order id aborts without throwing', () async {
      seedOrder(RequestStatus.enRoute);
      await ProximityService.onProPosition(
        requestId: 'nope',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(ProximityService.hasNotified('nope'), isFalse);
    });
  });

  group('proximity trigger (< 20 m)', () {
    test('enRoute within radius flips to arrivé + notifies client once',
        () async {
      seedOrder(RequestStatus.enRoute);
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );

      expect(ProximityService.hasNotified('prox-1'), isTrue);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.arrived);
      expect(NotificationStore.notifications.value, hasLength(1));
      final n = NotificationStore.notifications.value.single;
      expect(n.targetRole, 'client');
      expect(n.requestId, 'prox-1');

      // Second fix for the same session: no duplicate.
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(NotificationStore.notifications.value, hasLength(1));
    });

    test('far-away fix does nothing', () async {
      seedOrder(RequestStatus.enRoute);
      ProximityService.debugSetDistanceCalculator(
        (a, b, c, d) => 500.0,
      );
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: 36.0,
        proLng: 10.0,
      );
      expect(ProximityService.hasNotified('prox-1'), isFalse);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.enRoute);
      expect(NotificationStore.notifications.value, isEmpty);
    });

    test('pending order never auto-arrives (no trip yet)', () async {
      seedOrder(RequestStatus.pending);
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(ProximityService.hasNotified('prox-1'), isFalse);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.pending);
    });
  });

  group('dispatch input validation (first attempt + retries)', () {
    ServiceRequest orderWithId(String id) => ServiceRequest(
          id: id,
          serviceTitleFr: 'Plomberie',
          serviceTitleAr: 'سباكة',
          professionalId: 'pro_1',
          professionalName: 'Ahmed',
          customerName: 'Feres',
          customerId: 'user_1',
          dateTime: DateTime.now(),
          address: 'Ariana',
          message: '',
          createdAt: DateTime.now(),
          status: RequestStatus.enRoute,
        );

    test('notifyArrival refuses a blank order id and never notifies', () async {
      var calls = 0;
      NotificationStore.clear();
      ProximityService.debugSetArrivalNotifier((o, t) async => calls++);

      final delivered = await ProximityService.notifyArrival(
        orderWithId(''),
        const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: 'user_1',
        ),
      );

      expect(delivered, isFalse);
      expect(calls, 0, reason: 'a malformed id never reaches the channel');
      expect(NotificationStore.notifications.value, isEmpty);
      expect(ProximityService.hasNotified(''), isFalse);
    });

    test('notifyArrival refuses a blank recipient id', () async {
      var calls = 0;
      NotificationStore.clear();
      ProximityService.debugSetArrivalNotifier((o, t) async => calls++);

      final delivered = await ProximityService.notifyArrival(
        orderWithId('prox-1'),
        const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: '   ',
        ),
      );

      expect(delivered, isFalse);
      expect(calls, 0, reason: 'a push addressed to nobody is refused');
    });

    test('notifyArrival refuses unverifiable coordinates', () async {
      var calls = 0;
      NotificationStore.clear();
      ProximityService.debugSetArrivalNotifier((o, t) async => calls++);

      // Null island (0, 0) — the classic missing-GPS placeholder.
      expect(
        await ProximityService.notifyArrival(
          orderWithId('prox-1'),
          const ProximityTarget(
              clientLat: 0, clientLng: 0, customerId: 'user_1'),
        ),
        isFalse,
      );
      // Non-finite coordinates can never describe a real position.
      expect(
        await ProximityService.notifyArrival(
          orderWithId('prox-1'),
          ProximityTarget(
              clientLat: double.nan,
              clientLng: clientLng,
              customerId: 'user_1'),
        ),
        isFalse,
      );
      // Out of range (latitude > 90).
      expect(
        await ProximityService.notifyArrival(
          orderWithId('prox-1'),
          const ProximityTarget(
              clientLat: 95.0, clientLng: clientLng, customerId: 'user_1'),
        ),
        isFalse,
      );
      expect(calls, 0);
    });

    test('notifyArrival refuses a target pinned to another order', () async {
      var calls = 0;
      NotificationStore.clear();
      ProximityService.debugSetArrivalNotifier((o, t) async => calls++);

      expect(
        await ProximityService.notifyArrival(
          orderWithId('prox-1'),
          const ProximityTarget(
            clientLat: clientLat,
            clientLng: clientLng,
            customerId: 'user_1',
            requestId: 'prox-OTHER',
          ),
        ),
        isFalse,
      );
      expect(calls, 0);
    });

    test('onProPosition rejects a blank request id', () async {
      seedOrder(RequestStatus.enRoute);
      await ProximityService.onProPosition(
        requestId: '   ',
        proLat: clientLat,
        proLng: clientLng,
      );

      expect(ProximityService.hasNotified('   '), isFalse);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.enRoute);
      expect(NotificationStore.notifications.value, isEmpty);
    });

    test('a blank recipient id blocks the status commit entirely', () async {
      seedOrder(RequestStatus.enRoute);
      // Valid coordinates, but no addressable recipient identity.
      ProximityService.debugSetTargetResolver(
        (order) => const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: '',
        ),
      );

      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );

      expect(RequestStore.byId('prox-1')!.status, RequestStatus.enRoute,
          reason: 'commit-before-notify must not commit an unaddressable push');
      expect(ProximityService.hasNotified('prox-1'), isFalse);
      expect(NotificationStore.notifications.value, isEmpty);
    });
    test('a queued retry re-validates its inputs', () async {
      RequestStore.reset();
      NotificationStore.clear();
      ProximityService.reset();
      RequestStore.add(orderWithId('prox-1'));
      NotificationStore.clear();

      var attempts = 0;
      ProximityService.debugSetArrivalNotifier((order, target) async {
        attempts++;
        throw StateError('push channel down');
      });
      ProximityService.debugSetDistanceCalculator((a, b, c, d) => 5.0);

      // Fix 1 — valid payload: the arrival is committed and the failing push
      // queues a bounded retry.
      ProximityService.debugSetTargetResolver(
        (order) => const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: 'user_1',
          requestId: 'prox-1',
        ),
      );
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(attempts, 1);
      expect(RequestStore.byId('prox-1')!.status, RequestStatus.arrived);
      expect(ProximityService.hasNotified('prox-1'), isTrue);

      // Fix 2 — the fresh target belongs to ANOTHER order: the queued retry is
      // refused before it can reach the channel.
      ProximityService.debugSetTargetResolver(
        (order) => const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: 'user_1',
          requestId: 'prox-OTHER',
        ),
      );
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(attempts, 1,
          reason: 'a foreign retry payload is never dispatched');

      // Fix 3 — valid payload + working channel: the retry really delivers.
      ProximityService.debugSetTargetResolver(
        (order) => const ProximityTarget(
          clientLat: clientLat,
          clientLng: clientLng,
          customerId: 'user_1',
          requestId: 'prox-1',
        ),
      );
      ProximityService.debugSetArrivalNotifier((order, target) async {
        attempts++;
        NotificationStore.notifyProArrived(
          order.id,
          order.professionalName,
          target.customerId,
        );
      });
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(attempts, 2);
      expect(NotificationStore.notifications.value, hasLength(1));

      // Fix 4 — the delivered retry cleared the ledger: nothing fires again.
      await ProximityService.onProPosition(
        requestId: 'prox-1',
        proLat: clientLat,
        proLng: clientLng,
      );
      expect(attempts, 2, reason: 'a delivered retry is not repeated');
    });
  });
}
