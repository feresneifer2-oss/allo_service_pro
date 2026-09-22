import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/data/profile_repository.dart';
import 'package:allo_service_pro/core/realtime/supabase_realtime_service.dart';

/// Maps Supabase Auth lifecycle events onto the local [UserStore] session.
///
/// ONE listener per process, bound once from `main()` after both
/// `Supabase.initialize()` and `UserStore.loadFromPrefs()`.
///
/// MAPPING CONTRACT (Supabase `User` → local `UserModel`):
///   • id     ← Supabase user UUID (stable remote identity);
///   • email  ← the Supabase e-mail, normalized to the registry-key form;
///   • name   ← `user_metadata.full_name` / `name`, else the local part of
///              the e-mail;
///   • phone  ← the Supabase phone when present, else '';
///   • role / proCode / verification state ← PRESERVED: they live in the
///     local credential registry (and are restored by [UserStore.set]'s
///     e-mail-merge when a record/session already exists for this e-mail).
///     A brand-new remote identity starts roleless and replays onboarding,
///     exactly like a fresh local signup.
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
      await _bindRemoteUser();
      // REALTIME (re)BIND: postgres_changes channels carry the identity's
      // RLS scope in their subscription, so they are (re)bound on EVERY
      // sign-in — a device switching accounts instantly switches to the new
      // identity's data feed. [SupabaseRealtimeService.start] is idempotent.
      SupabaseRealtimeService.start();
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
    default:
      // tokenRefreshed / passwordRecovery / mfa events: no session mapping.
      break;
  }
}

Future<void> _bindRemoteUser() async {
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
  final name = (metaName?.trim().isNotEmpty ?? false)
      ? metaName!.trim()
      : identity.email.split('@').first;

  final currentLocal = UserStore.user.value;
  // IDENTITY-SCOPED PRESERVATION (CodeRabbit): the local session's phone /
  // role may only be carried onto the remote identity when they belong to
  // the SAME identity (normalized e-mail match). Preserving them across
  // identities — user B signing in while user A's local session was still
  // bound — would graft A's verified phone and role onto B's `profiles` row
  // and session. A non-matching local session is treated as ABSENT: the
  // remote values (or roleless defaults) apply, and onboarding decides the
  // role exactly as for a brand-new identity.
  final sameIdentity = currentLocal != null &&
      currentLocal.email?.trim().toLowerCase() ==
          identity.email.trim().toLowerCase();
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
    role: localRole,
  );
}
