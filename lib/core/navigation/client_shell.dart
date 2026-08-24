import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
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
    return Scaffold(
      body: _screens[_index],
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
