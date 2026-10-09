import 'dart:async';
import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/widgets/allo_service_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

      var roleKey = await UserStore.checkInitialSession();
      if (!mounted) return;
      if (roleKey == null) {
        // PERSISTED REMOTE SESSION (Phase 3U): the e-mail code is a sign-UP
        // step, so a returning identity must re-enter DIRECTLY. When the local
        // login markers are gone (app data cleared, a degraded first boot, a
        // failed hydration…) but the Supabase session is still on disk
        // (`persistSession`), the device re-binds that identity instead of
        // showing the code again.
        roleKey = await _restoreRemoteSession();
        if (!mounted) return;
      }

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

  /// Re-enters with a PERSISTED Supabase session when no LOCAL session marker
  /// was found (Phase 3U).
  ///
  /// The remote identity is still authenticated server-side, so replaying the
  /// e-mail code would be a needless second challenge: the identity is bound
  /// locally ([UserStore.bindRemoteIdentity]) and the route key is re-derived
  /// through the normal [UserStore.checkInitialSession] rules.
  ///
  /// Returns `null` in every other case — no configured/uninitialized client
  /// (local demo builds, widget tests), no session, a binding failure — which
  /// leaves the guest route untouched. A REAL sign-out strips the remote
  /// session too ([SupabaseAuthService.signOut]), so this can never resurrect
  /// a signed-out user.
  Future<String?> _restoreRemoteSession() async {
    if (!SupabaseAuthService.isConfigured) return null;
    final String? email;
    try {
      email = Supabase.instance.client.auth.currentSession?.user.email?.trim();
    } catch (e) {
      debugPrint('SplashScreen: no live Supabase session ($e)');
      return null;
    }
    if (email == null || email.isEmpty) return null;
    // FAIL-CLOSED: an unusable binding keeps the guest route.
    if (!await UserStore.bindRemoteIdentity(email: email)) return null;
    if (!mounted) return null;
    await AdminStore.syncSessionStoresForCurrentUser();
    return UserStore.checkInitialSession();
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
