import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Uber-style full-screen connectivity overlay. When the device loses its
/// network connection, a clean slate-dark sheet covers the app with a clear
/// status message and a manual retry action. It dismisses itself the moment
/// connectivity is restored (stream listener + Retry re-check through
/// [ConnectivityStore]).
class OfflineOverlay extends StatelessWidget {
  const OfflineOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityStore.isOnline,
      builder: (context, online, _) {
        if (online) return child;
        return Stack(
          children: [
            child,
            const Positioned.fill(child: _OfflineSheet()),
          ],
        );
      },
    );
  }
}

class _OfflineSheet extends StatelessWidget {
  const _OfflineSheet();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.slate900,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: AppColors.slate800,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: AppColors.secondary,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  tr(context,
                      fr: 'En attente de connexion Internet',
                      ar: 'في انتظار الاتصال بالإنترنت'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(context,
                      fr:
                          'Le chargement reprendra automatiquement dès le rétablissement de la connexion.',
                      ar: 'سيتم استئناف التحميل تلقائياً فور إعادة الاتصال بالشبكة.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => ConnectivityStore.checkNow(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(
                      tr(context, fr: 'Réessayer', ar: 'إعادة المحاولة')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(
                        color: AppColors.secondary, width: 1.6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}