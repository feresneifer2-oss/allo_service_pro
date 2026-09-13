import 'package:flutter/material.dart';

import 'package:allo_service_pro/shared/app_locale.dart';

/// The ONLY 4 official badges across Client, Pro and Admin screens.
/// Legacy badge strings are purged — always use these constants.
class ProBadges {
  ProBadges._();

  static const String cin = 'cin';
  static const String recommended = 'recommended';
  static const String topPro = 'top_pro';
  static const String certified = 'certified';

  static const List<String> all = [cin, recommended, topPro, certified];

  static bool isValid(String badge) => all.contains(badge);

  /// Bilingual label for UI rendering.
  static String label(BuildContext context, String badge) => switch (badge) {
        cin => tr(context, fr: 'CIN Vérifié', ar: 'هوية مفعلة'),
        recommended => tr(context, fr: 'Recommandé', ar: 'موصى به'),
        topPro => tr(context, fr: 'Top Pro', ar: 'الأفضل'),
        certified => tr(context, fr: 'Pro Certifié', ar: 'حرفي موثوق'),
        _ => badge,
      };
}