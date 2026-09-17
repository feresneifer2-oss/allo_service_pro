import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appLocale = ValueNotifier<Locale>(const Locale('fr'));

const String _kLocale = 'app_locale';

/// Changes the app language and persists it so the choice survives
/// app restarts (loaded in `main.dart` before the first frame).
Future<void> setLocale(Locale locale) async {
  appLocale.value = locale;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, locale.languageCode);
  } catch (_) {
    // Best-effort persistence.
  }
}

/// Restores the persisted language at startup (defaults to French).
Future<void> loadLocale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocale);
    if (code == 'ar' || code == 'fr') {
      appLocale.value = code == 'ar' ? const Locale('ar') : const Locale('fr');
    }
  } catch (_) {
    // Fresh install or storage unavailable → keep default.
  }
}

String tr(BuildContext context, {required String fr, required String ar}) {
  final code = Localizations.localeOf(context).languageCode;

  if (code == 'ar') {
    final v = ar.trim();
    if (v.isNotEmpty) return v; // Arabic موجود
    return fr; // fallback باش ما يطلعش فارغ
  }

  return fr;
}

/// Context-FREE localization lookup.
///
/// Needed by widgets that must render OUTSIDE any `Localizations` ancestor —
/// the global error fallback (`ErrorWidget.builder`) and any pre-`MaterialApp`
/// surface. It reads the live [appLocale] notifier directly, so it stays correct
/// after a language switch without a rebuild from above.
String trGlobal({required String fr, required String ar}) {
  if (appLocale.value.languageCode != 'ar') return fr;
  final v = ar.trim();
  return v.isEmpty ? fr : v;
}
