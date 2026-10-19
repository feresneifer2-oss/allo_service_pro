import 'package:flutter/foundation.dart';

import '../../auth/application/supabase_auth_service.dart';
import '../../auth/application/user_store.dart';
import '../data/pro_availability_repository.dart';
import 'pro_profile_store.dart';

/// LIVE availability board — `pro_id` (auth uuid) → "accepts new service requests".
///
/// WHY a separate board and not just [ProProfileStore.isAvailable]:
///   • [ProProfileStore.isAvailable] is the SIGNED-IN PRO'S OWN choice (one
///     device, one account);
///   • the client feed lists OTHER craftsmen (`ProfessionalsRepository`), whose
///     `ProfessionalModel.availableNow` has to reflect THEIR persisted
///     `pro_availability` row — the same table, read through RLS.
///
/// WRITE PATH: the pro's device upserts its own row
/// ([ProProfileStore.setAvailability] → [ProAvailabilityRepository]) — this
/// board is READ-ONLY: it is fed by the boot/reconnect hydration and by the
/// `realtime:public:pro_availability` postgres_changes stream
/// ([SupabaseRealtimeService]), both funnelled through
/// [applyRemoteAvailability] so a value is never applied twice.
///
/// NO PRESENCE, NO CONNECTION HEURISTICS: availability is a DURABLE user
/// decision stored in Postgres — never inferred from sockets, app state or
/// [ConnectivityStore]. A device that closes the app stays "available" exactly
/// as long as its last toggle said so.
class ProAvailabilityStore {
  ProAvailabilityStore._();

  /// Phase 7-4: `pro_id` (the professional's auth.users uuid) → isAvailable.
  ///
  /// Renamed (Phase 7-4) because `pro_code` is NULL for pros whose
  /// registration has no public code yet — those rows were dropped by the old
  /// decode gate, the real flag was lost and every reader fell through to
  /// `fallback: true` (an OFFLINE pro rendered as available). The uuid exists
  /// for every live pro, so the key never misses.
  ///
  /// ABSENCE MEANS "UNKNOWN", not "offline": a pro who never toggled has no
  /// row, so the feed keeps its own default instead of being flipped to
  /// unavailable by a value nobody ever set.
  static final onlineByProId =
      ValueNotifier<Map<String, bool>>(const <String, bool>{});

  /// REALTIME / HYDRATION INGRESS — idempotent merge of ONE pro's flag.
  ///
  /// Typed as a notifier write so [ValueNotifier] itself suppresses a
  /// redundant notification when the value did not change: an event that
  /// carries the value already on screen costs zero rebuilds.
  ///
  /// When the delivered row IS the signed-in professional's own, the value is
  /// also mirrored onto [ProProfileStore.isAvailable] — the dashboard switch
  /// reacts to a toggle made on ANOTHER device exactly like the client board
  /// does, without waiting for a restart.
  static void applyRemoteAvailability(String? proId, bool isAvailable) {
    final id = proId?.trim() ?? '';
    if (id.isEmpty) return;
    final current = onlineByProId.value;
    if (current[id] != isAvailable) {
      onlineByProId.value = Map<String, bool>.unmodifiable(<String, bool>{
        ...current,
        id: isAvailable,
      });
    }
    _mirrorOwn(id, isAvailable);
  }

  /// The identity this device's own row is keyed by (`pro_id` / uuid).
  ///
  /// Primary source: the LIVE Supabase session — the exact uuid the dashboard
  /// upserts its row with. Fallback: the BOUND session id, which
  /// `SupabaseAuthBindings` sets FROM `supabaseUser.id` (so in a Supabase
  /// session both sources are the SAME uuid) and which is the only identity a
  /// local-only session has — such a local id never appears as a server
  /// `pro_id`, so the mirror simply never fires there.
  static String? get _ownProId {
    final uuid = SupabaseAuthService.currentUserId?.trim();
    if (uuid != null && uuid.isNotEmpty) return uuid;
    final bound = UserStore.user.value?.id.trim() ?? '';
    return bound.isEmpty ? null : bound;
  }

  /// Mirrors [isAvailable] onto the OWNER's dashboard when [proId] is the
  /// signed-in professional's uuid (no-op for everybody else's rows).
  ///
  /// Kept INSIDE the ingress so both directions (realtime push and boot
  /// hydration) share one rule; [ProProfileStore.applyRemoteAvailability]
  /// itself no-ops on an unchanged value, so the mirror never echoes and never
  /// loops back into a write.
  static void _mirrorOwn(String proId, bool isAvailable) {
    final own = _ownProId;
    if (own == null || own != proId) return;
    ProProfileStore.applyRemoteAvailability(isAvailable);
  }

  /// Decodes a raw `pro_availability` row and merges it — the seam the
  /// Realtime gateway calls, so wire parsing stays in the repository.
  static void applyRemoteRow(Map<String, dynamic> row) {
    final parsed = ProAvailabilityRepository.fromRow(row);
    if (parsed == null) return;
    applyRemoteAvailability(parsed.proId, parsed.isAvailable);
  }

  /// The board's answer for [proId], or `null` when this pro never toggled
  /// (unknown → the caller keeps its own default).
  static bool? remoteFlagFor(String? proId) {
    final id = proId?.trim() ?? '';
    if (id.isEmpty) return null;
    return onlineByProId.value[id];
  }

  /// [remoteFlagFor] with an explicit fallback — the feed's single read seam.
  static bool isOnline(String? proId, {required bool fallback}) =>
      remoteFlagFor(proId) ?? fallback;

  /// Boot / reconnect hydration: pulls the whole RLS-scoped board.
  ///
  /// Returns `true` when the backend answered (even with an empty board) and
  /// `false` when it did not — in which case the local board is LEFT ALONE,
  /// because a failed read carries no authority and must never erase what
  /// realtime already merged.
  static Future<bool> hydrateFromSupabase() async {
    final board = await ProAvailabilityRepository.fetchAvailability();
    if (board == null) return false;
    onlineByProId.value = Map<String, bool>.unmodifiable(board);
    // The signed-in professional's OWN row (possibly written from ANOTHER
    // device) wins over the value this device cached locally — this is what
    // makes the dashboard restore the persisted state on launch.
    final own = _ownProId;
    final remote = own == null ? null : board[own];
    if (own != null && remote != null) _mirrorOwn(own, remote);
    return true;
  }

  /// Drops the whole board (sign-out): the map is scoped to the identity that
  /// was bound when it was fetched, so the next session re-hydrates it.
  static void reset() {
    onlineByProId.value = const <String, bool>{};
  }

  /// Test seam — same effect as [reset], named for the debug-* convention used
  /// by the other stores ([OfflineQueue.debugReset]).
  @visibleForTesting
  static void debugReset() => reset();
}
