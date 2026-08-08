import 'package:flutter/material.dart';
import 'package:allo_service_pro/features/dashboard/presentation/pro_dashboard_screen.dart';

class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int index = 0;

  final screens = const [
    ProDashboardScreen(),
    _ProRequestsPlaceholder(),
    _ProProfilePlaceholder(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: "Dashboard",
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: "Requests",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

class _ProRequestsPlaceholder extends StatelessWidget {
  const _ProRequestsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text("Requests (soon)"),
        ),
      ),
    );
  }
}

class _ProProfilePlaceholder extends StatelessWidget {
  const _ProProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text("Pro profile (soon)"),
        ),
      ),
    );
  }
}