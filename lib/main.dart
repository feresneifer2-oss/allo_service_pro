import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/error/app_error_handler.dart';
import 'core/location/location_service.dart';
import 'core/network/connectivity_store.dart';
import 'core/queue/offline_queue_bindings.dart';
import 'core/services/onesignal_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/application/admin_store.dart';
import 'features/anti_abuse/application/anti_abuse_bindings.dart';
import 'features/anti_abuse/application/anti_abuse_store.dart';
import 'features/auth/application/supabase_auth_bindings.dart';
import 'features/auth/application/user_store.dart';
import 'features/pro_dashboard/application/pro_profile_store.dart';
import 'features/pro_dashboard/application/subscription_store.dart';
import 'features/requests/application/request_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'shared/app_locale.dart';
import 'shared/widgets/anti_abuse_gate.dart';
import 'shared/widgets/offline_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ENVIRONMENT BOOT GUARD (CodeRabbit): a missing/corrupt `.env` used to
  // crash the app OUTRIGHT (dotenv.load threw, and the `!` null-assertions on
  // the credentials followed it). The app is local-first by design, so a
  // missing config must degrade to LOCAL-ONLY mode: log cleanly, skip
  // Supabase initialization (every Supabase call site guards on
  // `isConfigured`), and surface a visible warning banner in the shell.
  // ASSET-FREE ENV RESOLUTION (CodeRabbit): `.env` is gitignored, so it is
  // NOT declared as a Flutter asset anymore — a fresh clone / CI checkout
  // must not carry a bundling reference to an untracked file. Precedence:
  // 1) dotenv (local dev, file present), 2) `--dart-define=SUPABASE_URL=…`
  // / `SUPABASE_ANON_KEY=…` (release/CI builds), 3) LOCAL-ONLY degradation
  // via the guard below.
  var supaUrl = '';
  var supaKey = '';
  String? configWarning;
  try {
    await dotenv.load(fileName: ".env");
    supaUrl = (dotenv.env['SUPABASE_URL'] ?? '').trim();
    supaKey = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
  } catch (e) {
    debugPrint('main(): .env failed to load ($e) — falling back to '
        '--dart-define / LOCAL-ONLY mode.');
  }
  if (supaUrl.isEmpty || supaKey.isEmpty) {
    supaUrl = const String.fromEnvironment('SUPABASE_URL').trim();
    supaKey = const String.fromEnvironment('SUPABASE_ANON_KEY').trim();
  }
  if (supaUrl.isEmpty || supaKey.isEmpty) {
    configWarning = '.env introuvable — mode local uniquement / '
        'ملف البيئة مفقود — وضع محلي فقط';
    debugPrint('main(): $configWarning');
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Supabase using the credentials from .env (only when the
  // configuration is actually usable — see the guard above).
  if (configWarning == null) {
    // BOOT GUARD (CodeRabbit): `Supabase.initialize` itself can still fail —
    // a malformed URL, a unreachable/timeouted first round-trip, or a plugin
    // error on a broken device. The failure must degrade to the SAME
    // local-only boot as a missing .env (never crash the app at startup).
    try {
      await Supabase.initialize(
        url: supaUrl,
        publishableKey: supaKey,
      );
    } catch (e, st) {
      configWarning = 'تعذّر الاتصال بالخادم — وضع محلي فقط / '
          'Connexion au serveur impossible — mode local uniquement';
      debugPrint('main(): Supabase.initialize failed ($e) — starting in '
          'LOCAL-ONLY mode.');
      AppErrorHandler.report(e, st, context: 'main:Supabase.initialize');
    }
  }

  // Restore the persisted language choice before the first frame.
  await loadLocale();

  // Global error boundary + logger: must run before runApp so every
  // zone/async error is captured (never a red screen).
  AppErrorHandler.install();

  // Anti-abuse: bind the session terminator (logout on auto-ban).
  AntiAbuseBindings.register();

  // Restore locally persisted state BEFORE the first frame — everything is
  // awaited so the very first widgets render with truthful state:
  // admin registry + suspended/banned clients · registered clients ·
  // user session · tokens · subscription · anti-abuse counters.
  await AntiAbuseStore.loadFromPrefs();
  await AdminStore.loadFromPrefs();
  await UserStore.loadFromPrefs();
  await UserStore.loadRegisteredClients();
  await SubscriptionStore.loadFromPrefs();
  await ProProfileStore.loadFromPrefs();

  // Zero-desync: mirror the persisted admin registry (subscription ·
  // tokens · approval state) into the live session stores for any
  // auto-logged-in pro — so gates & paywall reflect the truth instantly.
  await AdminStore.syncSessionStoresForCurrentUser();

  // Supabase Auth ↔ UserStore bridge: binds the onAuthStateChange listener
  // so remote sign-in/out events map onto the local session dynamically
  // (logged-in user appears without a manual re-login, a remote sign-out
  // clears the session). No-op when Supabase was not initialized (tests /
  // offline demo builds) — the local auth flow remains fully functional.
  bindSupabaseAuthListener();

  // Global connectivity listener (Uber-style offline overlay).
  ConnectivityStore.init();

  // Offline action queue: register domain executors, restore pending work and
  // drain it. Deliberately the LAST hydration step: [OfflineQueue.init] may
  // replay a queued operation immediately, and that replay goes through
  // RequestStore / SubscriptionStore / ProProfileStore. Arming it before those
  // stores were hydrated (and before the session was mirrored) would replay
  // the professional's queued work against empty / default state.
  //
  // `armAutoFlush` is the connectivity-driven half of the wiring (CodeRabbit):
  // it binds the listener that pushes queued creations & transitions to
  // Supabase the moment the device is back online. It is awaited explicitly —
  // never a hidden side effect of `registerAll` — so the ordering above is
  // enforced and unit tests stay free to register executors without arming an
  // auto-flush.
  OfflineQueueBindings.registerAll();
  await OfflineQueueBindings.armAutoFlush();

  // LIVE BACKEND HYDRATION (Supabase `orders`): after the local stores and
  // the offline queue are restored, pull the RLS-scoped order history so the
  // very first screen reflects the live backend. Fire-and-forget and
  // failure-tolerant: a slow/unreachable backend must never delay boot —
  // the local state stays usable and the fetch lands when it lands. A
  // no-op when Supabase is not initialized (tests / offline demo builds).
  unawaited(RequestStore.hydrateFromSupabase());

  // Push notifications: safe no-op in tests and until ONESIGNAL_APP_ID is
  // provided via --dart-define. Awaited-after-binding but never fatal —
  // failures are logged, boot continues.
  await OneSignalService.initialize();

  // Background location: kicked off but deliberately NOT awaited — GPS
  // prompts, slow fixes or a disabled radio must never delay runApp()/
  // first frame. Detection completes asynchronously and, when ready, sets
  // resolvedAddress / governorate without blocking the boot flow.
  unawaited(LocationService.instance.init());

  // runApp wrapped in runZonedGuarded so even synchronous + async uncaught
  // errors outside the Flutter pipeline are routed through AppErrorHandler.
  runZonedGuarded(
    () {
      runApp(AlloServiceProApp(configWarning: configWarning));
    },
    (error, stackTrace) {
      AppErrorHandler.report(error, stackTrace, context: 'runZonedGuarded');
    },
  );
}

class AlloServiceProApp extends StatelessWidget {
  const AlloServiceProApp({super.key, this.configWarning});

  /// Non-null when the environment config is missing/incomplete: the app
  /// still boots in LOCAL-ONLY mode (every Supabase call site degrades
  /// gracefully) and this banner makes the degraded mode VISIBLE instead of
  /// failing silently. Null in normal (configured) and test boots.
  final String? configWarning;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Allo Service Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: locale,
          supportedLocales: const [
            Locale('fr'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Universal keyboard UX: tapping anywhere outside a field dismisses
          // the keyboard on every screen, without touching each screen's code.
          // Accessibility guard: clamp OS font scaling to 1.3× so very
          // large system fonts never produce flex-overflow stripes,
          // while still respecting users who need bigger text.
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
              ),
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: Column(
                  children: [
                    // FALLBACK CONFIG UI (CodeRabbit): a thin, non-blocking
                    // banner that tells the user the build is running without
                    // backend credentials (local-only mode) instead of the app
                    // silently losing sync. Null → zero layout impact.
                    if (configWarning != null)
                      Material(
                        color: AppColors.warning,
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              const Icon(Icons.cloud_off_rounded,
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    // LOCALIZED BANNER (CodeRabbit): the raw
                                    // `configWarning` string is dev-facing
                                    // (debugPrint only); the user sees a
                                    // localized message instead.
                                    trGlobal(
                                      fr: 'Configuration backend manquante — '
                                          'mode local uniquement.',
                                      ar: 'إعدادات الخادم غير مكتملة — '
                                          'الوضع المحلي فقط.',
                                    ),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: OfflineOverlay(
                        child: AntiAbuseGate(
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
