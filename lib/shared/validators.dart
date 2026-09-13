import 'package:flutter/material.dart';

import 'package:allo_service_pro/shared/app_locale.dart';

/// Shared input sanitization & validation helpers (Tunisia-specific rules).
class AppValidators {
  AppValidators._();

  /// Sanitizes common Tunisian entry variants: "+216" / "216" prefix,
  /// spaces, dashes, dots, parentheses and a leading zero are stripped.
  static String normalizePhone(String raw) {
    var v = raw.trim().replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
    v = v.replaceFirst(RegExp(r'^(\+?216)'), '');
    if (v.startsWith('0')) v = v.substring(1);
    return v;
  }

  /// Strict Tunisian phone format: exactly 8 digits AND the first digit must
  /// be a real mobile/landline prefix. Numbers starting with 6 or 8 are
  /// REJECTED explicitly (no Tunisian service uses those prefixes — valid
  /// mobiles begin with 2/4/5/9, landlines with 3/7).
  static bool isValidTunisianPhone(String raw) =>
      RegExp(r'^[234579]\d{7}$').hasMatch(normalizePhone(raw));

  /// Form-field validator with a bilingual (FR/AR) error message.
  static String? tunisianPhone(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return tr(context,
          fr: 'Entrez votre numéro de téléphone', ar: 'أدخل رقم هاتفك');
    }
    if (!isValidTunisianPhone(value)) {
      return tr(context,
          fr: 'Numéro tunisien invalide (8 chiffres, ex : 22 123 456)',
          ar: 'رقم تونسي غير صالح (8 أرقام، مثال: 22 123 456)');
    }
    return null;
  }
}