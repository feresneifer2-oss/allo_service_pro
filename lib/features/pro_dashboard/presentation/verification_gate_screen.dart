import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Full-screen gate blocking unverified professionals.
///
/// - pending : review in progress + WhatsApp inquiry pre-filled with
///             Name · Profession · PRO-XXXXX.
/// - rejected: shows the admin reason with a "Re-upload proof" action that
///             sends the account back to review without re-registering.
class VerificationGateScreen extends StatefulWidget {
  const VerificationGateScreen({super.key});

  @override
  State<VerificationGateScreen> createState() =>
      _VerificationGateScreenState();
}

class _VerificationGateScreenState extends State<VerificationGateScreen> {
  Future<void> _openWhatsApp(UserModel user) async {
    final msg = AdminStore.whatsappMessage(
      name: user.name,
      profession: ProProfileStore.professionFr ?? '-',
      proCode: user.proCode ?? '-',
    );
    final uri = Uri.parse(
        'https://wa.me/21624449959?text=${Uri.encodeComponent(msg)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context,
              fr: "Impossible d'ouvrir WhatsApp.",
              ar: 'تعذّر فتح واتساب.')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: UserStore.user,
      builder: (context, user, _) {
        final u = user;
        if (u == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final rejected = u.verificationStatus.isRejected;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(tr(context,
                fr: 'Vérification du compte', ar: 'التحقق من الحساب')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Icon(
                    rejected
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                    size: 72,
                    color: rejected ? AppColors.error : AppColors.warning,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    rejected
                        ? tr(context, fr: 'Compte refusé', ar: 'تم رفض الحساب')
                        : tr(context,
                            fr: 'En attente de vérification',
                            ar: 'في انتظار التحقق'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if ((u.proCode ?? '').isNotEmpty)
                    Center(
                      child: Chip(
                        label: Text(u.proCode!),
                        backgroundColor: AppColors.primarySurface,
                        labelStyle: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (rejected && (u.rejectionReason ?? '').isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: .35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(context,
                              fr: 'Motif du refus :', ar: 'سبب الرفض:'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(u.rejectionReason!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    rejected
                        ? tr(context,
                            fr:
                                'Corrigez le problème puis renvoyez votre preuve.',
                            ar: 'صحّح المشكلة ثم أعد رفع الإثبات.')
                        : tr(context,
                            fr:
                                'Votre compte est en cours de vérification par l\'administration.',
                            ar: 'حسابك قيد المراجعة من قبل الإدارة.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // ── Re-upload proof (rejected flow) ──
                  if (rejected)
                    ElevatedButton.icon(
                      onPressed: () {
                        const proofPath =
                            'assets/images/doc_placeholder.png';
                        // Re-queue WITHOUT full re-registration.
                        final entry = AdminStore.pendingPros.value
                            .where((p) => p.proCode == u.proCode)
                            .toList();
                        if (entry.isNotEmpty) {
                          AdminStore.resubmitProof(entry.first.id,
                              proofPath: proofPath);
                        }
                        UserStore.updateProVerification(
                          status: ProVerification.pending,
                          reason: '',
                          proofPath: proofPath,
                        );
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(tr(context,
                          fr: 'Re-téléverser la preuve',
                          ar: 'إعادة رفع الإثبات')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── WhatsApp inquiry (pre-filled) ──
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(u),
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(tr(context,
                        fr: 'Contacter via WhatsApp',
                        ar: 'التواصل عبر واتساب')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(
                          color:
                              AppColors.success.withValues(alpha: .4)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () =>
                        Navigator.popUntil(context, (r) => r.isFirst),
                    child: Text(tr(context,
                        fr: "Retour à l'accueil", ar: 'العودة للرئيسية')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}