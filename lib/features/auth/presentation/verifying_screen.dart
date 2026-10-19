import 'dart:async';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/application/verification_sync_service.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Phase 7-5: shown when a Pro is approved locally but the last server
/// re-check failed (transient network). Non-blocking: a ValueListenableBuilder
/// in ProShell watches UserStore.user and rebuilds automatically once
/// verificationUnconfirmed becomes false.
class VerifyingScreen extends StatefulWidget {
  const VerifyingScreen({super.key});

  @override
  State<VerifyingScreen> createState() => _VerifyingScreenState();
}

class _VerifyingScreenState extends State<VerifyingScreen> {
  Timer? _tick;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    // Kick off an immediate sync (idempotent — service guards on _inFlight).
    unawaited(VerificationSyncService.syncNow(force: true));
    // Tick to update the elapsed display + trigger periodic retries.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      // Every 10 seconds, nudge another sync attempt.
      if (_elapsed % 10 == 0) {
        unawaited(VerificationSyncService.syncNow(force: true));
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  tr(context,
                      fr: 'Vérification de votre compte en cours...',
                      ar: 'جارٍ التحقق من حسابك...'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context,
                      fr: 'Connexion au serveur en cours. Cela peut prendre '
                          'quelques secondes si le réseau est lent.',
                      ar: 'جارٍ الاتصال بالخادم. قد يستغرق بضع ثوانٍ '
                          'إذا كانت الشبكة بطيئة.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '$_elapsed s',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _elapsed = 0);
                    unawaited(VerificationSyncService.syncNow(force: true));
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    tr(context,
                        fr: 'Réessayer maintenant', ar: 'أعد المحاولة الآن'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    final signedOut = await UserStore.signOutAndReset();
                    // Inside build(), `context` is the build PARAMETER (it
                    // shadows State.context) — so the lint requires the
                    // BuildContext's own `.mounted` guard, not State.mounted.
                    if (!context.mounted) return;
                    // The contract (UserStore): `false` means the wipe ABORTED
                    // on a storage failure — the session is still ALIVE, so
                    // surface it instead of leaving a dead-end screen.
                    if (!signedOut) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr(context,
                              fr: 'Déconnexion impossible. Réessayez.',
                              ar: 'تعذّر تسجيل الخروج. أعد المحاولة.')),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  child: Text(
                    tr(context, fr: 'Se déconnecter', ar: 'تسجيل الخروج'),
                    style: const TextStyle(color: Colors.white54),
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
