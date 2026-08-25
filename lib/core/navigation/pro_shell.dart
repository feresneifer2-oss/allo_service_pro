import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_dashboard_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/pro_profile_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/subscription_paywall_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  final _screens = const [
    ProDashboardScreen(),
    ProRequestsScreen(),
    ProProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Paywall gates:
    // 1. An expired monthly subscription blocks every dashboard feature
    //    until the admin re-activates the account.
    // 2. Trial accounts with a zero token balance are locked too.
    return ValueListenableBuilder<SubscriptionStatus>(
      valueListenable: SubscriptionStore.status,
      builder: (context, status, _) {
        if (status == SubscriptionStatus.expired) {
          return const SubscriptionPaywallScreen();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: SubscriptionStore.isPaidSubscriber,
          builder: (context, isPaid, __) => ValueListenableBuilder<int>(
            valueListenable: ProProfileStore.tokens,
            builder: (context, tokenCount, ___) {
              if (!isPaid && tokenCount <= 0) {
                return const SubscriptionPaywallScreen();
              }
              return Scaffold(
                body: _screens[_index],
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
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
  }
}
