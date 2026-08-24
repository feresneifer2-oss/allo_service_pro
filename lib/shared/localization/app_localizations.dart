import 'package:flutter/material.dart';
import '../app_locale.dart';

/// Helper class for app localization
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return AppLocalizations(appLocale.value);
  }

  // Theme helper methods
  static bool isArabic(BuildContext context) {
    return appLocale.value.languageCode == 'ar';
  }

  static bool isFrench(BuildContext context) {
    return appLocale.value.languageCode == 'fr';
  }

  // Translation helper with default values
  static String translate(
    BuildContext context, {
    required String fr,
    required String ar,
  }) {
    return tr(context, fr: fr, ar: ar);
  }

  // Direction helper
  static TextDirection getDirection(BuildContext context) {
    return isArabic(context) ? TextDirection.rtl : TextDirection.ltr;
  }

  // Number formatting
  static String formatNumber(BuildContext context, num value) {
    return value.toString();
  }

  // Date formatting
  static String formatDate(BuildContext context, DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Time formatting
  static String formatTime(BuildContext context, DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
