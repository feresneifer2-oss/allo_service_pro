import 'package:flutter/foundation.dart';

import '../../auth/application/user_store.dart';
import '../data/pro_availability_repository.dart';
import 'pro_profile_store.dart';

/// LIVE availability board — `pro_code` → "accepts new service requests".
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

  /// `pro_code` (the PUBLIC id the client feed renders) → isAvailable.
  ///
  /// ABSENCE MEANS "UNKNOWN", not "offline": a pro who never toggled has no
  /// row, so the feed keeps its own default instead of being flipped to
  /// unavailable by a value nobody ever set.
  static final onlineByProCode =
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
  static void applyRemoteAvailability(String? proCode, bool isAvailable) {
    final code = proCode?.trim() ?? '';
    if (code.isEmpty) return;
    final current = onlineByProCode.value;
    if (current[code] != isAvailable) {
      onlineByProCode.value = Map<String, bool>.unmodifiable(<String, bool>{
        ...current,
        code: isAvailable,
      });
    }
    _mirrorOwn(code, isAvailable);
  }

  /// Mirrors [isAvailable] onto the OWNER's dashboard when [code] is the
  /// signed-in professional's public id (no-op for everybody else's rows).
  ///
  /// Kept INSIDE the ingress so both directions (realtime push and boot
  /// hydration) share one rule; [ProProfileStore.applyRemoteAvailability]
  /// itself no-ops on an unchanged value, so the mirror never echoes and never
  /// loops back into a write.
  static void _mirrorOwn(String code, bool isAvailable) {
    final own = UserStore.user.value?.proCode?.trim() ?? '';
    if (own.isEmpty || own != code) return;
    ProProfileStore.applyRemoteAvailability(isAvailable);
  }

  /// Decodes a raw `pro_availability` row and merges it — the seam the
  /// Realtime gateway calls, so wire parsing stays in the repository.
  static void applyRemoteRow(Map<String, dynamic> row) {
    final parsed = ProAvailabilityRepository.fromRow(row);
    if (parsed == null) return;
    applyRemoteAvailability(parsed.proCode, parsed.isAvailable);
  }

  /// The board's answer for [proId], or `null` when this pro never toggled
  /// (unknown → the caller keeps its own default).
  static bool? remoteFlagFor(String? proId) {
    final code = proId?.trim() ?? '';
    if (code.isEmpty) return null;
    return onlineByProCode.value[code];
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
    onlineByProCode.value = Map<String, bool>.unmodifiable(board);
    // The signed-in professional's OWN row (possibly written from ANOTHER
    // device) wins over the value this device cached locally — this is what
    // makes the dashboard restore the persisted state on launch.
    final own = UserStore.user.value?.proCode?.trim() ?? '';
    final remote = own.isEmpty ? null : board[own];
    if (remote != null) _mirrorOwn(own, remote);
    return true;
  }

  /// Drops the whole board (sign-out): the map is scoped to the identity that
  /// was bound when it was fetched, so the next session re-hydrates it.
  static void reset() {
    onlineByProCode.value = const <String, bool>{};
  }

  /// Test seam — same effect as [reset], named for the debug-* convention used
  /// by the other stores ([OfflineQueue.debugReset]).
  @visibleForTesting
  static void debugReset() => reset();
}
