import 'package:flutter/material.dart';

import 'package:allo_service_pro/features/anti_abuse/application/anti_abuse_store.dart';
import 'package:allo_service_pro/features/anti_abuse/presentation/ban_gate_screen.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';

/// Navigation interceptor for the 50-cancellation auto-ban.
///
/// When [AntiAbuseStore.showBanGate] is true this widget replaces [child]
/// with [AntiAbuseBanGateScreen] at the [MaterialApp] builder level, so no
/// route (shell, splash, login) can be reached until the user acknowledges.
class AntiAbuseGate extends StatelessWidget {
  const AntiAbuseGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AntiAbuseStore.showBanGate,
      builder: (context, blocked, _) {
        if (!blocked) return child;
        return AntiAbuseBanGateScreen(
          signOutAndReset: () async {
            await UserStore.signOutAndReset();
            AntiAbuseStore.acknowledgeBanGate();
          },
        );
      },
    );
  }
}
