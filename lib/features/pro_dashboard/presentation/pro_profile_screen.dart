import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_registration/presentation/pro_registration_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProProfileScreen extends StatelessWidget {
  const ProProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Mon profil pro', ar: 'ملفي المهني')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.secondarySurface,
                child: const Icon(Icons.engineering_rounded,
                    size: 48, color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ValueListenableBuilder<UserModel?>(
                valueListenable: UserStore.user,
                builder: (_, user, __) {
                  final name = (user != null && user.name.trim().isNotEmpty)
                      ? user.name.trim()
                      : UserStore.displayName;
                  return Text(
                    name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: ValueListenableBuilder(
                valueListenable: ProProfileStore.rating,
                builder: (_, rating, __) => Text(
                  '⭐ ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
              title: Text(
                  tr(context, fr: 'Modifier mon profil', ar: 'تعديل ملفي')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProRegistrationScreen()),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.verified_rounded, color: AppColors.primary),
              title: Text(
                  tr(context, fr: 'Statut vérification', ar: 'حالة التحقق')),
              subtitle: ValueListenableBuilder(
                valueListenable: ProProfileStore.verificationStatus,
                builder: (_, status, __) {
                  final label = switch (status) {
                    ProVerificationStatus.approved =>
                      tr(context, fr: 'Vérifié', ar: 'موثّق'),
                    ProVerificationStatus.pending =>
                      tr(context, fr: 'En cours', ar: 'قيد المراجعة'),
                    ProVerificationStatus.rejected =>
                      tr(context, fr: 'Refusé', ar: 'مرفوض'),
                    ProVerificationStatus.none =>
                      tr(context, fr: 'Non soumis', ar: 'غير مقدّم'),
                  };
                  return Text(label);
                },
              ),
            ),
            const SizedBox(height: 8),
            // Compte : identifiant et téléphone (dynamiques, repli sûr)
            ValueListenableBuilder<UserModel?>(
              valueListenable: UserStore.user,
              builder: (_, user, __) {
                final accountId = (user?.id.trim().isNotEmpty ?? false)
                    ? user!.id.trim()
                    : '—';
                final phone = (user?.phone.trim().isNotEmpty ?? false)
                    ? user!.phone.trim()
                    : tr(context, fr: 'Non renseigné', ar: 'غير محدد');
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_rounded,
                          color: AppColors.primary),
                      title: Text(tr(context,
                          fr: 'Identifiant de compte', ar: 'معرّف الحساب')),
                      subtitle: Text(accountId),
                    ),
                    ListTile(
                      leading: const Icon(Icons.phone_rounded,
                          color: AppColors.primary),
                      title:
                          Text(tr(context, fr: 'Téléphone', ar: 'رقم الهاتف')),
                      subtitle: Text(phone),
                    ),
                  ],
                );
              },
            ),
            // Abonnement : badge dynamique (Actif / Expiré)
            ValueListenableBuilder<SubscriptionStatus>(
              valueListenable: SubscriptionStore.status,
              builder: (_, status, __) {
                final isActive = status == SubscriptionStatus.active;
                return ListTile(
                  leading: Icon(Icons.workspace_premium_rounded,
                      color: isActive ? AppColors.success : AppColors.error),
                  title: Text(tr(context, fr: 'Abonnement', ar: 'الاشتراك')),
                  trailing: _SubscriptionBadge(isActive: isActive),
                );
              },
            ),
            // Solde de tokens (même source que le dashboard)
            ValueListenableBuilder<int>(
              valueListenable: ProProfileStore.tokens,
              builder: (_, tokenCount, __) => ListTile(
                leading: const Icon(Icons.diamond_rounded,
                    color: AppColors.success),
                title: Text(
                    tr(context, fr: 'Solde de tokens', ar: 'رصيد التوكنات')),
                trailing: Text(
                  '$tokenCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.success,
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

class _SubscriptionBadge extends StatelessWidget {
  const _SubscriptionBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        tr(context,
            fr: isActive ? 'Actif' : 'Expiré',
            ar: isActive ? 'نشط' : 'منتهي'),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
