import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error_handler.dart';

/// Supabase gateway for the LIVE `pro_availability` table — the durable
/// "this craftsman accepts new requests" flag.
///
/// MAPPING CONTRACT (`pro_availability` columns ↔ [ProAvailabilityRow]):
///   pro_id (uuid pk)    ← Supabase `auth.users.id` of the professional, i.e.
///                         the SAME identity `orders.customer_id` /
///                         `messages.sender_id` carry, read through
///                         `SupabaseAuthService.currentUserId`;
///   pro_code (text)     ← the PUBLIC identifier the client feed renders
///                         (`ProfessionalModel.id` == `PRO-XXXXX`), NULL while
///                         the registration has no code yet;
///   is_available (bool) ← the flag behind the dashboard's green/red dot;
///   updated_at          ← wall-clock of the LAST toggle (observability only —
///                         reads are never TTL-gated, the row IS the truth).
///
/// FAILURE POLICY: identical to [OrdersRepository] / [ProfileRepository] —
/// every call is failure-tolerant (logged through [AppErrorHandler], never
/// thrown into the UI) and a no-op when Supabase is not initialized (tests /
/// offline demo builds), so the local store stays usable with no backend.
class ProAvailabilityRepository {
  ProAvailabilityRepository._();

  static const String _table = 'pro_availability';

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ID of the CURRENTLY authenticated Supabase user (null when the client is
  /// not initialized / not signed in — tests and local-only builds).
  static String? currentAuthUserId() {
    try {
      final id = Supabase.instance.client.auth.currentUser?.id;
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// ATOMIC upsert of the caller's OWN availability row
  /// (`ON CONFLICT (pro_id) DO UPDATE`).
  ///
  /// One statement, so two devices toggling the same account can never leave a
  /// half-written row, and a pro who signs in on a NEW device materializes
  /// their row on the first toggle. Idempotent: replaying the same value is a
  /// no-op for the client, which is what makes the offline queue's eventual
  /// replay safe.
  ///
  /// [proCode] is written as-is but NEVER as an empty string: the partial
  /// UNIQUE index on `pro_code` would make two un-coded pros collide on ''.
  ///
  /// Returns `true` when the backend durably owns the value, `false` when it
  /// does not (not configured / RLS / transport) — the caller then keeps the
  /// write for the next connectivity window.
  static Future<bool> upsertAvailability({
    required String proId,
    String? proCode,
    required bool isAvailable,
  }) async {
    if (!isConfigured) return false;
    final id = proId.trim();
    if (id.isEmpty) return false;

    final code = proCode?.trim() ?? '';
    try {
      await Supabase.instance.client.from(_table).upsert(
        <String, dynamic>{
          'pro_id': id,
          'pro_code': code.isEmpty ? null : code,
          'is_available': isAvailable,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'pro_id',
      );
      return true;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProAvailabilityRepository.upsertAvailability',
      );
      return false;
    }
  }

  /// SELECT of the whole availability board (RLS: every authenticated identity
  /// may read the `pro_code` + flag pair — see the migration's policy),
  /// decoded to `pro_code → isAvailable`.
  ///
  /// Returns `null` when no backend answered (unconfigured / failed read) —
  /// DELIBERATELY distinct from an EMPTY map, which is a valid authoritative
  /// answer ("no pro has ever toggled"). The caller must be able to tell
  /// "no authority" from "nobody is available", or a failed fetch would wipe a
  /// board that realtime already populated.
  static Future<Map<String, bool>?> fetchAvailability() async {
    if (!isConfigured) return null;
    try {
      final rows = await Supabase.instance.client.from(_table).select();
      final board = <String, bool>{};
      for (final row in (rows as List)) {
        final parsed = fromRow(row as Map<String, dynamic>);
        if (parsed == null) continue;
        board[parsed.proCode] = parsed.isAvailable;
      }
      return board;
    } catch (e, st) {
      AppErrorHandler.report(
        e,
        st,
        context: 'ProAvailabilityRepository.fetchAvailability',
      );
      return null;
    }
  }

  /// Tolerant row decode — the counterpart of `OrdersRepository.fromRow`.
  ///
  /// A row without a usable `pro_code` is NOT decodable (nobody in the client
  /// feed can be matched to it), so it yields null and is skipped instead of
  /// polluting the board with an unmatchable key.
  static ProAvailabilityRow? fromRow(Map<String, dynamic> row) {
    final rawCode = row['pro_code'];
    final code = rawCode is String ? rawCode.trim() : '';
    if (code.isEmpty) return null;

    final flag = readAvailabilityFlag(row['is_available']);
    if (flag == null) return null;

    final rawProId = row['pro_id'];
    return ProAvailabilityRow(
      proId: rawProId is String ? rawProId.trim() : '',
      proCode: code,
      isAvailable: flag,
    );
  }

  /// Wire decode of the boolean flag: Postgres delivers a `bool`, but a
  /// legacy/hand-written row may carry the numeric or textual form. Returns
  /// null when the value is not a recognizable flag (the row is then dropped).
  static bool? readAvailabilityFlag(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'true':
        case 't':
        case '1':
        case 'yes':
          return true;
        case 'false':
        case 'f':
        case '0':
        case 'no':
          return false;
      }
    }
    return null;
  }
}

/// One decoded `pro_availability` row.
///
/// Immutable value object: the repository answers with this instead of a raw
/// map, so no caller has to re-parse the wire format.
@immutable
class ProAvailabilityRow {
  const ProAvailabilityRow({
    required this.proId,
    required this.proCode,
    required this.isAvailable,
  });

  /// Supabase `auth.users.id` of the professional (RLS owner).
  final String proId;

  /// Public identifier shown in the client feed (`ProfessionalModel.id`).
  final String proCode;

  /// `true` when the professional accepts new service requests.
  final bool isAvailable;

  @override
  String toString() =>
      'ProAvailabilityRow($proCode → ${isAvailable ? 'available' : 'offline'})';
}
