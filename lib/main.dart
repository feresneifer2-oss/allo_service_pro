import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/location/location_service.dart';
import 'core/network/connectivity_store.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/application/admin_store.dart';
import 'features/auth/application/user_store.dart';
import 'features/pro_dashboard/application/pro_profile_store.dart';
import 'features/pro_dashboard/application/subscription_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'shared/app_locale.dart';
import 'shared/widgets/offline_overlay.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Restore the persisted language choice before the first frame.
  await loadLocale();

  // Restore locally persisted state BEFORE the first frame — everything is
  // awaited so the very first widgets render with truthful state:
  // admin registry + suspended/banned clients · registered clients ·
  // user session · tokens · subscription.
  await AdminStore.loadFromPrefs();
  await UserStore.loadFromPrefs();
  await UserStore.loadRegisteredClients();
  await SubscriptionStore.loadFromPrefs();
  await ProProfileStore.loadFromPrefs();
  // Zero-desync: mirror the persisted admin registry (subscription ·
  // tokens · approval state) into the live session stores for any
  // auto-logged-in pro — so gates & paywall reflect the truth instantly.
  AdminStore.syncSessionStoresForCurrentUser();

  // Global connectivity listener (Uber-style offline overlay).
  ConnectivityStore.init();

  // Background location: kicked off but deliberately NOT awaited — GPS
  // prompts, slow fixes or a disabled radio must never delay runApp()/
  // first frame. Detection completes asynchronously and, when ready, sets
  // resolvedAddress / governorate without blocking the boot flow.
  unawaited(LocationService.instance.init());

  runApp(const AlloServiceProApp());
}

class AlloServiceProApp extends StatelessWidget {
  const AlloServiceProApp({super.key});

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
                child: OfflineOverlay(
                  child: child ?? const SizedBox.shrink(),
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
