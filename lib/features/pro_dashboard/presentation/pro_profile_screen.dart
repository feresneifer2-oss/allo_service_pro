import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/legal/presentation/legal_screens.dart';
import 'package:allo_service_pro/shared/widgets/logout_tile.dart';
import 'package:allo_service_pro/shared/widgets/support_info.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/admin/domain/pro_badges.dart';
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
            const SizedBox(height: 10),
            // Trust badge: identity card verified by the admin
            // (بطاقة هويّة مفعلة / CIN Vérifié).
            ValueListenableBuilder<UserModel?>(
              valueListenable: UserStore.user,
              builder: (_, user, __) =>
                  user?.verificationStatus == ProVerification.approved
                      ? const _PillBadge(
                          label: 'بطاقة هويّة مفعلة / CIN Vérifié',
                          color: Color(0xFF057A55),
                          icon: Icons.verified_user_rounded,
                        )
                      : const SizedBox.shrink(),
            ),
            // Admin-assigned badges — global real-time sync: adding or
            // removing a badge in the admin panel updates this list
            // instantly via [AdminStore.pendingPros].
            ValueListenableBuilder<List<PendingProModel>>(
              valueListenable: AdminStore.pendingPros,
              builder: (_, list, __) {
                // DOSSIER MATCH GUARD (CodeRabbit): the badge lookup goes
                // through the SAME guarded matcher the admin panel uses
                // ([AdminStore.entryForUser]) instead of a hand-rolled
                // comparison — the old inline loop happily matched on a
                // `null == null` PRO code or a blank session id, binding an
                // identifier-less session to an admin-seeded entry it does
                // not own (and leaking that entry's badges into its UI).
                final entry = AdminStore.entryForUser(UserStore.user.value);
                final badges = entry?.badges ?? const <String>[];
                if (badges.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final b in badges)
                        _PillBadge(
                          label: ProBadges.label(context, b),
                          color: AppColors.primary,
                          icon: Icons.stars_rounded,
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
              title: Text(
                  tr(context, fr: 'Modifier mon profil', ar: 'تعديل ملفي')),
              trailing: const Icon(Icons.chevron_right_rounded),
              // ENTRY GUARD (CodeRabbit): opening the registration flow while
              // the session is in a state where the dossier is already
              // submitted / approved must not blindly re-open the wizard and
              // clobber the persisted registry. The route listener reads the
              // CURRENT verification status dynamically so the badge/tile never
              // serves a stale prompt.
              onTap: () {
                final status = UserStore.user.value?.verificationStatus;
                if (status == ProVerification.approved) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(context,
                          fr: 'Votre profil est déjà vérifié.',
                          ar: 'ملفك موثّق بالفعل.')),
                    ),
                  );
                  return;
                }
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
              subtitle: ValueListenableBuilder<UserModel?>(
                valueListenable: UserStore.user,
                builder: (_, user, __) {
                  final status =
                      user?.verificationStatus ?? ProVerification.none;
                  final label = switch (status) {
                    ProVerification.approved =>
                      tr(context, fr: 'Vérifié', ar: 'موثّق'),
                    ProVerification.pending =>
                      tr(context, fr: 'En cours', ar: 'قيد المراجعة'),
                    ProVerification.rejected =>
                      tr(context, fr: 'Refusé', ar: 'مرفوض'),
                    ProVerification.none =>
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
                  trailing: _PillBadge(
                    label: tr(context,
                        fr: isActive ? 'Actif' : 'Expiré',
                        ar: isActive ? 'نشط' : 'منتهي'),
                    color: isActive ? AppColors.success : AppColors.error,
                  ),
                );
              },
            ),
            // Solde de tokens : badge ∞ illimité pour les abonnés payants,
            // compteur numérique en mode essai (même source que le dashboard).
            ValueListenableBuilder<bool>(
              valueListenable: SubscriptionStore.isPaidSubscriber,
              builder: (_, isPaid, __) => isPaid
                  ? ListTile(
                      leading: const Icon(Icons.all_inclusive_rounded,
                          color: AppColors.success),
                      title: Text(tr(context,
                          fr: 'Solde de tokens', ar: 'رصيد التوكنات')),
                      trailing: _PillBadge(
                        label: tr(context, fr: 'Illimité', ar: 'غير محدود'),
                        color: AppColors.success,
                        icon: Icons.all_inclusive_rounded,
                      ),
                    )
                  : ValueListenableBuilder<int>(
                      valueListenable: ProProfileStore.tokens,
                      builder: (_, tokenCount, ___) => ListTile(
                        leading: const Icon(Icons.diamond_rounded,
                            color: AppColors.success),
                        title: Text(tr(context,
                            fr: 'Solde de tokens', ar: 'رصيد التوكنات')),
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
            ),
            // Legal & about entries (About / Terms / Privacy).
            const LegalMenuTiles(),
            const Divider(),
            // Static, non-clickable support info — directly above Sign-Out.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const SupportInfo(),
            ),
            // Session: full local wipe + back to the welcome flow.
            const LogoutTile(),
          ],
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      // OVERFLOW-PROOF (CodeRabbit): the label is caller-supplied and a long
      // one (e.g. a PRO code + status pair, or a 1.3× text-scale) blew the
      // 360dp-wide profile row by 88px in the E2E harness. The Row is now
      // flexible and the text elides instead of overflowing, so the badge can
      // never paint outside its parent.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
