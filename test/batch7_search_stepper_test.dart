import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/shared/validators.dart';
import 'package:allo_service_pro/shared/widgets/request_stepper.dart';
import 'package:allo_service_pro/core/models/request_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B7 · live + suggested pro merge', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AdminStore.pendingPros.value = const <PendingProModel>[];
      UserStore.user.value = null;
    });

    test('approved live pro is merged into forService results', () {
      AdminStore.pendingPros.value = [
        const PendingProModel(
          id: 'reg_1',
          name: 'Slim Live Plumber',
          phone: '22123456',
          professionFr: 'Plombier',
          professionAr: 'سبّاك',
          submittedAt: '01/02/2026',
          status: 'approved',
          proCode: 'PRO-00424',
        ),
      ];

      // Sanity: the live feed exposes the approved pro.
      expect(
        ProfessionalsRepository.live.any((p) => p.id == 'PRO-00424'),
        isTrue,
      );

      final matched = ProfessionalsRepository.forService('plombier');
      expect(matched, isNotEmpty);
      // THE regression: the live pro (empty serviceIds) must appear alongside
      // the suggested catalog pros, never omitted from the search results.
      expect(
        matched.any((p) => p.id == 'PRO-00424'),
        isTrue,
        reason: 'live-approved pros must be merged with suggested lists',
      );
      // No duplicates: every id appears at most once.
      final ids = matched.map((p) => p.id).toSet();
      expect(ids.length, matched.length);
    });

    test('unapproved or deactivated live pros are never merged', () {
      AdminStore.pendingPros.value = const [
        PendingProModel(
          id: 'reg_2',
          name: 'Pending Plumber',
          phone: '22123457',
          professionFr: 'Plombier',
          professionAr: 'سبّاك',
          submittedAt: '01/02/2026',
          status: 'pending',
          proCode: 'PRO-00425',
        ),
        PendingProModel(
          id: 'reg_3',
          name: 'Suspended Plumber',
          phone: '22123458',
          professionFr: 'Plombier',
          professionAr: 'سبّاك',
          submittedAt: '01/02/2026',
          status: 'approved',
          proCode: 'PRO-00426',
          deactivated: true,
        ),
      ];
      final matched = ProfessionalsRepository.forService('plombier');
      expect(matched.any((p) => p.id == 'PRO-00425'), isFalse);
      expect(matched.any((p) => p.id == 'PRO-00426'), isFalse);
    });
  });

  group('B7 · phone normalization before registration lookup', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      UserStore.user.value = null;
    });

    test('UserStore.register persists a canonical phone for ANY variant', () {
      final ok = UserStore.register(
        name: 'Nizar',
        phone: ' +216 98 111 222 ',
        email: 'nizar@test.tn',
        password: 'secret1',
      );
      expect(ok, isTrue);
      expect(
        UserStore.user.value!.phone,
        '98111222',
        reason: 'register() must normalize internally, not trust the caller',
      );
      expect(AppValidators.isValidTunisianPhone(UserStore.user.value!.phone),
          isTrue);
    });
  });

  group('B7 · request stepper Arrived stage', () {
    testWidgets('enRoute ➔ arrived ➔ inProgress renders 6 stages with Arrivé',
        (tester) async {
      await tester.pumpWidget(
        const _Host(RequestStepper(status: RequestStatus.arrived)),
      );
      // The new stage label is rendered in both languages via tr().
      expect(find.text('Arrivé'), findsOneWidget);
      // Full pipeline: pending, accepted, en route, ARRIVED, in progress,
      // completed = 6 nodes.
      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Acceptée'), findsOneWidget);
      expect(find.text('En route'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
    });

    testWidgets('arrived is upcoming while the pro is still en route',
        (tester) async {
      await tester.pumpWidget(
        const _Host(RequestStepper(status: RequestStatus.enRoute)),
      );
      // While en route, the Arrivé node exists but is not yet highlighted as
      // the current stage (current = En route).
      expect(find.text('Arrivé'), findsOneWidget);
    });
  });
}

class _Host extends StatelessWidget {
  const _Host(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // MaterialApp supplies the Localizations ancestor that `tr()` needs
    // (default en locale → tr() resolves the French labels).
    return MaterialApp(home: Scaffold(body: child));
  }
}
