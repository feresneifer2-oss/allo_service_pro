import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';

void main() {
  group('B4 · ServiceRequest.copyWith integrity', () {
    final base = ServiceRequest(
      id: 'b4-1',
      serviceTitleFr: 'Plomberie',
      serviceTitleAr: 'سباكة',
      professionalId: 'pro_5',
      professionalName: 'Hatem Trabelsi',
      customerName: 'Client',
      dateTime: DateTime.now(),
      address: 'Ariana',
      message: '',
      paymentMethod: 'd17', // non-default choice must survive copies
      createdAt: DateTime.now(),
    );

    test('status update preserves the chosen payment method', () {
      final updated = base.copyWith(status: RequestStatus.accepted);
      expect(updated.paymentMethod, 'd17');
      expect(updated.status, RequestStatus.accepted);
    });

    test('copyWith never resets paymentMethod to the cash default', () {
      final updated = base.copyWith(reviewComment: 'Très bien');
      expect(updated.paymentMethod, 'd17');
      expect(updated.reviewComment, 'Très bien');
    });
  });

  group('B4 · specialty-restricted auto-assignment', () {
    test('forService(plombier) never returns a cross-specialty pro', () {
      final item = AppServicesCatalog.byId('plombier');
      expect(item, isNotNull);
      final fr = item!.nameFr.toLowerCase();
      final ar = item.nameAr;

      final matched = ProfessionalsRepository.forService('plombier');
      expect(matched, isNotEmpty);

      // Every returned pro must actually serve the requested specialty
      // (by catalog service id OR by profession label) - no electrician
      // sneaks into a plumber job.
      final crossSpecialty = matched.where((p) {
        final hasId = p.serviceIds.contains('plombier');
        final labelMatch = p.professionFr.toLowerCase().contains(fr) ||
            p.professionAr.contains(ar);
        return !hasId && !labelMatch;
      });
      expect(crossSpecialty, isEmpty,
          reason: 'auto-assignment must not pick a pro of another specialty');

      // Sanity: the known electrician (pro_4) is NOT among the results.
      expect(matched.where((p) => p.id == 'pro_4'), isEmpty);
    });
  });
}
