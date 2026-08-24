import 'package:flutter/material.dart';
import 'package:allo_service_pro/features/home/presentation/home_screen.dart';
import 'package:allo_service_pro/features/booking/presentation/booking_list_screen.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _index = 0;

  // OLD: kenet _ClientBookingsPlaceholder()
  // NEW: wallew BookingListScreen()
  final _screens = const [
    HomeScreen(),
    _ClientSearchPlaceholder(),
    BookingListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: const Color(0xFFEFF6FF), // light blue
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded),
            label: "Search",
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            selectedIcon: Icon(Icons.receipt_long_rounded),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text("Search")),
      body: const SafeArea(
        child: Center(
          child: Text(
            "Search screen (soon)",
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }
}