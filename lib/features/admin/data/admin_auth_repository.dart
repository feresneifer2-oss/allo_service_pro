import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';
import '../../auth/application/supabase_auth_service.dart';

/// ─── Admin Auth Repository ──────────────────────────────────────────────
///
/// SERVER-SIDE admin authorization boundary (Phase 1 hardening).
///
/// The client NEVER sees, stores or compares admin credentials: the ONLY
/// authority is the backend — `public.is_admin()`, a SECURITY DEFINER SQL
/// predicate keyed on `auth.uid()` (see
/// `supabase/migrations/20260927173046_phase1_admin_authorization.sql`).
///
/// SECURITY CONTRACT:
///  * No secret ships in the binary: the previous compile-time admin
///    e-mail/password defines and every client-side credential comparison are
///    GONE — nothing left to extract from a built APK/IPA.
///  * Every positive answer comes from a LIVE server round-trip bound to the
///    authenticated Supabase identity.
///  * Every failure mode — offline, RPC error, no session, unknown identity —
///    is FAIL-CLOSED (`false` / `null`): a network fault can never grant the
///    admin shell.
///  * The persisted cold-start marker carries the verified `auth.uid()` only
///    and is re-checked server-side on every boot (see
///    `UserStore.setAdminSession` / `UserStore.checkInitialSession`).
/// ────────────────────────────────────────────────────────────────────────
abstract class AdminAuthRepository {
  /// Server-side check for the CURRENT authenticated identity: `true` if and
  /// only if the backend confirms it is enrolled as an administrator.
  Future<bool> isAdmin();

  /// Admin sign-in attempt: authenticates [email]/[password] against
  /// Supabase Auth, then asks the backend whether that identity is an
  /// administrator.
  ///
  /// Returns the VERIFIED admin UID on success, `null` on ANY failure
  /// (wrong credentials, not an admin, unknown identity, Supabase not
  /// configured, network error).
  Future<String?> verifyAdminCredentials({
    required String email,
    required String password,
  });

  /// Server-side professional provisioning —
  /// `public.admin_provision_professional` (Phase 3P).
  ///
  /// Creates (or re-verifies) the backend row `public.professionals.id =
  /// [userId]` through the admin-only SECURITY DEFINER RPC and reports whether
  /// the server CONFIRMED it. [specialty] / [bio] are optional descriptive
  /// values (never authorization inputs): the RPC stores a null as null and
  /// preserves an already-stored value on conflict.
  ///
  /// Returns the VERIFIED `professional_id` on success; `null` on ANY failure
  /// — unconfigured boundary, no authenticated session, RPC error (offline,
  /// `42501` revoked admin, `23503` missing profile), or an answer that is not
  /// a confirmed `professional_is_verified = true`.
  ///
  /// FAIL-CLOSED and NEVER swallowed: the error is reported through the app
  /// error boundary and surfaced to the caller as `null`, which MUST abort the
  /// local approval — the UI may never show an approved professional the
  /// server does not know. No credential/token/key is ever passed here.
  Future<String?> provisionProfessional({
    required String userId,
    String? specialty,
    String? bio,
  });

  /// Server-side professional rejection —
  /// `public.admin_reject_professional` (Phase 3P).
  ///
  /// Flips the backend row `public.professionals.id = [userId]` to
  /// `status = 'rejected'`, stores [reason] as `rejection_reason` and clears
  /// `is_verified`, through the admin-only SECURITY DEFINER RPC, and reports
  /// whether the server CONFIRMED it (the returned `professional_id` row).
  ///
  /// Returns `true` only when the server answered with that confirmation;
  /// `false` on ANY failure — unconfigured boundary, blank identity, no
  /// authenticated session, RPC error (offline, `42501` revoked admin,
  /// `23503` missing profile) or an empty answer. FAIL-CLOSED and NEVER
  /// swallowed: the error is reported through the app error boundary and
  /// surfaced to the caller as `false`, which MUST abort the local rejection —
  /// the UI may never show a professional rejected locally that the server
  /// still holds as pending/approved. No credential/token/key is ever passed.
  Future<bool> rejectProfessional({
    required String userId,
    required String reason,
  });

  /// Admin-only: sets professionals.paid_until for the given user.
  /// null p_until → clears the subscription (unpaid).
  /// Returns true on success (server confirmed), false otherwise.
  Future<bool> setSubscription({
    required String userId,
    DateTime? until,
  });

  /// Admin-only: adjusts the token balance by delta (may be negative).
  /// Returns the NEW balance on success, null otherwise.
  Future<int?> adjustTokens({
    required String userId,
    required int delta,
  });

  /// Whether this environment can reach the authorization backend at all.
  /// A closed (unconfigured) boundary must always deny.
  bool get isConfigured;

  /// UID of the identity confirmed by the LAST successful check, or `null`
  /// when that check failed or never ran.
  ///
  /// [UserStore] binds the persisted admin routing marker to this UID, so a
  /// marker left behind by ANOTHER identity can never route to the admin
  /// shell.
  String? get lastVerifiedUserId;
}

/// PRODUCTION implementation — Supabase Auth (`signInWithPassword`) + the
/// `public.is_admin()` RPC.
///
/// SIGN-IN FLOW: the operator presents their REAL Supabase e-mail/password —
/// there is no client-side secret to compare against, because the secret does
/// not exist in the binary. Supabase Auth creates the session and the backend
/// then decides membership from that session's `auth.uid()`.
///
/// COLD START: [isAdmin] re-runs the same server check against the persisted
/// Supabase session, so an enrolment revoked server-side closes the admin
/// route at the next launch instead of surviving on a stale preference.
class SupabaseAdminAuthRepository implements AdminAuthRepository {
  String? _lastVerifiedUserId;

  @override
  bool get isConfigured => SupabaseAuthService.isConfigured;

  @override
  String? get lastVerifiedUserId => _lastVerifiedUserId;

  @override
  Future<bool> isAdmin() async {
    // Reset FIRST: a failed check must never leave a previously verified UID
    // behind for a caller (UserStore) to trust.
    _lastVerifiedUserId = null;
    final uid = SupabaseAuthService.currentUserId;
    if (uid == null) return false;
    try {
      final answer = await Supabase.instance.client.rpc('is_admin');
      // PostgREST answers with a JSON boolean; anything else is NOT a `true`.
      final confirmed = answer == true;
      if (confirmed) _lastVerifiedUserId = uid;
      return confirmed;
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'AdminAuth.isAdmin');
      return false; // FAIL-CLOSED: no server answer, no admin route.
    }
  }

  @override
  Future<String?> provisionProfessional({
    required String userId,
    String? specialty,
    String? bio,
  }) async {
    // Same fail-closed boundary as [isAdmin]: an unreachable backend can
    // never CONFIRM a provisioning, so the attempt is refused up front.
    if (!SupabaseAuthService.isConfigured) return null;
    if (userId.trim().isEmpty) return null;
    // The RPC authorizes through auth.uid()/is_admin(): without an
    // authenticated session it can only be refused server-side, so it is
    // refused here first (no round-trip, no raw failure surfaced as success).
    if (SupabaseAuthService.currentUserId == null) return null;
    try {
      final answer = await Supabase.instance.client.rpc(
        'admin_provision_professional',
        // Parameter names ONLY: no credential, token or key is sent — the
        // call rides the existing authenticated session's JWT, and the
        // backend re-decides with `public.is_admin()`.
        params: <String, dynamic>{
          'p_user_id': userId,
          'p_specialty': specialty,
          'p_bio': bio,
        },
      );
      return _verifiedProvisionedId(answer);
    } catch (e, st) {
      // NOT swallowed: the provisioning failure is reported with context…
      AppErrorHandler.report(
        e,
        st,
        context: 'AdminAuth.provisionProfessional',
      );
      // …and handed back as `null` — the caller's hard fail-closed signal.
      return null;
    }
  }

  @override
  Future<bool> rejectProfessional({
    required String userId,
    required String reason,
  }) async {
    // Same fail-closed boundary as [provisionProfessional]: an unreachable
    // backend can never CONFIRM a rejection, so the attempt is refused up
    // front.
    if (!SupabaseAuthService.isConfigured) return false;
    if (userId.trim().isEmpty) return false;
    // The RPC authorizes through auth.uid()/is_admin(): without an
    // authenticated session it can only be refused server-side, so it is
    // refused here first (no round-trip, no raw failure surfaced as success).
    if (SupabaseAuthService.currentUserId == null) return false;
    try {
      final answer = await Supabase.instance.client.rpc(
        'admin_reject_professional',
        // Parameter names ONLY: no credential, token or key is sent — the
        // call rides the existing authenticated session's JWT, and the
        // backend re-decides with `public.is_admin()`.
        params: <String, dynamic>{
          'p_user_id': userId,
          'p_reason': reason,
        },
      );
      return _rejectedProfessionalId(answer) != null;
    } catch (e, st) {
      // NOT swallowed: the rejection failure is reported with context…
      AppErrorHandler.report(
        e,
        st,
        context: 'AdminAuth.rejectProfessional',
      );
      // …and handed back as `false` — the caller's hard fail-closed signal.
      return false;
    }
  }

  @override
  Future<bool> setSubscription({
    required String userId,
    DateTime? until,
  }) async {
    if (!SupabaseAuthService.isConfigured) return false;
    if (userId.trim().isEmpty) return false;
    if (SupabaseAuthService.currentUserId == null) return false;
    try {
      await Supabase.instance.client.rpc(
        'admin_set_subscription',
        params: <String, dynamic>{
          'p_pro_id': userId,
          'p_until': until?.toUtc().toIso8601String(),
        },
      );
      return true;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'AdminAuth.setSubscription',
      );
      return false;
    }
  }

  @override
  Future<int?> adjustTokens({
    required String userId,
    required int delta,
  }) async {
    if (!SupabaseAuthService.isConfigured) return null;
    if (userId.trim().isEmpty) return null;
    if (SupabaseAuthService.currentUserId == null) return null;
    try {
      final answer = await Supabase.instance.client.rpc(
        'admin_adjust_tokens',
        params: <String, dynamic>{
          'p_pro_id': userId,
          'p_delta': delta,
        },
      );
      // The RPC returns integer (new balance).
      if (answer is int) return answer;
      if (answer is num) return answer.toInt();
      return null;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'AdminAuth.adjustTokens',
      );
      return null;
    }
  }

  /// Extracts the confirmed `professional_id` from an RPC answer shaped
  /// `returns table (professional_id uuid)` — `null` unless the server
  /// returned a row. A LIST of row objects is what PostgREST hands back for
  /// `returns table`; a composite answer arrives as a single object — both
  /// shapes are accepted. An empty list (RPC matched nothing) or any other
  /// shape is NOT a confirmation.
  static String? _rejectedProfessionalId(Object? answer) {
    final Map<String, dynamic>? row;
    if (answer is Map<String, dynamic>) {
      row = answer;
    } else if (answer is List &&
        answer.isNotEmpty &&
        answer.first is Map<String, dynamic>) {
      row = answer.first as Map<String, dynamic>;
    } else {
      return null;
    }
    final id = row['professional_id'];
    if (id is! String || id.trim().isEmpty) return null;
    return id.trim();
  }

  /// Extracts the professional UUID from the RPC answer — `null` unless the
  /// server explicitly confirmed `professional_is_verified = true`.
  ///
  /// `returns table (…)` reaches PostgREST clients as a LIST of row objects
  /// (a composite answer would arrive as a single object), so both shapes are
  /// accepted; anything else is NOT a confirmed provisioning.
  static String? _verifiedProvisionedId(Object? answer) {
    final Map<String, dynamic>? row;
    if (answer is Map<String, dynamic>) {
      row = answer;
    } else if (answer is List &&
        answer.isNotEmpty &&
        answer.first is Map<String, dynamic>) {
      row = answer.first as Map<String, dynamic>;
    } else {
      row = null;
    }
    if (row == null) return null;
    if (row['professional_is_verified'] != true) return null;
    final id = row['professional_id'];
    if (id is! String || id.trim().isEmpty) return null;
    return id.trim();
  }

  @override
  Future<String?> verifyAdminCredentials({
    required String email,
    required String password,
  }) async {
    _lastVerifiedUserId = null;
    if (email.isEmpty || password.isEmpty) return null;
    if (!SupabaseAuthService.isConfigured) return null;
    final signedIn =
        await SupabaseAuthService.signInWithPassword(email, password);
    if (!signedIn) return null;
    // Membership is decided on the uid that just authenticated — never on the
    // e-mail string the caller typed.
    if (await isAdmin()) return _lastVerifiedUserId;
    // Correct credentials but NOT an administrator: drop the session this
    // attempt created (local scope — a valid identity is not revoked
    // remotely) so a non-admin Supabase session neither lingers on disk nor
    // displaces the local app session.
    await SupabaseAuthService.clearLocalSession();
    return null;
  }
}

/// Resolution point for the active [AdminAuthRepository].
///
/// The DEFAULT is the production, server-side Supabase implementation — the
/// client-side credential seam was removed in Phase 1. Call sites (AdminStore,
/// LoginScreen, UserStore) depend only on the abstraction, and tests inject
/// fakes via [configure].
class AdminAuth {
  AdminAuth._();

  static AdminAuthRepository _repository = SupabaseAdminAuthRepository();

  static AdminAuthRepository get instance => _repository;

  /// Test hook: swap the active repository (debug/test builds only).
  @visibleForTesting
  static void configure(AdminAuthRepository repository) {
    if (kReleaseMode || kProfileMode) {
      throw StateError(
        'AdminAuth.configure is unavailable in release/profile builds.',
      );
    }
    _repository = repository;
  }

  /// Test hook: restore the default (production) repository.
  @visibleForTesting
  static void resetToDefault() {
    _repository = SupabaseAdminAuthRepository();
  }
}
