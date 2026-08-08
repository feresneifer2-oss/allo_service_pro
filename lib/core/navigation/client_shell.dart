import 'package:flutter/material.dart';
import 'package:allo_service_pro/features/home/presentation/home_screen.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int index = 0;

  final screens = const [
    HomeScreen(),
    _ClientSearchPlaceholder(),
    _ClientBookingsPlaceholder(),
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: "Search",
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: "Bookings",
          ),
        ],
      ),
    );
  }
}

class _ClientSearchPlaceholder extends StatelessWidget {
  const _ClientSearchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text("Search screen (soon)"),
        ),
      ),
    );
  }
}

class _ClientBookingsPlaceholder extends StatelessWidget {
  const _ClientBookingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text("Bookings history (soon)"),
        ),
      ),
    );
  }
}