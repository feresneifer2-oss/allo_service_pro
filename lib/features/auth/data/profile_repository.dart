import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';

/// Supabase gateway for the live `profiles` table.
///
/// CONTRACT:
///   • One row per authenticated identity — the primary key IS the Supabase
///     `auth.users.id` (UUID), mirroring the standard Supabase schema
///     (`profiles.id references auth.users(id)`).
///   • Upsert happens at every remote sign-in / OTP verification so a new
///     identity immediately materializes its row; an existing row is
///     refreshed with the current session profile (name / phone) WITHOUT
///     ever overwriting the role: the role is chosen in-app at onboarding
///     and is NOT an auth concern.
///   • Row-level security scopes every statement to the caller's own row.
///
/// FAILURE POLICY: failure-tolerant like [OrdersRepository] — logged and
/// swallowed; a no-op when Supabase is not initialized.
class ProfileRepository {
  ProfileRepository._();

  static const String _table = 'profiles';

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ATOMIC INSERT-or-refresh of the caller's own profile row.
  ///
  /// A single `upsert` (`ON CONFLICT (id) DO UPDATE`) replaces the previous
  /// select-then-update/insert round trip:
  ///   • ONE atomic statement — no read/write race between two concurrent
  ///     sign-ins of the same identity (the old flow could observe "no row"
  ///     twice and then fail the second INSERT on the primary key);
  ///   • `role` is OMITTED from the payload when [role] is null, and
  ///     `DO UPDATE` only rewrites the columns PRESENT in the payload — so an
  ///     existing row keeps its onboarding-chosen role, while the first
  ///     materialization of an identity writes it.
  static Future<bool> upsertProfile({
    required String id,
    required String email,
    required String name,
    required String phone,
    String? role,
  }) async {
    if (!isConfigured) return false;
    try {
      final row = <String, dynamic>{
        'id': id,
        'email': email,
        'name': name,
        'phone': phone,
        if (role != null && role.isNotEmpty) 'role': role,
      };
      await Supabase.instance.client.from(_table).upsert(row, onConflict: 'id');
      return true;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'ProfileRepository.upsertProfile');
      return false;
    }
  }

  /// SELECT of the caller's own profile row, or null when absent.
  static Future<Map<String, dynamic>?> fetchProfile(String id) async {
    if (!isConfigured) return null;
    try {
      return await Supabase.instance.client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'ProfileRepository.fetchProfile');
      return null;
    }
  }
}
