import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

ServiceRequest _request(String id,
    {RequestStatus status = RequestStatus.pending}) {
  return ServiceRequest(
    id: id,
    serviceTitleFr: 'Peinture',
    serviceTitleAr: 'دهان',
    professionalId: 'pro_1',
    professionalName: 'Ahmed Ben Ali',
    customerName: 'Feres',
    dateTime: DateTime(2026, 8, 24, 10),
    address: 'Ariana',
    message: 'Devis rapide',
    createdAt: DateTime(2026, 8, 23),
    status: status,
  );
}

void main() {
  final savedTokens = ProProfileStore.tokens.value;

  setUp(() {
    RequestStore.requests.value = [];
    ChatStore.sessions.value = {};
    ChatStore.messages.value = {};
    NotificationStore.clear();
    ProProfileStore.tokens.value = 100; // headroom for confirmation costs
  });

  tearDown(() {
    ProProfileStore.tokens.value = savedTokens;
  });

  group('RequestStore.isChatAllowed · status layer', () {
    test('unknown request id is rejected', () {
      expect(RequestStore.isChatAllowed('ghost'), isFalse);
    });

    test('pending order without confirmation stays locked', () {
      RequestStore.add(_request('r-pending'));
      expect(RequestStore.isChatAllowed('r-pending'), isFalse);
    });

    test('every live status opens the chat once the session is activated',
        () {
      const liveStatuses = [
        RequestStatus.accepted,
        RequestStatus.enRoute,
        RequestStatus.arrived,
        RequestStatus.inProgress,
      ];

      for (final status in liveStatuses) {
        final id = 'r-${status.name}';
        RequestStore.add(_request(id, status: status));
        ChatStore.activate(id);

        expect(RequestStore.isChatAllowed(id), isTrue,
            reason: '$status should allow chat with an active session');
      }
    });

    test('completed request never opens a chat, even with a live session',
        () {
      RequestStore.add(_request('r-done', status: RequestStatus.completed));
      ChatStore.activate('r-done'); // force a live session

      expect(RequestStore.isChatAllowed('r-done'), isFalse);
    });

    test('cancelled request never opens a chat, even with a live session',
        () {
      RequestStore.add(
          _request('r-cancelled', status: RequestStatus.cancelled));
      ChatStore.activate('r-cancelled');

      expect(RequestStore.isChatAllowed('r-cancelled'), isFalse);
    });

    test('refused request never opens a chat', () {
      RequestStore.add(_request('r-refused', status: RequestStatus.refused));
      ChatStore.activate('r-refused');

      expect(RequestStore.isChatAllowed('r-refused'), isFalse);
    });
  });

  group('RequestStore.isChatAllowed · session layer (real flow)', () {
    test('confirming a pending order unlocks the chat and costs 10 tokens',
        () {
      RequestStore.add(_request('r-flow'));

      expect(RequestStore.isChatAllowed('r-flow'), isFalse);

      final confirmed = RequestStore.updateStatus(
        'r-flow',
        RequestStatus.accepted,
      );

      expect(confirmed, isTrue);
      expect(ProProfileStore.tokens.value, 90); // 100 - 10
      expect(ChatStore.isActive('r-flow'), isTrue);
      expect(RequestStore.isChatAllowed('r-flow'), isTrue);
    });

    test('completing the job closes the chat window automatically', () {
      RequestStore.add(_request('r-complete'));
      RequestStore.updateStatus('r-complete', RequestStatus.accepted);
      expect(RequestStore.isChatAllowed('r-complete'), isTrue);

      RequestStore.updateStatus('r-complete', RequestStatus.completed);

      expect(ChatStore.isActive('r-complete'), isFalse);
      expect(RequestStore.isChatAllowed('r-complete'), isFalse);
    });

    test('cancelling the job closes the chat window automatically', () {
      RequestStore.add(_request('r-cancel'));
      RequestStore.updateStatus('r-cancel', RequestStatus.accepted);
      expect(RequestStore.isChatAllowed('r-cancel'), isTrue);

      RequestStore.updateStatus('r-cancel', RequestStatus.cancelled);

      expect(RequestStore.isChatAllowed('r-cancel'), isFalse);
    });

    test('the 48h window closing locks an otherwise-live order', () {
      RequestStore.add(_request('r-expiry'));
      RequestStore.updateStatus('r-expiry', RequestStatus.accepted);
      expect(RequestStore.isChatAllowed('r-expiry'), isTrue);

      // Simulate time passing beyond the window: replace the session with
      // one activated 49h ago (window = 48h by default).
      final map = Map<String, ChatSession>.from(ChatStore.sessions.value);
      map['r-expiry'] = ChatSession(
        requestId: 'r-expiry',
        active: true,
        activatedAt: DateTime.now().subtract(const Duration(hours: 49)),
      );
      ChatStore.sessions.value = map;

      expect(ChatStore.isActive('r-expiry'), isFalse);
      expect(RequestStore.isChatAllowed('r-expiry'), isFalse);
    });
  });
}