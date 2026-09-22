import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/error/app_error_handler.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Clean, branded replacement for Flutter's red "exception caught" screen.
///
/// CONSTRAINTS (why it looks hand-rolled):
///  * it is produced by `ErrorWidget.builder`, which can run where the widget
///    that failed lived — possibly OUTSIDE `MaterialApp`, without a
///    `Localizations`, `Directionality` or `Scaffold` ancestor. It therefore
///    provides its own [Directionality] + [Material] and localizes through
///    [trGlobal] instead of `tr(context, ...)`;
///  * it must never throw itself: no async work, no inherited dependency that
///    could be the very thing that failed;
///  * it is REACTIVE on the language notifier, so switching FR/AR after the
///    failure re-renders the copy correctly.
///
/// The exception itself is never shown to the user — it is in [AppLogger].
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({
    super.key,
    this.error,
    this.onRetry,
    this.titleFr = 'Une erreur est survenue',
    this.titleAr = 'حدث خطأ ما',
    this.messageFr =
        "L'application a rencontré un problème inattendu. Vos données enregistrées sont intactes : vous pouvez réessayer.",
    this.messageAr =
        'واجه التطبيق مشكلة غير متوقعة. بياناتك المحفوظة سليمة: يمكنك إعادة المحاولة.',
  });

  /// The failure that triggered this view (logged, not displayed).
  final Object? error;

  /// Optional recovery action. When null the button only dismisses the flag.
  final VoidCallback? onRetry;

  final String titleFr;
  final String titleAr;
  final String messageFr;
  final String messageAr;

  void _retry() {
    // Clear the failure flag FIRST so a listener-driven shell can rebuild,
    // then hand control back to the caller's own recovery action.
    AppErrorHandler.clear();
    onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        final rtl = locale.languageCode == 'ar';
        return Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Material(
            color: AppColors.background,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: AppColors.secondarySurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.secondary,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      trGlobal(fr: titleFr, ar: titleAr),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      trGlobal(fr: messageFr, ar: messageAr),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        trGlobal(fr: 'Réessayer', ar: 'إعادة المحاولة'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
