import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/welcome_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Bilingual "تسجيل الخروج / Déconnexion" tile shared by the client,
/// professional and admin settings screens.
///
/// Tapping asks for confirmation, then performs the full local session
/// wipe ([UserStore.signOutAndReset]) and rebuilds the navigation stack
/// down to the welcome / auth entry point — so closing & reopening the
/// app afterwards can never auto-restore the previous session.
class LogoutTile extends StatelessWidget {
  const LogoutTile({super.key});

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(
          tr(dialogContext, fr: 'Se déconnecter ?', ar: 'تسجيل الخروج؟'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          tr(
            dialogContext,
            fr: 'Votre session et vos données locales seront effacées de cet appareil.',
            ar: 'سيتم مسح جلستك وبياناتك المحلية من هذا الجهاز.',
          ),
          style: const TextStyle(color: AppColors.slate400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(dialogContext, fr: 'Annuler', ar: 'إلغاء')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(tr(dialogContext, fr: 'Déconnexion', ar: 'خروج')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await UserStore.signOutAndReset();

    if (!context.mounted) return;
    // Rebuild the whole stack: nothing of the previous session remains.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.logout_rounded, color: AppColors.error),
      title: Text(
        tr(context, fr: 'Déconnexion', ar: 'تسجيل الخروج'),
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        tr(context,
            fr: 'Effacer la session de cet appareil',
            ar: 'مسح الجلسة من هذا الجهاز'),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      onTap: () => _confirmAndSignOut(context),
    );
  }
}