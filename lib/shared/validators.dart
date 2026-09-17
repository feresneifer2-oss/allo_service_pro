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

  // ─── Email (auth identity & Email-OTP channel) ────────────────────────

  /// Maximum total length of an e-mail address (RFC 5321 forward-path).
  static const int maxEmailLength = 254;

  /// Maximum length of the local part (before the `@`).
  static const int maxEmailLocalLength = 64;

  /// Maximum length of the domain part (after the `@`) — RFC 1035.
  static const int maxEmailDomainLength = 253;

  /// Maximum length of a single domain label — RFC 1035.
  static const int maxEmailLabelLength = 63;

  /// Domain label: starts and ends with an alphanumeric character, internal
  /// hyphens allowed, 1–63 characters (no leading/trailing `-`).
  static const String _label = r'[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?';

  /// Local part: alphanumerics and `_ % + -`, with SINGLE dots used as
  /// separators — so a leading dot, a trailing dot and consecutive dots are
  /// all rejected (`[A-Za-z0-9_%+\-]+(?:\.[A-Za-z0-9_%+\-]+)*`).
  static const String _local = r'[A-Za-z0-9_%+\-]+(?:\.[A-Za-z0-9_%+\-]+)*';

  /// Top-level domain: alphabetic only, 2–63 characters — no numeric TLD, no
  /// single-letter TLD and no over-long TLD.
  static const String _tld = r'[A-Za-z]{2,63}';

  /// Any whitespace or C0/C1 control character — never legal inside an
  /// address, and a classic injection-smuggling vector.
  static final RegExp _whitespaceOrControl =
      RegExp(r'[\s\u0000-\u001F\u007F]');

  /// Full address: local part `@` one or more domain labels `@` an alphabetic
  /// TLD. Malformed local parts (`.a@`, `a.@`,
  /// `a..b@`) and invalid domain labels (`@-x.com`, `@x-.com`, `@x..com`,
  /// numeric/1-char TLDs, trailing dots) never match.
  static final RegExp _emailRegExp = RegExp(
    '^$_local@(?:$_label\\.)+$_tld\$',
  );

  /// Strict email format check used as the auth identity.
  ///
  /// Applies the production rules of RFC 5321 (total ≤ 254, local part ≤ 64)
  /// and RFC 1035 (domain ≤ 253, every label 1–63 with alphanumeric edges —
  /// no leading/trailing hyphen) on top of the structural pattern, and rejects
  /// any whitespace or control character. Surrounding whitespace is trimmed;
  /// INTERNAL anomalies (double dots, stray spaces, illegal symbols) are
  /// rejected outright, as a real mail agent would.
  static bool isValidEmail(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length > maxEmailLength) return false;
    // Exactly one `@`, splitting a non-empty local part and a non-empty domain.
    final at = value.indexOf('@');
    if (at <= 0 || at != value.lastIndexOf('@')) return false;
    if (at > maxEmailLocalLength) return false;
    final domain = value.substring(at + 1);
    if (domain.isEmpty || domain.length > maxEmailDomainLength) return false;
    if (_whitespaceOrControl.hasMatch(value)) return false;
    if (!_emailRegExp.hasMatch(value)) return false;
    // Per-label bounds are asserted explicitly: the pattern only caps the
    // INTERNAL characters of a label, so an over-long one is caught here.
    for (final label in domain.split('.')) {
      if (label.isEmpty || label.length > maxEmailLabelLength) return false;
    }
    return true;
  }

  /// Form-field validator for the authentication email with bilingual
  /// (FR/AR) error messages.
  static String? email(String? value, BuildContext context) {
    if (value == null || value.trim().isEmpty) {
      return tr(context,
          fr: 'Entrez votre adresse e-mail', ar: 'أدخل بريدك الإلكتروني');
    }
    if (!isValidEmail(value)) {
      return tr(context,
          fr: 'Adresse e-mail invalide (ex : nom@exemple.com)',
          ar: 'بريد إلكتروني غير صالح (مثال: name@example.com)');
    }
    return null;
  }
}