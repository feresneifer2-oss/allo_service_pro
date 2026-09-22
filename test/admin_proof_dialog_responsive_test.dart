import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';

/// Responsive-layout regression guard (CodeRabbit).
///
/// Renders the admin dashboard on a 320×480 viewport — the smallest phone
/// class — and exercises BOTH proof-inspection surfaces:
///  * tab 0 (`_ProManageCard` → `_showDocument`): the proof dialog must be
///    capped + scrollable and must render without any RenderFlex overflow;
///  * tab 1 (`_PendingDossier` → `_DetailRow`): a long localized payload row
///    must wrap instead of pushing past the card.
///
/// A regression here fails loudly: Flutter reports layout overflows as test
/// exceptions, which `tester.takeException()` also asserts against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('proof dialog survives a 320x480 viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    // One APPROVED pro (tab 0 → _ProManageCard → proof dialog) and one
    // PENDING pro (tab 1 → _PendingDossier → _DetailRow payload rows).
    AdminStore.pendingPros.value = <PendingProModel>[
      const PendingProModel(
        id: 'pp_tmp_ok',
        name: 'Test Approved',
        phone: '+21620000001',
        professionFr: 'Plombier',
        professionAr: 'سبّاك',
        city: 'Tunis',
        submittedAt: '01/01/2026',
        docImage: 'assets/images/proof_missing.png',
        status: 'approved',
      ),
      const PendingProModel(
        id: 'pp_tmp_pending',
        name: 'Test Pending',
        phone: '+21620000002',
        professionFr: 'Électricien',
        professionAr: 'كهربائي',
        city: 'Ariana',
        submittedAt: '02/01/2026',
        docImage: 'assets/images/proof_missing.png',
        status: 'pending',
        rejectionReason: 'Motif du refus très long qui dépasse la largeur '
            'disponible de la carte sur un écran de 320 pixels',
      ),
    ];

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardScreen()));
    await tester.pumpAndSettle();

    // ── Tab 0 (Professionnels): open the responsive proof dialog ──
    final docButton = find.byTooltip('Voir le document');
    expect(docButton, findsWidgets, reason: 'proof button must be rendered');
    await tester.tap(docButton.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'proof dialog must fit a 320x480 viewport');
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byType(InteractiveViewer), findsWidgets);

    // Close the dialog, then ── Tab 1 (En attente): dossier detail rows ──
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'dossier payload rows must wrap, never overflow');
  });
}
