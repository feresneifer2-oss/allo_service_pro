import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/home/presentation/home_screen.dart';
import 'package:allo_service_pro/features/profile/presentation/customer_profile_screen.dart';
import 'package:allo_service_pro/features/requests/presentation/request_list_screen.dart';
import 'package:allo_service_pro/features/search/presentation/search_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    SearchScreen(),
    RequestListScreen(),
    MessagesListScreen(),
    CustomerProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final me = UserStore.user.value;
    return ValueListenableBuilder<List<String>>(
      // Reactive ban gate: the instant an admin suspends this client, the
      // whole shell is swapped for a locked screen — and back the moment the
      // account is re-activated. No app restart or pull-to-refresh needed.
      valueListenable: AdminStore.suspendedClients,
      builder: (_, suspended, __) {
        if (me != null && suspended.contains(me.id)) {
          return const _AccountLockedScreen();
        }
        return _buildShell(context);
      },
    );
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab's scroll position, search text and
      // form state alive while switching (Uber-style persistent tabs).
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: AppColors.secondarySurface,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon:
                const Icon(Icons.home_rounded, color: AppColors.primary),
            label: tr(context, fr: 'Accueil', ar: 'الرئيسية'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_rounded),
            selectedIcon:
                const Icon(Icons.search_rounded, color: AppColors.primary),
            label: tr(context, fr: 'Recherche', ar: 'بحث'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded,
                color: AppColors.primary),
            label: tr(context, fr: 'Demandes', ar: 'الطلبات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon:
                const Icon(Icons.chat_bubble_rounded, color: AppColors.primary),
            label: tr(context, fr: 'Messages', ar: 'الرسائل'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon:
                const Icon(Icons.person_rounded, color: AppColors.primary),
            label: tr(context, fr: 'Profil', ar: 'الملف'),
          ),
        ],
      ),
    );
  }
}

/// Full-screen "account frozen" lock shown to a client while the admin keeps
/// them suspended. It listens on AdminStore.suspendedClients through the
/// enclosing shell, so it unlocks automatically on re-activation.
class _AccountLockedScreen extends StatelessWidget {
  const _AccountLockedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded,
                    color: AppColors.error, size: 72),
                const SizedBox(height: 16),
                Text(
                  tr(context, fr: 'Compte suspendu', ar: 'الحساب مجمَّد'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context,
                      fr: 'Votre compte a été suspendu par l\'administration. '
                          'Contacter le support pour plus de détails.',
                      ar: 'تم تجميد حسابك من طرف الإدارة. '
                          'راسل الدعم الفني للمزيد من التفاصيل.'),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.slate400, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}