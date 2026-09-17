import 'package:allo_service_pro/features/anti_abuse/application/anti_abuse_store.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';

/// Wires [AntiAbuseStore] to the session layer without an import cycle
/// (the store must not import [UserStore]).
class AntiAbuseBindings {
  AntiAbuseBindings._();

  /// Registers the auto-ban session terminator. Idempotent.
  static void register() {
    AntiAbuseStore.onSessionTerminated = () async {
      // Wipe the live session immediately. Do NOT call AntiAbuseStore.reset:
      // the ban and the silent counter must survive the logout.
      await UserStore.signOutAndReset();
    };
  }
}
