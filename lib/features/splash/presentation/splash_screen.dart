import 'dart:async';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
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

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      // Session-aware routing: restored sessions skip onboarding entirely.
      final user = UserStore.user.value;
      final Widget destination;
      if (user != null &&
          user.role == UserRole.professional &&
          !user.needsVerificationGate) {
        destination = const ProShell();
      } else if (user != null && user.role == UserRole.client) {
        destination = const ClientShell();
      } else {
        destination = const WelcomeScreen();
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    });
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
