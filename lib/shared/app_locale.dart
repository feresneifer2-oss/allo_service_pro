import 'package:flutter/material.dart';

final appLocale = ValueNotifier<Locale>(const Locale('fr'));

String tr(BuildContext context, {required String fr, required String ar}) {
  final code = Localizations.localeOf(context).languageCode;

  if (code == 'ar') {
    final v = ar.trim();
    if (v.isNotEmpty) return v; // Arabic موجود
    return fr; // fallback باش ما يطلعش فارغ
  }

  return fr;
}