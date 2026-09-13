import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/constants/legal_texts.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// The three legal documents reachable from both client & pro profiles.
enum LegalDoc { about, terms, privacy }

/// À propos / من نحن.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _LegalDocView(doc: LegalDoc.about);
}

/// Conditions d'utilisation / شروط الاستخدام.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _LegalDocView(doc: LegalDoc.terms);
}

/// Politique de confidentialité / سياسة الخصوصية.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _LegalDocView(doc: LegalDoc.privacy);
}

Widget _screenFor(LegalDoc doc) => switch (doc) {
      LegalDoc.about => const AboutScreen(),
      LegalDoc.terms => const TermsScreen(),
      LegalDoc.privacy => const PrivacyPolicyScreen(),
    };

/// Reusable profile-menu block: the three legal entries with localized
/// labels, used by both the customer profile and the pro profile screens.
class LegalMenuTiles extends StatelessWidget {
  const LegalMenuTiles({super.key});

  void _open(BuildContext context, LegalDoc doc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _screenFor(doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline_rounded,
              color: AppColors.primary),
          title: Text(tr(context, fr: 'À propos', ar: 'من نحن')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(context, LegalDoc.about),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_rounded, color: AppColors.primary),
          title: Text(tr(context,
              fr: "Conditions d'utilisation", ar: 'شروط الاستخدام')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(context, LegalDoc.terms),
        ),
        ListTile(
          leading:
              const Icon(Icons.shield_outlined, color: AppColors.primary),
          title: Text(tr(context,
              fr: 'Politique de confidentialité', ar: 'سياسة الخصوصية')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(context, LegalDoc.privacy),
        ),
      ],
    );
  }
}

/// Shared document viewer: listens to [appLocale] so the content switches
/// live between Arabic and French without reopening the screen.
class _LegalDocView extends StatelessWidget {
  const _LegalDocView({required this.doc});

  final LegalDoc doc;

  String _title(BuildContext context) => switch (doc) {
        LegalDoc.about => tr(context, fr: 'À propos', ar: 'من نحن'),
        LegalDoc.terms =>
          tr(context, fr: "Conditions d'utilisation", ar: 'شروط الاستخدام'),
        LegalDoc.privacy =>
          tr(context, fr: 'Politique de confidentialité', ar: 'سياسة الخصوصية'),
      };

  String _body(Locale locale) {
    final isArabic = locale.languageCode == 'ar';
    return switch (doc) {
      LegalDoc.about => isArabic ? LegalTexts.aboutAr : LegalTexts.aboutFr,
      LegalDoc.terms => isArabic ? LegalTexts.termsAr : LegalTexts.termsFr,
      LegalDoc.privacy =>
        isArabic ? LegalTexts.privacyAr : LegalTexts.privacyFr,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_title(context))),
      body: ValueListenableBuilder<Locale>(
        valueListenable: appLocale,
        builder: (context, locale, _) {
          // "À propos" is one flowing paragraph; the terms & privacy docs
          // are numbered clauses rendered as individual cards.
          final isParagraph = doc == LegalDoc.about;
          final lines =
              isParagraph ? <String>[_body(locale)] : _body(locale).split('\n');

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final line = lines[index];
              return Container(
                width: double.infinity,
                padding: EdgeInsets.all(isParagraph ? 20 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: isParagraph ? 15.5 : 14.5,
                    height: 1.7,
                    color: AppColors.slate800,
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _LegalFooter(current: doc),
    );
  }
}

/// Cross-links so the user can hop between the three documents.
class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.current});

  final LegalDoc current;

  String _label(BuildContext context, LegalDoc doc) => switch (doc) {
        LegalDoc.about => tr(context, fr: 'À propos', ar: 'من نحن'),
        LegalDoc.terms => tr(context, fr: 'Conditions', ar: 'الشروط'),
        LegalDoc.privacy =>
          tr(context, fr: 'Confidentialité', ar: 'الخصوصية'),
      };

  @override
  Widget build(BuildContext context) {
    final others = LegalDoc.values.where((d) => d != current).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            Text(
              tr(context, fr: 'Voir aussi :', ar: 'شوف كذلك:'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            ...others.map(
              (doc) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _screenFor(doc)),
                ),
                child: Text(
                  _label(context, doc),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}