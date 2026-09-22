import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Why the paywall is currently blocking the professional.
enum PaywallReason {
  /// Monthly subscription cycle elapsed → admin re-activation needed.
  subscriptionExpired,

  /// Trial mode with a zero token balance → no confirmations left.
  tokensExhausted,
}

/// Full-screen paywall blocking a craftsperson's dashboard until the
/// 15 TND / 1-month unlimited plan is (re-)activated by the admin.
///
/// Two entry points drive it (see [PaywallReason]):
/// - expired subscription → "Abonnement expiré" copy;
/// - token exhaustion (trial at 0) → "Solde de tokens épuisé" copy.
/// Both funnel into the same D17-via-WhatsApp re-activation flow.
class SubscriptionPaywallScreen extends StatelessWidget {
  const SubscriptionPaywallScreen({
    super.key,
    this.reason = PaywallReason.subscriptionExpired,
  });

  final PaywallReason reason;

  String _title(PaywallReason reason, bool isArabic) {
    if (reason == PaywallReason.tokensExhausted) {
      return isArabic
          ? 'تم إيقاف حسابك مؤقتاً لنفاد الرصيد'
          : 'Compte suspendu : Solde de tokens épuisé';
    }
    return isArabic ? 'انتهاء الاشتراك' : 'Abonnement expiré';
  }

  String _description(PaywallReason reason, bool isArabic) {
    if (reason == PaywallReason.tokensExhausted) {
      return isArabic
          ? 'لقد استهلكت جميع التوكنز المتاحة لك. للحصول على طلبات غير محدودة لمدة شهر كامل، يرجى التفعيل بـ 15 ديناراً تونسياً.'
          : 'Vous avez consommé tous vos tokens. Pour obtenir des demandes illimitées pendant un mois complet, veuillez activer l\'abonnement à 15 DT.';
    }
    return isArabic
        ? 'انتهت فترة اشتراكك الشهري. تواصل معنا عبر الواتساب لمعرفة رقم الدفع D17 والحصول على حساب غير محدود لمدة شهر كامل مقابل 15 دينار.'
        : "Votre abonnement mensuel a expiré. Contactez-nous sur WhatsApp pour obtenir le numéro D17 et bénéficier d'un accès illimité pendant un mois pour 15 TND.";
  }

  String _ctaLabel(PaywallReason reason, bool isArabic) {
    if (reason == PaywallReason.tokensExhausted) {
      return isArabic
          ? 'تفعيل الاشتراك اللامحدود (15 د.ت / شهر)'
          : "Activer l'abonnement illimité (15 DT / mois)";
    }
    return isArabic ? 'التواصل عبر الواتساب' : 'Contacter sur WhatsApp';
  }

  Future<void> _openWhatsApp(
    BuildContext context, {
    required PaywallReason reason,
    required bool isArabic,
    required bool askingForReceipt,
  }) async {
    final user = UserStore.user.value;
    final name = user?.name ?? UserStore.displayName;
    final proCode = user?.proCode;
    final codeLine = (proCode == null || proCode.isEmpty)
        ? ''
        : '\n${isArabic ? 'المعرّف المهني' : 'ID Pro'} : $proCode';

    final String base;
    if (reason == PaywallReason.tokensExhausted) {
      // Token-exhaustion templates (spec wording, pro name injected
      // dynamically from UserStore).
      base = isArabic
          ? 'مرحباً، أنا $name، تم إغلاق حسابي بسبب نفاد الرصيد. أرغب في دفع 15 ديناراً لتفعيل الحساب اللامحدود لمدة شهر. الرجاء مدي برقم D17 لإرسال المبلغ.'
          : "Bonjour, je suis $name, mon compte est suspendu pour solde épuisé. Je souhaite payer 15 DT pour activer le compte illimité pendant un mois. Veuillez me fournir le numéro D17 pour effectuer le virement.";
    } else {
      // Subscription-expiry templates (existing approved flow).
      final accountId =
          (user?.id.isNotEmpty ?? false) ? user!.id : (user?.phone ?? '-');
      if (isArabic) {
        base = askingForReceipt
            ? 'مرحبا، أنا $name (معرّف الحساب: $accountId).\nهذا وصل دفع D17 الخاص بتجديد اشتراكي الشهري (15 دينار) — أرجو تفعيل الحساب غير المحدود. 🙏'
            : 'مرحبا، أنا $name، معرّف حسابي: $accountId.\nانتهى اشتراكي الشهري وأرجو تزويدي بمعلومات الدفع عبر D17 لتفعيل الحساب غير المحدود لمدة شهر كامل مقابل 15 دينار.\nسأرفق صورة وصل الدفع هنا بعد التحويل 🙏';
      } else {
        base = askingForReceipt
            ? 'Bonjour, je suis $name (ID : $accountId).\nVoici mon reçu de paiement D17 pour le renouvellement mensuel (15 TND) — merci d\'activer mon accès illimité. 🙏'
            : "Bonjour, je suis $name (ID : $accountId).\nMon abonnement mensuel a expiré ; merci de m'envoyer les informations de paiement D17 pour activer l'accès illimité d'un mois complet pour 15 TND.\nJe joindrai le reçu de paiement ici après le transfert 🙏";
      }
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
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        // Dynamic locale: the AR/FR copy re-renders the instant appLocale
        // flips — no need to reopen the screen.
        child: ValueListenableBuilder<Locale>(
          valueListenable: appLocale,
          builder: (context, locale, _) {
            final isArabic = locale.languageCode == 'ar';
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    _title(reason, isArabic),
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
                      _description(reason, isArabic),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
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
                      onPressed: () => _openWhatsApp(
                        context,
                        reason: reason,
                        isArabic: isArabic,
                        askingForReceipt: false,
                      ),
                      icon: const Icon(Icons.chat_rounded, size: 24),
                      label: Text(
                        _ctaLabel(reason, isArabic),
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.bold),
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
                              color: AppColors.slate400,
                              fontSize: 13,
                              height: 1.6),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openWhatsApp(
                              context,
                              reason: reason,
                              isArabic: isArabic,
                              askingForReceipt: true,
                            ),
                            icon:
                                const Icon(Icons.attach_file_rounded, size: 18),
                            label: Text(
                              tr(context,
                                  fr: 'Envoyer le reçu sur WhatsApp',
                                  ar: 'إرسال الوصل عبر الواتساب'),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondaryLight,
                              side: BorderSide(
                                  color: AppColors.secondary
                                      .withValues(alpha: .6)),
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
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ), // Column
            ); // SingleChildScrollView
          }, // appLocale builder
        ), // ValueListenableBuilder
      ), // SafeArea
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
