import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/features/rating/presentation/rating_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/request_detail_screen.dart';

/// WIDGET-LEVEL CONTRACT OF THE REAL REVIEW & RATING FLOW.
///
/// WHAT IS UNDER TEST (no stand-in widget is created here):
///   • `RatingScreen` — `lib/features/rating/presentation/rating_screen.dart`,
///     the sheet the customer reaches from `RequestDetailScreen`'s « Évaluer »
///     action (`RequestDetailScreen` → `Navigator.push(RatingScreen(...))`);
///   • `RequestStore.rate` — the ONLY production call the sheet makes on
///     submit, and therefore the observable effect every submission assertion
///     reads (`ServiceRequest.rating` / `reviewComment`).
///
/// DETERMINISM (no `Future.delayed`, no real clock, no network):
///   • the suite runs LOCAL-ONLY: `ConnectivityStore.debugSetOnline(false)`
///     plus an uninitialized Supabase client (`OrdersRepository.isConfigured`
///     is false) makes `RequestStore.rate` skip its mirror branch entirely, so
///     the recorded review stays in memory and no I/O is scheduled;
///   • the store is seeded directly (the same seam `core_stores_test.dart`
///     uses) instead of driving `RequestStore.add`, so no notification /
///     persistence side effect can leak into the assertions;
///   • SnackBar auto-hide timers are drained on the FAKE test clock before a
///     test ends, so no pending timer survives into the next one;
///   • `_RequestWriteSpy` counts writes to `RequestStore.requests`, which is
///     what proves « exactly one submission » instead of a mere value check.
///
/// The sheet is always opened by PUSHING it over a host route, exactly like the
/// real entry point does: that is what makes « the sheet closed » and « the
/// host is still there » observable (a lost/duplicated pop would fail).
const String _hostLabel = 'ACCUEIL';
const String _orderId = 'order-rating-1';

/// A realistic completed order — the ONLY state `RequestStore.rate` accepts.
ServiceRequest _order({
  RequestStatus status = RequestStatus.completed,
  double? rating,
  String? reviewComment,
}) =>
    ServiceRequest(
      id: _orderId,
      serviceTitleFr: 'Électricité',
      serviceTitleAr: 'كهرباء',
      professionalId: 'PRO-2001',
      professionalName: 'Ahmed Ben Ali',
      customerName: 'Feres',
      dateTime: DateTime(2026, 9, 20, 14, 30),
      address: 'Ariana, Tunis',
      message: 'Installation de deux prises',
      status: status,
      rating: rating,
      reviewComment: reviewComment,
      createdAt: DateTime(2026, 9, 19, 9),
    );

void _seed(List<ServiceRequest> orders) => RequestStore.requests.value = orders;

/// The five star widgets of the review row (filled OR outlined) — the row is
/// always 5 icons, whatever the current selection is, so this finder stays
/// index-stable while the selection changes.
Finder _starIcons() => find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          (widget.icon == Icons.star_rounded ||
              widget.icon == Icons.star_outline_rounded),
    );

/// The row decoded top-down / left-right: `star_rounded` = selected.
List<IconData?> _starRow(WidgetTester tester) => _starIcons()
    .evaluate()
    .map((element) => (element.widget as Icon).icon)
    .toList(growable: false);

/// Counts every write to [RequestStore.requests] while installed — the single
/// observable effect of a recorded review. `1` at the end of a submission is
/// what « exactly one review was recorded » means (a second `rate` call would
/// fire the notifier again, even with an identical value).
///
/// Install it AFTER seeding the store: the seed is a write too, and only the
/// review itself must be counted.
class _RequestWriteSpy {
  int writes = 0;

  void _handle() => writes++;

  void install() {
    RequestStore.requests.addListener(_handle);
    addTearDown(() => RequestStore.requests.removeListener(_handle));
  }

  /// Forgets everything counted so far — used when a test re-seeds the store
  /// between two phases and only the review writes matter.
  void reset() => writes = 0;
}

/// The REAL app configuration (see `main.dart`): the project ships `fr` + `ar`
/// with the `flutter_localizations` delegates, so `Localizations.localeOf`
/// resolves to French and `tr(...)` renders the French labels — instead of the
/// English-only defaults, which have no `fr` support at all (every `AppBar` /
/// `TextField` would assert `debugCheckHasMaterialLocalizations`).
Widget _app({
  required Widget home,
  Locale locale = const Locale('fr'),
}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const <Locale>[Locale('fr'), Locale('ar')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// Pushes the REAL [RatingScreen] over a host route (how [RequestDetailScreen]
/// does it) and settles, so every test starts from the sheet being on top.
Future<void> _openSheet(
  WidgetTester tester, {
  String requestId = _orderId,
  Size surface = const Size(390, 844),
  Locale locale = const Locale('fr'),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RatingScreen(requestId: requestId),
                ),
              ),
              child: const Text(_hostLabel),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_hostLabel));
  await tester.pumpAndSettle();
}

/// Drains the SnackBar auto-hide timer on the fake clock (never a real delay),
/// so a test never ends with a pending timer.
Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RequestStore.requests.value = [];
    // LOCAL-ONLY execution (see the file header): the review is recorded in
    // memory and the Supabase mirror branch of `RequestStore.rate` is skipped.
    ConnectivityStore.debugSetOnline(false);
  });

  tearDown(() {
    RequestStore.requests.value = [];
    ConnectivityStore.debugSetOnline(true);
  });

  group('A. initial rendering', () {
    testWidgets(
        'renders the real review sheet: heading, 5 stars, comment field and '
        'one submit action', (tester) async {
      _seed([_order()]);
      await _openSheet(tester);

      // The REAL screen is mounted (not a stand-in).
      expect(find.byType(RatingScreen), findsOneWidget);
      expect(find.text('Évaluez votre expérience'), findsOneWidget); // AppBar
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Service terminé'), findsOneWidget);

      // Five stars, each inside a tappable IconButton, all selected by
      // default (5/5 is the sheet's initial state).
      expect(_starIcons(), findsNWidgets(5));
      expect(
        find.ancestor(of: _starIcons(), matching: find.byType(IconButton)),
        findsNWidgets(5),
      );
      expect(_starRow(tester), everyElement(Icons.star_rounded));

      // Optional multi-line comment box.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Commentaire (optionnel)'), findsOneWidget);

      // Exactly one submit action, armed.
      final submit = find.widgetWithText(ElevatedButton, 'Envoyer');
      expect(submit, findsOneWidget);
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

      expect(tester.takeException(), isNull);
    });

    testWidgets('stays overflow-free on a small phone surface (body scrolls)',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester, surface: const Size(360, 640));

      expect(find.byType(RatingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The submit action is REACHABLE by scrolling: the body is a ListView,
      // so a short viewport must not overflow it.
      final submit = find.widgetWithText(ElevatedButton, 'Envoyer');
      await tester.scrollUntilVisible(
        submit,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(submit, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'renders the Arabic surface of the same sheet when the app '
        'language is ar', (tester) async {
      _seed([_order()]);
      await _openSheet(tester, locale: const Locale('ar'));

      expect(find.text('قيّم تجربتك'), findsOneWidget); // AppBar
      expect(find.text('الخدمة مكتملة'), findsOneWidget);
      expect(find.text('تعليق (اختياري)'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'إرسال'), findsOneWidget);
      expect(_starIcons(), findsNWidgets(5));
      // The whole sheet follows the Arabic direction, not just its strings.
      expect(
        Directionality.of(tester.element(find.byType(RatingScreen))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('B. rating interaction', () {
    testWidgets(
        'tapping the Nth star selects exactly N/5 (1-based, left→right)',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester);
      final spy = _RequestWriteSpy()..install();

      // Default state is a full 5/5 — asserted here too so the loop below
      // proves a CHANGE, not a coincidence.
      expect(_starRow(tester), everyElement(Icons.star_rounded));

      for (var stars = 1; stars <= 5; stars++) {
        await tester.tap(_starIcons().at(stars - 1));
        await tester.pump();

        expect(
          _starRow(tester),
          <IconData>[
            for (var i = 0; i < 5; i++)
              i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
          ],
          reason: '$stars/5 selected by tapping star n°$stars',
        );
      }

      // Selection is LOCAL state: the store is untouched until submit.
      expect(spy.writes, 0);
      expect(RequestStore.byId(_orderId)!.rating, isNull);
      expect(RequestStore.byId(_orderId)!.reviewComment, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the 4th star selects 4/5 — the OUTLINED one is the 5th',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester);

      await tester.tap(_starIcons().at(3)); // 4th star
      await tester.pump();

      expect(_starRow(tester), <IconData>[
        Icons.star_rounded,
        Icons.star_rounded,
        Icons.star_rounded,
        Icons.star_rounded,
        Icons.star_outline_rounded,
      ]);

      // Positional proof (the row reads left → right): the single dimmed star
      // is the RIGHT-MOST one, and the four selected ones sit to its left.
      final row = _starIcons().evaluate().map((e) => e.widget).toList();
      final leftMostSelectedX = tester.getCenter(find.byWidget(row.first)).dx;
      final lastStar = row.last;
      final lastStarX = tester.getCenter(find.byWidget(lastStar)).dx;
      expect((lastStar as Icon).icon, Icons.star_outline_rounded);
      for (final star in row.take(4)) {
        expect(tester.getCenter(find.byWidget(star)).dx, lessThan(lastStarX));
      }
      expect(leftMostSelectedX, lessThan(lastStarX));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the selection is free: 5 → 2 → 4 all repaint the same row',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester);

      int filled() => find.byIcon(Icons.star_rounded).evaluate().length;

      await tester.tap(_starIcons().at(1)); // 2/5
      await tester.pump();
      expect(filled(), 2);

      await tester.tap(_starIcons().at(3)); // 4/5 (raising the selection back)
      await tester.pump();
      expect(filled(), 4);

      await tester.tap(_starIcons().at(4)); // 5/5
      await tester.pump();
      expect(filled(), 5);
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('C. review input', () {
    testWidgets('accepts a realistic customer review in the comment box',
        (tester) async {
      const review = 'Travail très soigné et ponctuel, prix honnête. '
          'Il a tout nettoyé avant de partir : je recommande vivement.';
      _seed([_order()]);
      await _openSheet(tester);

      expect(find.text('Commentaire (optionnel)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), review);
      await tester.pump();

      // The text is accepted, shown by the field and owned by its controller.
      expect(find.text(review), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, review);
      expect(field.maxLines, 4); // a real multi-line review box

      // Typing alone never records anything.
      expect(RequestStore.byId(_orderId)!.reviewComment, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the box is editable: clearing it brings the hint back',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField), 'Premier avis');
      await tester.pump();
      expect(find.text('Premier avis'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Premier avis'), findsNothing);
      expect(find.text('Commentaire (optionnel)'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('D. submission', () {
    testWidgets(
        'a completed order: 4/5 + the comment are recorded, the sheet closes '
        'and the customer is thanked', (tester) async {
      final spy = _RequestWriteSpy();
      _seed([_order()]);
      spy.install();
      await _openSheet(tester);

      await tester.tap(_starIcons().at(3)); // 4/5
      await tester.enterText(
          find.byType(TextField), '  Prestation impeccable. ');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Envoyer'));
      await tester.pumpAndSettle();

      // THE SUBMISSION EFFECT: the real store now carries the review.
      final saved = RequestStore.byId(_orderId)!;
      expect(saved.rating, 4.0);
      expect(saved.reviewComment, 'Prestation impeccable.'); // trimmed
      expect(saved.status, RequestStatus.completed); // rating never flips it
      expect(spy.writes, 1); // exactly ONE submission

      // The sheet closed, and ONLY it: the host route survived the pop.
      expect(find.byType(RatingScreen), findsNothing);
      expect(find.text(_hostLabel), findsOneWidget);
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainSnackBars(tester);
    });

    testWidgets('the comment is optional: an untouched box submits as empty',
        (tester) async {
      _seed([_order()]);
      await _openSheet(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Envoyer'));
      await tester.pumpAndSettle();

      final saved = RequestStore.byId(_orderId)!;
      expect(saved.rating, 5.0); // the default selection is submitted as-is
      expect(saved.reviewComment, isEmpty);
      expect(find.byType(RatingScreen), findsNothing);
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainSnackBars(tester);
    });

    testWidgets(
        'an in-progress order is refused: no write, explicit error, the sheet '
        'stays open and re-arms for the retry', (tester) async {
      final spy = _RequestWriteSpy();
      _seed([_order(status: RequestStatus.inProgress)]);
      spy.install();
      await _openSheet(tester);

      final submit = find.widgetWithText(ElevatedButton, 'Envoyer');
      await tester.tap(_starIcons().at(2)); // 3/5
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(
        find.text('Seuls les services terminés peuvent être évalués.'),
        findsOneWidget,
      );
      final refused = RequestStore.byId(_orderId)!;
      expect(refused.rating, isNull); // no phantom review
      expect(refused.reviewComment, isNull);
      expect(refused.status, RequestStatus.inProgress); // state machine intact
      expect(spy.writes, 0);
      expect(find.byType(RatingScreen), findsOneWidget); // still open
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
      await _drainSnackBars(tester);

      // ...and once the service really IS completed, the retry goes through
      // with the rating the customer had already picked (no dead-end).
      _seed([_order()]);
      await tester.pump();
      spy.reset(); // the re-seed above is not a review
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(RequestStore.byId(_orderId)!.rating, 3.0);
      expect(RequestStore.byId(_orderId)!.reviewComment, isEmpty);
      expect(spy.writes, 1);
      expect(find.byType(RatingScreen), findsNothing);
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainSnackBars(tester);
    });

    testWidgets(
        'an unknown request id is refused exactly like a non-completed one '
        '(never a crash)', (tester) async {
      _seed(const <ServiceRequest>[]);
      await _openSheet(tester, requestId: 'order-that-does-not-exist');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Envoyer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Seuls les services terminés peuvent être évalués.'),
        findsOneWidget,
      );
      expect(find.byType(RatingScreen), findsOneWidget);
      expect(RequestStore.requests.value, isEmpty);
      expect(tester.takeException(), isNull);

      await _drainSnackBars(tester);
    });

    testWidgets(
        'a rapid double tap on Envoyer never records twice nor pops two '
        'routes', (tester) async {
      final spy = _RequestWriteSpy();
      _seed([_order()]);
      spy.install();
      await _openSheet(tester);

      final submit = find.widgetWithText(ElevatedButton, 'Envoyer');
      await tester.tap(submit);
      // The second tap is issued immediately: whichever interleaving happens
      // (it lands on the still-visible sheet and is swallowed by the in-flight
      // lock, or the sheet is already leaving), the contract is the same —
      // ONE review, ONE popped route, no exception.
      await tester.tap(submit, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(spy.writes, lessThanOrEqualTo(1));
      expect(RequestStore.byId(_orderId)!.rating, isNotNull);
      expect(find.byType(RatingScreen), findsNothing);
      expect(find.text(_hostLabel), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _drainSnackBars(tester);
    });
  });

  group('E. the real entry point (RequestDetailScreen)', () {
    Future<void> pumpDetail(WidgetTester tester, String requestId) async {
      // The project's widget-test convention for full screens (see
      // `professional_search_screen_test.dart`): the test font is wider than
      // Roboto, so a narrow surface makes fixed-width rows (the order stepper)
      // overflow for reasons that have nothing to do with the behaviour here.
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(home: RequestDetailScreen(requestId: requestId)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'offers « Évaluer » for a completed unrated order and opens the real '
        'sheet', (tester) async {
      _seed([_order()]);
      await pumpDetail(tester, _orderId);

      final rate = find.widgetWithText(ElevatedButton, 'Évaluer');
      expect(rate, findsOneWidget);

      await tester.tap(rate);
      await tester.pumpAndSettle();

      expect(find.byType(RatingScreen), findsOneWidget);
      expect(find.text('Évaluez votre expérience'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'hides « Évaluer » once the order is rated or not completed yet',
        (tester) async {
      _seed([_order(rating: 4.0, reviewComment: 'Déjà évalué')]);
      await pumpDetail(tester, _orderId);
      expect(find.widgetWithText(ElevatedButton, 'Évaluer'), findsNothing);

      // Same route, a service that is not fully completed → no review action.
      _seed([_order(status: RequestStatus.inProgress)]);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Évaluer'), findsNothing);
      expect(find.byType(RatingScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
