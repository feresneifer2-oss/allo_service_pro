import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/network/connectivity_store.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/application/admin_store.dart';
import 'features/auth/application/user_store.dart';
import 'features/pro_dashboard/application/pro_profile_store.dart';
import 'features/pro_dashboard/application/subscription_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'package:allo_service_pro/shared/widgets/offline_overlay.dart';
import 'shared/app_locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Restore locally persisted state BEFORE the first frame:
  // admin registry · user session · tokens · subscription.
  await AdminStore.loadFromPrefs();
  await UserStore.loadFromPrefs();
  await SubscriptionStore.loadFromPrefs();
  await ProProfileStore.loadFromPrefs();

  // Global connectivity listener (Uber-style offline overlay).
  ConnectivityStore.init();

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
          builder: (context, child) => GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: OfflineOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
