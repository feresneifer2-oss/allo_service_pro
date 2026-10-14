// ─────────────────────────────────────────────────────────────────────────────
// CRAFTSMAN ("SNEY3I") ONLINE / OFFLINE STATUS — REALTIME REACTIVITY SUITE
// ─────────────────────────────────────────────────────────────────────────────
//
// WHAT IS UNDER TEST
// ------------------
// The craftsman presence source of truth in this codebase is
// `ProProfileStore.isAvailable` (a `ValueNotifier<bool>`): the flag the pro
// toggles from their dashboard, the flag `ProfessionalProfileScreen` projects
// onto `ProfessionalModel.availableNow` for `pro_1`, and the flag every
// client-facing availability filter (`ProfessionalsListScreen._availableOnly`,
// `BookingScreen`) reads.
//
// THE LISTENER UNDER TEST
// -----------------------
// `ProDashboardScreen` binds that notifier through a `ValueListenableBuilder`
// and paints the online/offline INDICATOR: a 10×10 circular dot
// (green `AppColors.success` = online / red `AppColors.error` = offline) plus
// the localized "Disponible"/"Indisponible" badge and the presence `Switch`.
// Every presence frame that lands in the notifier MUST be on screen one frame
// later — no setState, no navigation, no pull-to-refresh, no remount.
//
// NOTE ON THE TRANSPORT
// ---------------------
// The REAL transport for this status is `realtime:public:pro_availability`
// (Postgres Changes → `ProAvailabilityStore.applyRemoteRow`, see
// `pro_availability_persistence_test.dart`). This suite deliberately isolates
// the CLIENT contract from it: a `StreamController` presence feed
// ([_MockPresenceChannel]) stands in for the backend push, and the assertions
// lock what any ingress must keep — one event ⇒ one notifier write ⇒ one
// repainted frame, with no event-loop slip and no dead listener left behind.
//
// HYGIENE
// -------
// The mocked channel is cancelled + closed in `tearDown`, the suite asserts a
// cancelled subscription receives nothing, and it asserts the widget releases
// its own listener on unmount (`hasListeners == false`). A leak of either the
// transport or the UI subscription fails the build.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_dashboard_screen.dart';
import 'package:allo_service_pro/features/search/presentation/search_screen.dart';

/// One realtime presence frame as pushed by the backend channel.
class _PresenceEvent {
  const _PresenceEvent(this.proId, this.online);

  final String proId;
  final bool online;
}

/// TEST DOUBLE for the realtime presence transport.
///
/// `SupabaseRealtimeService` pushes every change as an event on a broadcast
/// channel; the app ingress then writes the affected store. This double mirrors
/// that shape 1:1:
///
///  * `controller` — the mocked broadcast channel (`sync: true` so a test can
///    reason in single frames: `push()` completes the store write before the
///    next `tester.pump()`).
///  * `bind()` — the ingress subscription (what production binds to the real
///    channel).
///  * `push()` — one backend frame.
///  * `dispose()` — cancels the subscription and closes the channel; it is
///    idempotent so `tearDown` can always call it.
class _MockPresenceChannel {
  _MockPresenceChannel()
      : controller = StreamController<_PresenceEvent>.broadcast(sync: true);

  /// Identity of the pro logged in on THIS device. Frames for anyone else ride
  /// the same channel and must be ignored by this client.
  static const String authenticatedProId = 'pro_me';

  final StreamController<_PresenceEvent> controller;

  StreamSubscription<_PresenceEvent>? _subscription;

  /// Frames that actually reached the ingress (post-multiplexing).
  int delivered = 0;

  void bind() {
    _subscription ??= controller.stream.listen(_onFrame);
  }

  void _onFrame(_PresenceEvent frame) {
    if (frame.proId != authenticatedProId) return; // another pro's frame
    delivered++;
    ProProfileStore.isAvailable.value = frame.online;
  }

  /// Pushes one backend presence frame. Synchronous: after this call the store
  /// already holds the new truth.
  void push({required bool online, String proId = authenticatedProId}) {
    controller.add(_PresenceEvent(proId, online));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!controller.isClosed) await controller.close();
  }
}

/// The online/offline DOT of the dashboard.
///
/// Matched on its three identifying traits simultaneously — tight 10×10
/// constraints, circular shape and the exact fill — so no other circle on the
/// screen (avatars, badges, steppers) can satisfy the finder.
Finder _statusDot(Color fill) => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints ==
              const BoxConstraints.tightFor(width: 10, height: 10) &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (widget.decoration! as BoxDecoration).color == fill,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPresenceChannel presence;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    presence = _MockPresenceChannel()..bind();
    ProProfileStore.isAvailable.value = true; // factory-default presence
  });

  tearDown(() async {
    // Requirement #3 — the mocked transport is always torn down.
    await presence.dispose();
    ProProfileStore.isAvailable.value = true;
  });

  /// Pumps the pro dashboard (the screen that owns the status indicator) on a
  /// tall surface so the header — dot, badge and Switch — is on-screen and
  /// hittable.
  Future<void> pumpDashboard(WidgetTester tester, {Locale? locale}) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('fr'), Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ProDashboardScreen(),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 1 · The presence listener itself (mocked realtime stream → notifier)
  // ───────────────────────────────────────────────────────────────────────────

  group('presence listener · ProProfileStore.isAvailable', () {
    test('rebroadcasts every realtime frame — offline → online → offline', () {
      final seen = <bool>[];
      void probe() => seen.add(ProProfileStore.isAvailable.value);
      ProProfileStore.isAvailable.addListener(probe);
      addTearDown(() => ProProfileStore.isAvailable.removeListener(probe));

      presence.push(online: false);
      expect(ProProfileStore.isAvailable.value, isFalse);

      presence.push(online: true);
      expect(ProProfileStore.isAvailable.value, isTrue);

      presence.push(online: false);
      expect(ProProfileStore.isAvailable.value, isFalse);

      expect(seen, [false, true, false]);
      expect(presence.delivered, 3);
    });

    test('a frame identical to the current status notifies nobody', () {
      final seen = <bool>[];
      void probe() => seen.add(ProProfileStore.isAvailable.value);
      ProProfileStore.isAvailable.addListener(probe);
      addTearDown(() => ProProfileStore.isAvailable.removeListener(probe));

      // Two identical "offline" frames landed back-to-back.
      presence.push(online: false);
      presence.push(online: false);

      expect(presence.delivered, 2); // both frames arrived...
      expect(seen, [false]); // ...but only ONE wake-up was spent
      expect(ProProfileStore.isAvailable.value, isFalse);
    });

    test('frames belonging to ANOTHER craftsman never touch this client', () {
      final seen = <bool>[];
      void probe() => seen.add(ProProfileStore.isAvailable.value);
      ProProfileStore.isAvailable.addListener(probe);
      addTearDown(() => ProProfileStore.isAvailable.removeListener(probe));

      presence.push(online: false, proId: 'pro_someone_else');

      expect(presence.delivered, 0);
      expect(seen, isEmpty);
      expect(ProProfileStore.isAvailable.value, isTrue);
    });

    test('a detached probe stops firing and dispose() frees the channel',
        () async {
      final seen = <bool>[];
      void probe() => seen.add(ProProfileStore.isAvailable.value);

      ProProfileStore.isAvailable.addListener(probe);
      presence.push(online: false);
      expect(seen, [false]);

      // Unsubscribe — the classic leak: a dead listener still being woken.
      ProProfileStore.isAvailable.removeListener(probe);
      presence.push(online: true);
      presence.push(online: false);

      expect(seen, [false],
          reason: 'a detached listener must never fire again');
      expect(ProProfileStore.isAvailable.value, isFalse,
          reason: 'the store itself keeps following the live frames');

      // Tearing the mocked channel down cancels the ingress subscription and
      // closes the transport — nothing survives the teardown.
      await presence.dispose();
      expect(
        () => presence.controller.add(const _PresenceEvent('pro_me', true)),
        throwsStateError,
        reason: 'a disposed realtime channel must be closed',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 2 · The client-side indicator repaints in ONE frame
  // ───────────────────────────────────────────────────────────────────────────

  group('status indicator · ProDashboardScreen', () {
    testWidgets('flips offline → online → offline, one pump() per frame',
        (tester) async {
      await pumpDashboard(tester);

      // ── Initial state: online ──
      expect(_statusDot(AppColors.success), findsOneWidget);
      expect(_statusDot(AppColors.error), findsNothing);
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('Indisponible'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Identity of the host element: the SAME element must rebuild in place,
      // proving a live reaction instead of a remount / manual refresh.
      final screen = tester.element(find.byType(ProDashboardScreen));

      // ── Realtime frame: the craftsman goes OFFLINE ──
      presence.push(online: false);
      await tester.pump(); // ← exactly ONE frame

      expect(_statusDot(AppColors.error), findsOneWidget);
      expect(_statusDot(AppColors.success), findsNothing);
      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.text('Disponible'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.element(find.byType(ProDashboardScreen)), same(screen));

      // ── Realtime frame: back ONLINE ──
      presence.push(online: true);
      await tester.pump();

      expect(_statusDot(AppColors.success), findsOneWidget);
      expect(_statusDot(AppColors.error), findsNothing);
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('Indisponible'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.element(find.byType(ProDashboardScreen)), same(screen));
    });

    testWidgets('Arabic (RTL) badge follows the frame with the same dot',
        (tester) async {
      await pumpDashboard(tester, locale: const Locale('ar'));

      expect(_statusDot(AppColors.success), findsOneWidget);
      expect(find.text('متاح'), findsOneWidget);

      presence.push(online: false);
      await tester.pump();

      expect(_statusDot(AppColors.error), findsOneWidget);
      expect(find.text('غير متاح'), findsOneWidget);
      expect(find.text('متاح'), findsNothing);
    });

    testWidgets('the craftsman\'s own Switch drives the same indicator',
        (tester) async {
      await pumpDashboard(tester);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(ProProfileStore.isAvailable.value, isFalse);
      expect(_statusDot(AppColors.error), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(ProProfileStore.isAvailable.value, isTrue);
      expect(_statusDot(AppColors.success), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('unmounting the dashboard releases its subscription — no leak',
        (tester) async {
      // Baseline: this file has no listener attached yet.
      // ignore: invalid_use_of_protected_member
      expect(ProProfileStore.isAvailable.hasListeners, isFalse);

      await pumpDashboard(tester);
      // ignore: invalid_use_of_protected_member
      expect(ProProfileStore.isAvailable.hasListeners, isTrue);

      // Tear the screen down — what popping the route (or logout) does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // The ValueListenableBuilder unsubscribed on dispose...
      // ignore: invalid_use_of_protected_member
      expect(ProProfileStore.isAvailable.hasListeners, isFalse);

      // ...so frames landing after the screen is gone are harmless: no
      // "setState after dispose" crash, no resurrection of the widget.
      presence.push(online: false);
      presence.push(online: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Switch), findsNothing);
      expect(ProProfileStore.isAvailable.value, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 3 · What the CUSTOMER sees for that same status
  // ───────────────────────────────────────────────────────────────────────────
  //
  // `ProfessionalsRepository` derives the client feed from the same presence
  // truth (`ProfessionalModel.availableNow`), so the customer card must render
  // the two states distinctly: an offline craftsman carries the red
  // "Indisponible" badge and a DISABLED request CTA, an online one stays
  // requestable. The live ingress is `realtime:public:pro_availability`
  // (covered end-to-end in `pro_availability_persistence_test.dart`); this test
  // pins the RENDERING contract that ingress depends on — a stale flag can
  // never be shown as requestable, and the badge can never disagree with the
  // button.

  testWidgets('customer view · offline craftsman is badged, not requestable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: SearchScreen()),
    );

    // Governorate 'Tunis' hosts exactly four catalog craftsmen:
    //   pro_2 (Tunis Ville, OFFLINE) + pro_5 (Tunis Ville, online)
    //   + pro_3 / pro_7 (La Marsa, online).
    // Results only render once a governorate is picked.
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tunis').last);
    await tester.pumpAndSettle();

    // Exactly one of the four cards is flagged offline...
    expect(find.text('Indisponible'), findsOneWidget);

    // ...and only its request CTA is disabled — the status gate the customer
    // runs into.
    final ctas = tester
        .widgetList<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Demander'))
        .toList();
    expect(ctas, hasLength(4));
    expect(ctas.where((b) => b.onPressed == null), hasLength(1),
        reason: 'the offline craftsman must not be requestable');
    expect(ctas.where((b) => b.onPressed != null), hasLength(3),
        reason: 'every online craftsman stays requestable');
    expect(tester.takeException(), isNull);
  });
}
