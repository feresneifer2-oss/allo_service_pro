import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/verifying_screen.dart';
import 'package:allo_service_pro/features/auth/presentation/welcome_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_dashboard_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_profile_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/subscription_paywall_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/logout_tile.dart';

/// Null/empty-safe identity comparator. Two pro ids only match when BOTH
/// sides are non-null and non-empty — a half-populated account (missing
/// proCode or id) can never match another row, preventing null-ref errors,
/// accidental deactivation and blank screens from stale lookups.
bool _sameIdentity(String? a, String? b) {
  if (a == null || b == null) return false;
  if (a.isEmpty || b.isEmpty) return false;
  return a == b;
}

class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  /// R4 (Phase 9): a shell whose SESSION disappeared must leave for the entry
  /// screen exactly once. Without this latch the post-frame callback would be
  /// re-scheduled by every rebuild of the gate chain.
  bool _exitingToWelcome = false;

  void _exitToWelcome() {
    if (_exitingToWelcome) return;
    _exitingToWelcome = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    });
  }

  final _screens = const [
    ProDashboardScreen(),
    ProRequestsScreen(),
    ProProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // ── Fully reactive gate chain ──────────────────────────────────────────
    // Every gate listens to its source-of-truth ValueNotifier, so admin
    // actions (approve / suspend / reactivate / subscription grant) reflect
    // on the pro session INSTANTLY — no restart, no re-login.
    return ValueListenableBuilder<UserModel?>(
      valueListenable: UserStore.user,
      builder: (context, sessionUser, _) {
        return ValueListenableBuilder<List<PendingProModel>>(
          valueListenable: AdminStore.pendingPros,
          builder: (context, registry, __) {
            // ── Gate -1 · Admin deactivation ──────────────────────────────
            // A deactivated pro cannot access the dashboard at all (no
            // orders, no chat) until the admin re-activates the account.
            if (sessionUser != null && sessionUser.isProfessional) {
              var deactivated = false;
              for (final p in registry) {
                if (!p.deactivated) continue;
                if (_sameIdentity(p.proCode, sessionUser.proCode) ||
                    _sameIdentity(p.id, sessionUser.id) ||
                    _sameIdentity(p.proCode, sessionUser.id) ||
                    _sameIdentity(p.id, sessionUser.proCode)) {
                  deactivated = true;
                  break;
                }
              }
              if (deactivated) return const _ProDeactivatedScreen();
            }

            // ── Gate 0 · Verification ──────────────────────────────────────
            // Unverified professionals are blocked until the admin approves
            // them. When the admin approves (UserStore.user updates), this
            // builder re-runs and the dashboard appears immediately.
            // A NULL session or a NULL/unknown role inside the PRO shell can
            // never be read as "approved": it falls to the SAME gate, so a
            // stale or missing role (e.g. an auth-binding downgrade) can no
            // longer bypass the pending-approval screen. Client sessions
            // never route here (they land on ClientShell), so their routing
            // is untouched.
            // Phase 7-5b · R4 (Phase 9): Gate 0 priority, most-specific first:
            // 1. NO session at all → leave for the entry screen (R4, below).
            // 2. Missing role.
            // 3. Explicit rejection → the Gate, with its reason.
            // 4. Unconfirmed read (transient failure) for a NON-pending state
            //    (none / approved) → VerifyingScreen.
            // 5. Known pending → the Gate.
            // 6. Otherwise → Dashboard.
            // ── R4 (Phase 9) · Session ended ──────────────────────────────
            // A NULL session is NOT a verification state: it means the auth
            // session is gone (sign-out, expiry, revoked token, partial
            // hydration). The old code parked it on the verification gate,
            // whose own null branch rendered a spinner with no AppBar and no
            // action — a dead end that needed an app kill. Send it back to the
            // entry screen instead; `checkInitialSession` (R6) already stops a
            // stale marker from routing here in the first place.
            if (sessionUser == null) {
              _exitToWelcome();
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // A KNOWN session with an unknown role still fails closed: it can
            // never be read as "approved".
            if (sessionUser.role == null) {
              return const VerificationGateScreen();
            }

            if (sessionUser.verificationStatus.isRejected) {
              return const VerificationGateScreen();
            }

            // PENDING IS EXCLUDED ON PURPOSE: an account the admin has not
            // decided on yet must keep the pending gate even when server
            // confirmation is unavailable — "vérification en cours" would
            // promise a decision that was never made, and the retry loop
            // would hide the real status indefinitely. `none` and `approved`
            // are the states a transient failure may legitimately mask, so
            // only those fall through to the VerifyingScreen.
            if (sessionUser.verificationUnconfirmed &&
                !sessionUser.verificationStatus.isPending) {
              return const VerifyingScreen();
            }

            if (sessionUser.needsVerificationGate) {
              return const VerificationGateScreen();
            }

            // Paywall gates:
            // 1. An expired monthly subscription blocks every dashboard
            //    feature until the admin re-activates the account.
            // 2. Trial accounts that ran their balance dry through REAL
            //    usage (tokensConsumed) are locked too — a fresh trial
            //    with a manually-adjusted 0 balance is left on the shell.
            return ValueListenableBuilder<SubscriptionStatus>(
              valueListenable: SubscriptionStore.status,
              builder: (context, status, _) {
                if (status == SubscriptionStatus.expired) {
                  return const SubscriptionPaywallScreen(
                    reason: PaywallReason.subscriptionExpired,
                  );
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: SubscriptionStore.isPaidSubscriber,
                  builder: (context, isPaid, __) => ValueListenableBuilder<int>(
                    valueListenable: ProProfileStore.tokens,
                    builder: (context, tokenCount, ___) {
                      if (!isPaid &&
                          tokenCount <= 0 &&
                          ProProfileStore.tokensConsumed.value) {
                        // Token exhaustion lock: ONLY a trial that has been
                        // genuinely used (real orders spent its balance) is
                        // locked. A brand-new trial account whose balance was
                        // touched manually (admin/dev adjust) stays on the
                        // dashboard — no premature paywall.
                        return const SubscriptionPaywallScreen(
                          reason: PaywallReason.tokensExhausted,
                        );
                      }
                      return Scaffold(
                        // IndexedStack preserves each tab's state across
                        // switches.
                        body: IndexedStack(
                          index: _index,
                          children: _screens,
                        ),
                        bottomNavigationBar: NavigationBar(
                          selectedIndex: _index,
                          onDestinationSelected: (i) =>
                              setState(() => _index = i),
                          indicatorColor: AppColors.secondarySurface,
                          destinations: [
                            NavigationDestination(
                              icon: const Icon(Icons.dashboard_outlined),
                              selectedIcon: const Icon(Icons.dashboard_rounded,
                                  color: AppColors.primary),
                              label: tr(context, fr: 'Dashboard', ar: 'لوحة'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.inbox_outlined),
                              selectedIcon: const Icon(Icons.inbox_rounded,
                                  color: AppColors.primary),
                              label: tr(context, fr: 'Demandes', ar: 'الطلبات'),
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.person_outline_rounded),
                              selectedIcon: const Icon(Icons.person_rounded,
                                  color: AppColors.primary),
                              label: tr(context, fr: 'Profil', ar: 'الملف'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Full-screen block shown when the admin deactivates this pro's
/// account: no dashboard, no orders, no chat — until re-activation.
class _ProDeactivatedScreen extends StatelessWidget {
  const _ProDeactivatedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block_rounded,
                    color: AppColors.error, size: 64),
                const SizedBox(height: 16),
                Text(
                  tr(context, fr: 'Compte désactivé', ar: 'تم تجميد حسابك'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    fr: "Votre compte a été désactivé par l'administration. Contactez le support pour le réactiver.",
                    ar: 'تم تجميد حسابك من طرف الإدارة. تواصل مع الدعم لإعادة تفعيله.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                const LogoutTile(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
