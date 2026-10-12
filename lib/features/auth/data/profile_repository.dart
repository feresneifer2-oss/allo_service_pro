import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';
import '../application/supabase_auth_service.dart';

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
  ///
  /// AUTHENTICATED WRITE (Phase 2I — sign-in session race): the statement is
  /// issued ONLY with a session that authenticates [id], and its JWT is PINNED
  /// on the request itself. The client otherwise resolves `Authorization`
  /// LAZILY at send time from the LIVE session, so a sign-out (e.g. the admin
  /// gate's `clearLocalSession`) or a session that is not installed yet in
  /// that window silently degraded the statement to the anonymous key, and
  /// RLS rejected it (`auth.uid()` NULL → `42501`):
  ///   • the session carried by the `AuthState` event is authoritative; the
  ///     live session is preferred when it belongs to [id] (it may hold a
  ///     freshly refreshed token) and the event session covers the window
  ///     where the live one is absent or already gone;
  ///   • with neither, NO request is issued at all (fail-safe);
  ///   • the resolved JWT is pinned around the request CONSTRUCTION:
  ///     `SupabaseClient.from` snapshots the REST headers synchronously and
  ///     `AuthHttpClient` keeps an `Authorization` header that is already
  ///     present, so the bytes carry the authenticated user's credential.
  /// Builds the wire payload for [upsertProfile] WITHOUT any network call.
  ///
  /// Pure (Supabase-free) so it is unit-testable: the test pins that the
  /// display name travels as `full_name` — the live `public.profiles`
  /// column — and NEVER as `name` (no such column exists server-side).
  /// [upsertProfile] is the only writer and delegates to this builder.
  ///
  /// Phase A: [name] is optional. A null/blank name omits `full_name` from
  /// the row so an e-mail fragment (or any derived placeholder) can never
  /// pollute the column — the DB keeps whatever value is already there (or
  /// leaves it null on first insert).
  @visibleForTesting
  static Map<String, dynamic> buildProfileRow({
    required String id,
    required String email,
    String? name,
    required String phone,
    String? role,
  }) =>
      <String, dynamic>{
        'id': id,
        'email': email,
        // Live schema column is `full_name` (Phase 2C): the Dart parameter
        // stays `name` to keep the public API unchanged. Omitted entirely
        // when no REAL name is known (Phase A).
        if (name != null && name.trim().isNotEmpty) 'full_name': name.trim(),
        'phone': phone,
        if (role != null && role.isNotEmpty) 'role': role,
      };

  /// PURE authenticated-write gate (Phase 2I) — Supabase-free, like
  /// [buildProfileRow], so it is unit-testable without a client.
  ///
  /// The `profiles` policies are `auth.uid() = id`: a statement is only ever
  /// legitimate when the session that signs it carries the SAME identity as
  /// the row being written. Absent session, token-less session, or another
  /// identity's session → Postgres answers `42501` (`auth.uid()` NULL or a
  /// different UUID) — exactly the failure this gate prevents.
  @visibleForTesting
  static bool canWriteOwnRow({
    required String id,
    required String? sessionUserId,
    required String? accessToken,
  }) =>
      sessionUserId != null &&
      sessionUserId == id &&
      accessToken != null &&
      accessToken.isNotEmpty;

  /// [session] itself when it authenticates a write of row [id], else null.
  static Session? _authenticating(Session? session, String id) =>
      session != null &&
              canWriteOwnRow(
                id: id,
                sessionUserId: session.user.id,
                accessToken: session.accessToken,
              )
          ? session
          : null;

  /// Phase A: [name] is optional — null/blank omits `full_name` from the
  /// upsert (see [buildProfileRow]) so the column is never polluted with
  /// an e-mail fragment. Non-breaking: existing callers keep passing a
  /// non-null name and behave exactly as before.
  static Future<bool> upsertProfile({
    required String id,
    required String email,
    String? name,
    required String phone,
    String? role,
    required Session? session,
  }) async {
    if (!isConfigured) return false;
    final client = Supabase.instance.client;

    // AUTHENTICATED-WRITE GATE (Phase 2I): a session is only usable for THIS
    // row when its JWT belongs to `id`. The live session is consulted first —
    // `getSession` also refreshes an expired one, which keeps the pinned token
    // valid on a cold start — and the session carried by the auth event is the
    // fallback for the window where the live one is absent or already dropped
    // (the race behind the anonymous `42501`).
    Session? live;
    try {
      live = await client.auth.getSession();
    } catch (_) {
      // A failed refresh (offline / revoked) is not fatal here: the event
      // session below is still this caller's own credential.
      live = null;
    }
    final attested = _authenticating(live, id) ?? _authenticating(session, id);
    if (attested == null) {
      debugPrint('ProfileRepository.upsertProfile: no authenticated session '
          'for this identity — write skipped (RLS would reject it).');
      return false;
    }

    try {
      final row = buildProfileRow(
        id: id,
        email: email,
        name: name,
        phone: phone,
        role: role,
      );
      // PIN THE AUTHENTICATED JWT ON THE REQUEST (Phase 2I): the client would
      // otherwise resolve `Authorization` at send time from the LIVE session —
      // gone by then in the sign-out race. `setAuth` writes the REST headers,
      // and `SupabaseClient.from` snapshots them SYNCHRONOUSLY, so the request
      // built below carries the authenticated user's credential regardless of
      // what happens to the live session before the bytes leave the device.
      final rest = client.rest;
      rest.setAuth(attested.accessToken);
      try {
        final write = client.from(_table).upsert(row, onConflict: 'id');
        // Released BEFORE the await: no other request can ever observe the pin.
        rest.setAuth(null);
        await write;
      } finally {
        rest.setAuth(null); // idempotent: covers a synchronous build throw.
      }
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

  /// TEST SEAM (pro pending-approval routing): stands in for the live
  /// `public.professionals.is_verified` read. `null` = real read.
  @visibleForTesting
  static Future<bool?> Function()? debugIsVerifiedOverride;

  /// SERVER AUTHORITY — the caller's OWN `public.professionals.is_verified`.
  ///
  /// The professional approval state is decided by the SERVER (the admin-only
  /// `admin_provision_professional` RPC is the only writer of `is_verified`),
  /// so login / session routing must never grant the pro dashboard from local
  /// storage alone:
  ///
  ///   * `true`  → the server confirms this professional IS verified;
  ///   * `false` → the server has NOT verified this professional;
  ///   * `null`  → UNRESOLVED (Supabase unconfigured, no signed-in identity,
  ///     query error, timeout, missing row or column) — callers must FAIL
  ///     CLOSED and never treat it as approved.
  ///
  /// The statement is RLS-scoped to the caller's own row
  /// (`professionals_select_own_row`, phase 3O): it can never read another
  /// professional's row.
  static Future<bool?> fetchOwnProfessionalIsVerified({
    required String id,
  }) async {
    final override = debugIsVerifiedOverride;
    if (override != null) return override();
    if (!isConfigured) return null;
    if (id.trim().isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('professionals')
          .select('is_verified')
          .eq('id', id.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return null;
      return row['is_verified'] == true;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProfileRepository.fetchOwnProfessionalIsVerified',
      );
      return null;
    }
  }

  /// Reads the full server-side Pro verification state for the given user id.
  /// Returns null on any failure (fail-closed). Never throws.
  ///
  /// Shape when successful:
  ///   {
  ///     'status': 'pending' | 'approved' | 'rejected' | null,
  ///     'is_verified': bool?,
  ///     'rejection_reason': String?,
  ///     'approved_at': String?,   // ISO8601
  ///     // Registry-hydration source (Step 6b): the local dossier mirror is
  ///     // seeded from these when the device has no entry for this pro.
  ///     'specialty': String?,
  ///     'bio': String?,
  ///     // Phase 3S — server-side token balance + subscription window
  ///     // (read-only here; writes go through the admin/pro RPCs).
  ///     'tokens': int?,
  ///     'paid_until': String?,    // ISO8601, null when no subscription
  ///     'category_id': String?,
  ///     'service_ids': `List<String>?`,
  ///     'proof_path': String?,
  ///     'selfie_path': String?,
  ///     'work_images': List?,
  ///     'badges': List?,
  ///     'zones': List?,
  ///     'pricing_type': String?,
  ///     'price_from': num?,
  ///   }
  ///
  /// Mirrors [fetchOwnProfessionalIsVerified] exactly: unconfigured Supabase
  /// or a blank identity resolves to `null` WITHOUT issuing a request; the
  /// statement is RLS-scoped to the caller's own row
  /// (`professionals_select_own_row`, phase 3O) and every failure (timeout,
  /// missing row, error) degrades to `null` so callers FAIL CLOSED.
  static Future<Map<String, dynamic>?> fetchOwnProfessionalStatus({
    required String id,
  }) async {
    // TEST SEAM (mirrors the ordering in [fetchOwnProfessionalIsVerified]):
    // when the boolean override stands in for the live read (tests without a
    // Supabase instance), derive the three-state row from it so BOTH server
    // reads stay consistent: true → 'approved', false → 'pending',
    // null → unresolved (fail closed, exactly like a failed query).
    final override = debugIsVerifiedOverride;
    if (override != null) {
      final verified = await override();
      if (verified == null) return null;
      return <String, dynamic>{
        'status': verified ? 'approved' : 'pending',
        'is_verified': verified,
        'rejection_reason': null,
        'category_id': null,
        'service_ids': null,
        'approved_at': null,
        // Same keys as the live select — the seam must not change the SHAPE
        // for callers that read the hydration fields (Step 6b).
        'specialty': null,
        'bio': null,
        // Phase 3S keys — same SHAPE as the live select below so callers can
        // read them regardless of which path produced the row.
        'tokens': null,
        'paid_until': null,
        'proof_path': null,
        'selfie_path': null,
        'work_images': null,
        'badges': null,
        'zones': null,
        'pricing_type': null,
        'price_from': null,
      };
    }
    if (!isConfigured) return null;
    if (id.trim().isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('professionals')
          .select(
              'status, is_verified, rejection_reason, approved_at, specialty, bio, tokens, paid_until, proof_path, selfie_path, work_images, badges, zones, pricing_type, price_from, category_id, service_ids')
          .eq('id', id.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return null;
      return row;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProfileRepository.fetchOwnProfessionalStatus',
      );
      return null;
    }
  }

  /// Re-submits the CURRENT professional's own proof — the server-side reset
  /// of their row through `public.professional_resubmit_own_proof()` (Phase
  /// 3Q — user-facing counterpart of Phase 3P's admin reset).
  ///
  /// USER-FACING: NO id parameter exists — the row acted upon is pinned to
  /// `auth.uid()` server-side, so a caller can only move ITS OWN row, and
  /// only 'rejected' → 'pending' (plus the idempotent 'pending' → 'pending')
  /// is ever accepted; 'approved' and any NULL/unknown status are refused
  /// server-side (42501), a missing row with 23503.
  ///
  /// FAIL-CLOSED: an unconfigured client, a missing session, an RPC error
  /// (offline /42501 /23503) or an unconfirmed answer all resolve to
  /// `false` (reported through the app error boundary) — the caller MUST
  /// then abort its local re-submission. `true` means only that the SERVER
  /// confirmed the reset (a non-empty `professional_id` came back).
  static Future<bool> resubmitOwnProfessionalProof({String? proofPath}) async {
    if (!isConfigured) return false;
    if (SupabaseAuthService.currentUserId == null) return false;
    try {
      final params = <String, dynamic>{};
      if (proofPath != null && proofPath.trim().isNotEmpty) {
        params['p_proof_path'] = proofPath.trim();
      }
      final answer = await Supabase.instance.client.rpc(
        'professional_resubmit_own_proof',
        params: params.isEmpty ? null : params,
      );
      return _confirmedProfessionalId(answer) != null;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProfileRepository.resubmitOwnProfessionalProof',
      );
      return false;
    }
  }

  /// Self-service profile update via the pro_update_profile RPC.
  /// All params are optional; null means "keep existing value".
  /// Returns true on success, false on any failure (fail-closed).
  static Future<bool> updateOwnProfessionalProfile({
    String? specialty,
    String? bio,
    String? pricingType,
    num? priceFrom,
    List<String>? workImages,
    List<String>? zones,
  }) async {
    if (!isConfigured) return false;
    if (SupabaseAuthService.currentUserId == null) return false;
    try {
      final params = <String, dynamic>{};
      if (specialty != null && specialty.trim().isNotEmpty) {
        params['p_specialty'] = specialty.trim();
      }
      if (bio != null && bio.trim().isNotEmpty) {
        params['p_bio'] = bio.trim();
      }
      if (pricingType != null && pricingType.trim().isNotEmpty) {
        params['p_pricing_type'] = pricingType.trim();
      }
      if (priceFrom != null) {
        params['p_price_from'] = priceFrom;
      }
      if (workImages != null) {
        params['p_work_images'] = workImages;
      }
      if (zones != null) {
        params['p_zones'] = zones;
      }
      if (params.isEmpty) return true; // nothing to update
      final answer = await Supabase.instance.client.rpc(
        'pro_update_profile',
        params: params,
      );
      if (answer is List && answer.isNotEmpty) {
        final row = answer.first;
        if (row is Map && row['updated_id'] != null) return true;
      }
      if (answer is Map && answer['updated_id'] != null) return true;
      return false;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProfileRepository.updateOwnProfessionalProfile',
      );
      return false;
    }
  }

  /// Extracts the confirmed `professional_id` from an RPC answer shaped
  /// `returns table (professional_id uuid)` — `null` unless the server
  /// returned a row. A LIST of row objects is what PostgREST hands back for
  /// `returns table`; a composite answer arrives as a single object — both
  /// shapes are accepted. An empty list (RPC matched nothing) or any other
  /// shape is NOT a confirmation.
  /// Mirrors `AdminAuthRepository._rejectedProfessionalId` (Step 4b).
  static String? _confirmedProfessionalId(Object? answer) {
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

  /// Creates the CURRENT professional's own `public.professionals` row as the
  /// freshly-collected PENDING registration — the server-side half of the
  /// registration submit (Phase 2 Step 5).
  ///
  /// Mirrors the Phase 3P own-row INSERT policy
  /// (`professionals_insert_own_row`: `with check (auth.uid() = id)`): the row
  /// `id` is pinned to the caller's Supabase UUID (never a caller-controlled
  /// parameter), and the FIXED outcome columns are written here —
  /// `status: 'pending'`, `is_verified: false`; `rejection_reason` /
  /// `approved_at` stay NULL by default. `onConflict: 'id'` mirrors the
  /// `profiles` / `pro_availability` upsert shape already used in this
  /// project (single-column conflict target = the table's own primary key).
  ///
  /// FAIL-CLOSED: an unconfigured client, a missing/blank session identity,
  /// a write error (offline / RLS denial / timeout) or an unconfirmed write
  /// all resolve to `false` (reported through the app error boundary) — the
  /// caller MUST then abort the registration submit instead of pretending it
  /// succeeded.
  static Future<bool> upsertOwnProfessionalPending({
    required String specialty,
    required String bio,
    String? proofPath,
    String? selfiePath,
    List<String>? workImages,
    List<String>? zones,
    String? pricingType,
    num? priceFrom,
    String? categoryId,
    List<String>? serviceIds,
  }) async {
    if (!isConfigured) return false;
    final uid = SupabaseAuthService.currentUserId;
    if (uid == null || uid.isEmpty) return false;
    try {
      await Supabase.instance.client.from('professionals').upsert(
        <String, dynamic>{
          'id': uid,
          'specialty': specialty,
          'bio': bio,
          'status': 'pending',
          'is_verified': false,
          if (pricingType != null && pricingType.trim().isNotEmpty)
            'pricing_type': pricingType.trim(),
          if (priceFrom != null) 'price_from': priceFrom,
          if (proofPath != null && proofPath.trim().isNotEmpty)
            'proof_path': proofPath.trim(),
          if (selfiePath != null && selfiePath.trim().isNotEmpty)
            'selfie_path': selfiePath.trim(),
          if (workImages != null) 'work_images': workImages,
          if (zones != null) 'zones': zones,
          if (categoryId != null && categoryId.trim().isNotEmpty)
            'category_id': categoryId.trim(),
          if (serviceIds != null && serviceIds.isNotEmpty)
            'service_ids': serviceIds,
        },
        onConflict: 'id',
      ).timeout(const Duration(seconds: 10));
      return true;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProfileRepository.upsertOwnProfessionalPending',
      );
      return false;
    }
  }
}
