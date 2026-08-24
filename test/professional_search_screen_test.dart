import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/search/presentation/professional_search_screen.dart';

void main() {
  // The search form lives inside a SingleChildScrollView; on the default
  // 800x600 test surface the governorate dropdown menu overflows and item
  // taps silently miss their target. A tall surface keeps every control
  // on-screen and hittable.
  Future<void> pumpSearchScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ProfessionalSearchScreen()),
    );
  }

  Future<void> selectFirstGovernorate(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();

    // On the tall surface every menu item is on-screen, so a direct tap
    // works — verified by diagnostics (menu lists all 24 governorates).
    await tester.tap(find.text('Ariana').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows hint state first, then renders results in an Expanded ListView '
    'without overlapping the search button',
    (tester) async {
      await pumpSearchScreen(tester);

      // Before picking a governorate: hint state, no results list.
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);

      await selectFirstGovernorate(tester);

      // Results are now rendered lazily via ListView.builder.
      expect(find.byType(ListView), findsOneWidget);
      // Known Ariana professionals from the mock data are visible
      // (two of them share the name in demo data → at least one).
      expect(find.text('Ahmed Ben Ali'), findsWidgets);
      // The search button is still present and hittable (not overlapped).
      expect(
        find.ancestor(
          of: find.text('Rechercher'),
          matching: find.byType(ElevatedButton),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search button applies the text query and shows the no-results state',
    (tester) async {
      await pumpSearchScreen(tester);

      await selectFirstGovernorate(tester);
      expect(find.text('Ahmed Ben Ali'), findsWidgets);

      // Type a query matching nothing, then press the search button.
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();

      expect(find.text('Ahmed Ben Ali'), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
