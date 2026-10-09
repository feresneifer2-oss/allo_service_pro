import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_availability_store.dart';
import 'package:allo_service_pro/core/realtime/supabase_realtime_service.dart';

/// Maps Supabase Auth lifecycle events onto the local [UserStore] session.
///
/// ONE listener per process, bound once from `main()` after both
/// `Supabase.initialize()` and `UserStore.loadFromPrefs()`.
///
/// MAPPING CONTRACT (Supabase `User` → local `UserModel`):
///   • id     ← Supabase user UUID (stable remote identity);
///   • email  ← the Supabase e-mail, normalized to the registry-key form;
///   • name   ← `user_metadata.full_name` / `name`, else the SAME-identity
///              local name, else '' (NEVER the local part of the e-mail —
///              an e-mail fragment must not pollute the session or the
///              `profiles.full_name` column);
///   • phone  ← the Supabase phone when present, else '';
///   • role / proCode / verification state ← PRESERVED: they live in the
///     local credential registry (and are restored by [UserStore.set]'s
///     e-mail-merge when a record/session already exists for this e-mail).
///     A brand-new remote identity falls back to the SERVER's
///     `profiles.role`; only an identity unknown there starts roleless and
///     replays onboarding, exactly like a fresh local signup.
///
/// The local session remains the single source of truth for UI state — this
/// binding only keeps it COHERENT with the remote identity:
///   `signedIn` / `userUpdated` → bind or refresh the local session;
///   `signedOut` / `userDeleted` → clear it (only when one is actually
///   bound — a remote event must never wipe an unrelated local session such
///   as the admin dashboard flow, which is auth-independent).
void bindSupabaseAuthListener() {
  if (!SupabaseAuthService.isConfigured) {
    debugPrint('SupabaseAuthBindings: Supabase not initialized — '
        'auth-state listener not bound (local-only mode).');
    return;
  }
  _sub ??= Supabase.instance.client.auth.onAuthStateChange.listen(
    _handle,
    onError: (Object e) => debugPrint('SupabaseAuthBindings: stream error: $e'),
  );
}

StreamSubscription<AuthState>? _sub;

/// SERIALIZED EVENT PIPELINE (CodeRabbit): auth events can burst
/// (`initialSession` + `signedIn` + `userUpdated` within one boot; a
/// `signedOut` racing a reconnect-driven `signedIn`). Overlapping handlers
/// would interleave session binds/wipes and persistence writes — every event
/// is therefore processed through ONE strictly sequential chain. The stored
/// chain swallows errors so a failed event can never poison the next one.
Future<void> _eventChain = Future<void>.value();

Future<void> _handle(AuthState state) {
  debugPrint('SupabaseAuthBindings: event → ${state.event}');
  final run = _eventChain.then((_) => _processEvent(state));
  _eventChain = run.then<void>((_) {}, onError: (_) {});
  return run;
}

Future<void> _processEvent(AuthState state) async {
  switch (state.event) {
    case AuthChangeEvent.signedIn:
    case AuthChangeEvent.userUpdated:
    case AuthChangeEvent.initialSession:
      // AWAITED: the session bind (profiles upsert + UserStore.set
      // persistence cycle) settles before the NEXT queued auth event runs.
      // The event travels WITH the bind (Phase 2I): `state.session` is the JWT
      // that authenticated this transition — the profiles write must never be
      // signed by the anonymous key when the live session is already gone by
      // the time the request resolves its Authorization header.
      await _bindRemoteUser(state);
      // REALTIME (re)BIND: postgres_changes channels carry the identity's
      // RLS scope in their subscription, so they are (re)bound on EVERY
      // sign-in — a device switching accounts instantly switches to the new
      // identity's data feed. [SupabaseRealtimeService.start] is idempotent.
      SupabaseRealtimeService.start();
      // PERSISTED AVAILABILITY, RESTORED AT SESSION START: the pro's own
      // `pro_availability` row is the source of truth, so a force-closed app
      // (or a toggle made on another device) resolves to the REAL state instead
      // of a reset default. Fire-and-forget: a slow backend must never delay
      // the session bind — the board's ingress mirrors the value into
      // `ProProfileStore.isAvailable` when it lands, and the locally cached
      // flag already covered the very first frame.
      unawaited(ProAvailabilityStore.hydrateFromSupabase());
    case AuthChangeEvent.signedOut:
      // Only clear the LOCAL session when one is actually bound — a remote
      // sign-out for an anonymous local session (admin-only flows) must not
      // wipe it. The full store reset (tokens, chats, …) is driven by the
      // explicit `UserStore.signOutAndReset()` call sites, NOT here.
      if (UserStore.user.value != null) {
        // PERSISTED CLEANUP FIRST, RESULT HANDLED (CodeRabbit): the stale
        // session keys on disk (`is_logged_in`, `user_role`, profile
        // fields…) are wiped by the awaited `signOut()` BEFORE the
        // in-memory user is cleared — and its abort contract is honored:
        // when storage cleanup FAILS the in-memory session is KEPT (the
        // remote session is already revoked by the server event that fired
        // this handler), so the UI never advertises a signed-out state
        // whose disk half silently survived; the next sign-out attempt
        // re-runs the cleanup.
        final localCleanupOk = await UserStore.signOut();
        if (localCleanupOk) {
          UserStore.user.value = null;
        } else {
          debugPrint('SupabaseAuthBindings: local sign-out cleanup failed — '
              'in-memory session kept for a coherent retry.');
        }
      }
      // Stop ingesting: the channels were scoped to the signed-out identity.
      unawaited(SupabaseRealtimeService.stop());
      // The availability board was fetched under the signed-out identity's RLS
      // scope — dropped with the session, so the next account starts from its
      // own rows instead of inheriting the previous pro's flags.
      ProAvailabilityStore.reset();
    default:
      // tokenRefreshed / passwordRecovery / mfa events: no session mapping.
      break;
  }
}

Future<void> _bindRemoteUser(AuthState state) async {
  final identity = SupabaseAuthService.currentUser;
  if (identity == null) return;

  final supabaseUser = Supabase.instance.client.auth.currentUser;
  if (supabaseUser == null) return;
  final meta = supabaseUser.userMetadata;
  // SAFE METADATA CAST (CodeRabbit): user metadata is untrusted JSON — a
  // value typed as num/bool/list by the writer must never crash an `as
  // String?` cast. Everything is stringified defensively instead.
  Object? rawName;
  if (meta != null) {
    rawName = meta['full_name'] ?? meta['name'];
  }
  final metaName = rawName?.toString();
  // NAME RESOLUTION (Phase A / Fix 7): remote metadata wins when present;
  // else the SERVER-STORED `profiles.full_name` (written at registration —
  // a fresh device has NO same-identity local name to fall back on); else
  // the SAME-identity local name. The local part of the e-mail is NEVER
  // used (it polluted `profiles.full_name` with e-mail fragments like
  // "feres.neifer2"). `currentLocal` is read BEFORE this point because the
  // same-identity check below runs on it.
  final currentLocal = UserStore.user.value;
  final sameIdentity = currentLocal != null &&
      currentLocal.email?.trim().toLowerCase() ==
          identity.email.trim().toLowerCase();
  final localName = sameIdentity ? currentLocal.name.trim() : '';
  final resolvedMetaName =
      (metaName?.trim().isNotEmpty ?? false) ? metaName!.trim() : null;
  // The local fallback is only ever a REAL name (something a human typed),
  // never an e-mail fragment: identity bindings (`bindRemoteIdentity`) store
  // exactly that at registration, while this binding's own historical
  // e-mail-derived writes must not be recycled.
  final localFallback =
      (localName.isNotEmpty && !localName.contains('@')) ? localName : '';
  // SHARED PROFILE-ROW READ (Fix 7): `public.profiles` is SELECTED at most
  // ONCE per auth event — the `full_name` fallback below and the role
  // fallback at the end of this function share the SAME future.
  Future<Map<String, dynamic>?>? profileRowFuture;
  Future<Map<String, dynamic>?> readProfileRow() =>
      profileRowFuture ??= _readProfileRow(supabaseUser.id);
  // SERVER-STORED NAME (Fix 7): the registration-time `profiles.full_name`
  // answers whenever no metadata name exists — skipped entirely when
  // [resolvedMetaName] already won (no wasted SELECT), and `''` never
  // overwrites: `upsertProfile` omits a blank name (FIX 2B).
  String? serverName;
  if (resolvedMetaName == null) {
    final row = await readProfileRow();
    final server = row?['full_name']?.toString().trim() ?? '';
    serverName = server.isEmpty ? null : server;
  }
  final name = resolvedMetaName ?? serverName ?? localFallback;
  // IDENTITY-SCOPED PRESERVATION (CodeRabbit): the local session's phone /
  // role may only be carried onto the remote identity when they belong to
  // the SAME identity (normalized e-mail match). Preserving them across
  // identities — user B signing in while user A's local session was still
  // bound — would graft A's verified phone and role onto B's `profiles` row
  // and session. A non-matching local session is treated as ABSENT: the
  // remote values (or roleless defaults) apply, and onboarding decides the
  // role exactly as for a brand-new identity.
  final localRole = sameIdentity ? currentLocal.role : null;
  // PHONE RESOLUTION (CodeRabbit): a remote identity usually carries NO phone
  // (the Email-OTP flow never asks for one) while the local number is
  // verified in-app and belongs to the pro's dossier — but ONLY for the
  // matching identity. Preferring the remote value, then the SAME-identity
  // local number, stops every auth event from wiping it — without ever
  // leaking another account's number onto this profile.
  final remotePhone = supabaseUser.phone?.trim() ?? '';
  final localPhone = sameIdentity ? currentLocal.phone.trim() : '';
  final phone = remotePhone.isNotEmpty ? remotePhone : localPhone;

  // PROFILES TABLE SYNC (live backend): materialize / refresh this identity's
  // `profiles` row. The role written on FIRST insert comes from the current
  // local session (null for a brand-new identity → onboarding still decides).
  // AWAITED through the serialized event pipeline (CodeRabbit): overlapping
  // auth events must never interleave two session persistence cycles.
  // AUTHENTICATED BY THE EVENT'S SESSION (Phase 2I): `state.session` is the
  // session that authenticated THIS transition; it travels with the write so
  // the INSERT/UPDATE can never degrade to the anonymous key when the live
  // session is dropped (or not yet installed) before the request resolves its
  // Authorization header — Postgres saw `auth.uid()` NULL and answered 42501.
  try {
    await ProfileRepository.upsertProfile(
      id: supabaseUser.id,
      email: identity.email,
      name: name,
      phone: phone,
      role: localRole == UserRole.professional
          ? 'professional'
          : localRole == UserRole.client
              ? 'client'
              : null,
      session: state.session,
    );
  } catch (e) {
    // Failure-tolerant by design: an auth event must never crash the
    // pipeline; the profile sync retries on the next auth event.
    debugPrint('SupabaseAuthBindings: profiles upsert failed: $e');
  }

  // ROLE PRESERVATION (CodeRabbit): the local role is owned by the IN-APP
  // onboarding choice (setRole), never by the remote identity provider — and
  // ONLY for the matching identity (see above). AWAITED: the persisted
  // session cycle settles before the next queued auth event runs.
  await UserStore.set(
    name: name,
    // Same resolution as the profile upsert above: the remote phone wins when
    // it exists, otherwise the SAME-identity locally verified number is
    // preserved verbatim.
    phone: phone,
    email: identity.email,
    id: supabaseUser.id,
    // ROLE PRESERVATION (pending-approval routing): a KNOWN identity must
    // never be downgraded to `role = null` by this binding — inside the pro
    // shell that would read as "unknown role" and trip the fail-closed
    // verification gate. The credential record is keyed by THIS authenticated
    // e-mail, so its role is the identity's OWN (never a foreign graft).
    // SERVER FALLBACK: when NEITHER the same-identity session NOR the
    // credential registry knows a role (fresh device / cleared app data),
    // `public.profiles.role` — the onboarding role already written server-
    // side — answers instead; an identity unknown even there still resolves
    // to null and replays onboarding. An explicit same-identity session role
    // keeps priority over everything else.
    role: localRole ??
        UserStore.credentialRoleFor(identity.email) ??
        await _readServerRole(readProfileRow()),
  );
}

/// SERVER ROLE FALLBACK for [_bindRemoteUser]: `public.profiles.role` parsed
/// from the SHARED profile-row read — the SAME future the `full_name` name
/// fallback consumed (see `_readProfileRow`), so one auth event performs at
/// most ONE SELECT of `public.profiles`.
///
/// Consulted ONLY when neither the same-identity local session nor the
/// credential registry knows a role, so a returning client/pro routes to its
/// shell instead of replaying onboarding after clearing app data. `null` on
/// ANY failure (row absent, missing column, unrecognized value, offline) →
/// the caller keeps today's behavior. Never throws, so an offline device can
/// never break the serialized event chain.
Future<UserRole?> _readServerRole(
  Future<Map<String, dynamic>?> profileRow,
) async {
  try {
    final row = await profileRow;
    final raw = row?['role']?.toString().trim().toLowerCase();
    if (raw == 'client') return UserRole.client;
    if (raw == 'professional' || raw == 'professionnel') {
      return UserRole.professional;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// SAFE PROFILE-ROW READ shared by the name and role fallbacks inside
/// [_bindRemoteUser]: never throws — an absent uid or a simulated/offline
/// client degrades to `null` (same contract as [_readServerRole]; RLS
/// `profiles_select_own_row` scopes the read to `auth.uid()`), so the
/// serialized auth-event chain always settles.
Future<Map<String, dynamic>?> _readProfileRow(String uid) async {
  try {
    if (uid.trim().isEmpty) return null;
    return await ProfileRepository.fetchProfile(uid);
  } catch (e) {
    debugPrint('SupabaseAuthBindings: profile row read failed: $e');
    return null;
  }
}
