import 'dart:async';
import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/widgets/allo_service_logo.dart';
import '../../auth/presentation/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();

    _checkAuthAndRoute();
  }

  Future<void> _checkAuthAndRoute() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final roleKey = await UserStore.checkInitialSession();
      if (!mounted) return;

      Widget destination = const WelcomeScreen();
      if (roleKey != null) {
        destination = switch (roleKey) {
          'admin' => const AdminDashboardScreen(),
          'professionnel' => const ProShell(),
          'client' => const ClientShell(),
          _ => const WelcomeScreen(),
        };
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      debugPrint('SplashScreen: session routing failed: $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _animation,
          child: const AlloServiceLogo(imageWidth: 220),
        ),
      ),
    );
  }
}
