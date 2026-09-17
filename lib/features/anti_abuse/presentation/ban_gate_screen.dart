import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/constants/app_constants.dart';
import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Full-screen gate shown when a client account has been auto-banned by the
/// anti-abuse system (≥ 50 silent cancellations).
///
/// This screen is intentionally final: there is no "go back" path. The
/// `Sign out` button calls [signOutAndReset] (passed in) to return the user
/// to the welcome flow. The support number from [AppConstants.adminSupportNumber]
/// is rendered in both languages.
class AntiAbuseBanGateScreen extends StatelessWidget {
  const AntiAbuseBanGateScreen({
    super.key,
    required this.signOutAndReset,
  });

  /// Action that clears the full session on confirmation.
  final VoidCallback signOutAndReset;

  @override
  Widget build(BuildContext context) {
    final isArabic = appLocale.value.languageCode == 'ar';

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.secondarySurface,
                  child: Icon(
                    Icons.block,
                    size: 56,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  trGlobal(
                    fr: 'Compte bloqué',
                    ar: 'تم حظر الحساب',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  trGlobal(
                    fr: 'Ce compte a été automatiquement bloqué car il a '
                        'atteint ${AppConstants.antiAbuseCancellationLimit} '
                        'annulations.',
                    ar: 'تم حظر هذا الحساب تلقائياً لأنه وصل إلى '
                        '${AppConstants.antiAbuseCancellationLimit} '
                        'إلغاء.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  trGlobal(
                    fr: 'Pour plus d\'informations, contactez le support :',
                    ar: 'للمزيد من المعلومات، اتصل بدعم العملاء:',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppConstants.adminSupportNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.primary,
                  ),
                ),
                if (isArabic)
                  const SizedBox(height: 2),
                if (isArabic)
                  Text(
                    AppConstants.adminSupportNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      AppLogger.info(
                        'AntiAbuse',
                        'User confirmed ban gate — signing out.',
                      );
                      signOutAndReset();
                    },
                    icon: const Icon(Icons.logout),
                    label: Text(
                      trGlobal(fr: 'Se déconnecter', ar: 'تسجيل الخروج'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
