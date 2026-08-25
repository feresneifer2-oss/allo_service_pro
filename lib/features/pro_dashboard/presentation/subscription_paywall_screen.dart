import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Full-screen paywall shown to craftspersons whose monthly subscription
/// has expired. Blocks every dashboard feature until the 15 TND / 1-month
/// unlimited plan is re-activated by the admin.
class SubscriptionPaywallScreen extends StatelessWidget {
  const SubscriptionPaywallScreen({super.key});

  Future<void> _openWhatsApp(
    BuildContext context, {
    required bool askingForReceipt,
  }) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final user = UserStore.user.value;
    final name = user?.name ?? UserStore.displayName;
    final accountId =
        (user?.id.isNotEmpty ?? false) ? user!.id : (user?.phone ?? '-');

    final proCode = user?.proCode;
    final codeLine = (proCode == null || proCode.isEmpty)
        ? ''
        : '\n${isArabic ? 'المعرّف المهني' : 'ID Pro'} : $proCode';

    final String base;
    if (isArabic) {
      base = askingForReceipt
          ? 'مرحبا، أنا $name (معرّف الحساب: $accountId).\nهذا وصل دفع D17 الخاص بتجديد اشتراكي الشهري (15 دينار) — أرجو تفعيل الحساب غير المحدود. 🙏'
          : 'مرحبا، أنا $name، معرّف حسابي: $accountId.\nانتهى اشتراكي الشهري وأرجو تزويدي بمعلومات الدفع عبر D17 لتفعيل الحساب غير المحدود لمدة شهر كامل مقابل 15 دينار.\nسأرفق صورة وصل الدفع هنا بعد التحويل 🙏';
    } else {
      base = askingForReceipt
          ? 'Bonjour, je suis $name (ID : $accountId).\nVoici mon reçu de paiement D17 pour le renouvellement mensuel (15 TND) — merci d\'activer mon accès illimité. 🙏'
          : "Bonjour, je suis $name (ID : $accountId).\nMon abonnement mensuel a expiré ; merci de m'envoyer les informations de paiement D17 pour activer l'accès illimité d'un mois complet pour 15 TND.\nJe joindrai le reçu de paiement ici après le transfert 🙏";
    }

    final String message = '$base$codeLine';

    final uri = Uri.parse(
      'https://wa.me/${SubscriptionStore.whatsappNumber}'
      '?text=${Uri.encodeComponent(message)}',
    );

    try {
      // externalApplication avoids in-app webviews that break wa.me redirects
      // on some Android devices.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            context,
            fr: 'Impossible d\'ouvrir WhatsApp. Installez l\'application.',
            ar: 'تعذّر فتح واتساب — تأكد من تثبيت التطبيق.',
          )),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final explanation = tr(
      context,
      fr: "Votre abonnement mensuel a expiré. Contactez-nous sur WhatsApp pour obtenir le numéro D17 et bénéficier d'un accès illimité pendant un mois pour 15 TND.",
      ar: 'انتهت فترة اشتراكك الشهري. تواصل معنا عبر الواتساب لمعرفة رقم الدفع D17 والحصول على حساب غير محدود لمدة شهر كامل مقابل 15 دينار.',
    );

    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 44),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr(context, fr: 'Abonnement expiré', ar: 'انتهاء الاشتراك'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.35)),
                ),
                child: Text(
                  explanation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 15,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Price badge ──
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.secondary),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium_rounded,
                          color: AppColors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? '${SubscriptionStore.priceTnd} دينار / شهر'
                            : '${SubscriptionStore.priceTnd} TND / mois',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Benefits ──
              _Benefit(
                  icon: Icons.all_inclusive_rounded,
                  text: tr(context,
                      fr: 'Demandes et chats illimités pendant 1 mois',
                      ar: 'طلبات ومحادثات غير محدودة لمدة شهر')),
              _Benefit(
                  icon: Icons.verified_rounded,
                  text: tr(context,
                      fr: 'Profil mis en avant auprès des clients',
                      ar: 'بروفايل مميّز أمام العملاء')),
              _Benefit(
                  icon: Icons.support_agent_rounded,
                  text: tr(context,
                      fr: 'Support prioritaire sur WhatsApp',
                      ar: 'دعم ذو أولوية عبر الواتساب')),
              const SizedBox(height: 28),

              // ── Primary CTA : WhatsApp ──
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _openWhatsApp(context, askingForReceipt: false),
                  icon: const Icon(Icons.chat_rounded, size: 24),
                  label: Text(
                    tr(context,
                        fr: 'Contacter sur WhatsApp',
                        ar: 'التواصل عبر الواتساب'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Receipt attachment flow ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: AppColors.secondaryLight, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr(context,
                                fr: 'Après le transfert D17 :',
                                ar: 'بعد تحويل D17:'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        fr: "Prenez une capture du reçu puis joignez-la dans la conversation WhatsApp — l'admin validera votre abonnement depuis le panneau d'administration.",
                        ar: 'صوّر وصل الدفع ثم أرفقه في نفس محادثة الواتساب — سيقوم المشرف بتفعيل اشتراكك من لوحة الإدارة.',
                      ),
                      style: const TextStyle(
                          color: AppColors.slate400, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openWhatsApp(context, askingForReceipt: true),
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(
                          tr(context,
                              fr: 'Envoyer le reçu sur WhatsApp',
                              ar: 'إرسال الوصل عبر الواتساب'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondaryLight,
                          side: BorderSide(
                              color: AppColors.secondary.withValues(alpha: .6)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Footer note ──
              Center(
                child: Text(
                  tr(context,
                      fr: "Votre compte se réactive automatiquement dès validation par l'admin.",
                      ar: 'يتفاعل حسابك تلقائيًا بمجرد موافقة المشرف.'),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
