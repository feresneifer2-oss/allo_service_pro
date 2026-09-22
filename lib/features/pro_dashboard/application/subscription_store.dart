import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
// Cycle attribution needs the LIVE session account. This two-way import is
// deliberate and already the established pattern in this codebase (see
// user_store.dart <-> notification_store.dart): both sides are static-only
// classes whose cross-references only run inside method bodies, so there is no
// top-level initialisation-order hazard.
import '../../auth/application/user_store.dart';

enum SubscriptionStatus { active, expired }

/// Monthly unlimited-plan subscription state for a craftsperson.
///
/// The 15 TND / 1-month unlimited plan is activated manually by the admin
/// after receiving the D17 payment receipt over WhatsApp.
///
/// SCOPE — device-global, session-scoped:
/// This store mirrors the subscription of the professional who is CURRENTLY
/// logged in on this device. The plan itself is not held per account: the
/// persisted admin registry (keyed by PRO code) is authoritative, and
/// `AdminStore.syncSessionStoresForCurrentUser()` re-derives this state on
/// every login / auto-login restore — including the truthful 'expired' status,
/// which is computed from THAT pro's own paid stamp and never inherited from
/// whatever session ran on this device before.
///
/// CYCLE ATTRIBUTION: the one per-account datum this store does record is the
/// cycle OWNER ([_kCycleOwnerId]). Every cycle opened here is attributed to the
/// account that opened it ([renew] stamps the live session account), and
/// [markPaidPreservingCycle] refuses to reuse an existing cycle whose ownership
/// is NOT validated for the account asking - see its OWNER VALIDATION GUARD
/// docs. This is what stops a cycle left behind by a previous session (the
/// admin's own, or another pro) from being inherited by whoever logs in next.
class SubscriptionStore {
  SubscriptionStore._();

  /// Price of one month of unlimited access (TND).
  static const int priceTnd = 15;

  /// Length of one subscription cycle, in days.
  static const int durationDays = 30;

  /// Support WhatsApp number (international format, no '+').
  /// Single source of truth: [AppConstants.adminWhatsAppNumber].
  static const String whatsappNumber = AppConstants.adminWhatsAppNumber;

  // ─── Local persistence keys (SharedPreferences) ────────────────────
  static const String _kIsPaid = 'sub_isPaidSubscriber';
  static const String _kActivatedAtMs = 'sub_activatedAtMs';
  static const String _kExpiresAtMs = 'sub_expiresAtMs';
  static const String _kStatusIndex = 'sub_statusIndex';

  /// Owner (account id) the persisted cycle belongs to.
  ///
  /// The store itself is device-global (see the class docs), so this key is
  /// what stops a cycle left behind by a PREVIOUS session on this device from
  /// being adopted by the account logging in now.
  static const String _kCycleOwnerId = 'sub_cycleOwnerId';

  /// Account the in-memory cycle is attributed to (null = unknown/legacy).
  static String? _cycleOwnerId;

  /// Test hook: the account the current cycle is attributed to.
  @visibleForTesting
  static String? get debugCycleOwnerId => _cycleOwnerId;

  static final status =
      ValueNotifier<SubscriptionStatus>(SubscriptionStatus.active);

  /// True once a paid unlimited plan is activated by the admin.
  ///
  /// `false` = free-trial mode: every confirmed order costs tokens and a
  /// zero balance locks pro actions behind the paywall.
  static final isPaidSubscriber = ValueNotifier<bool>(false);

  /// Free-trial mode: no active paid plan (token costs apply).
  static bool get isTrial => !isPaidSubscriber.value;

  /// Moment the current 30-day cycle was activated (null = never activated).
  static final activatedAt = ValueNotifier<DateTime?>(null);

  /// End of the current cycle, or null when the plan was never activated.
  static DateTime? get expiresAt =>
      activatedAt.value?.add(const Duration(days: durationDays));

  static bool get isExpired => status.value == SubscriptionStatus.expired;

  /// True once a cycle opened on [start] has fully elapsed at [now]
  /// (i.e. more than [durationDays] days have passed).
  static bool isCycleOver(DateTime start, DateTime now) =>
      now.isAfter(start.add(const Duration(days: durationDays)));

  /// True when the recorded cycle has run past its 30 days.
  static bool get cycleElapsed =>
      activatedAt.value != null &&
      isCycleOver(activatedAt.value!, DateTime.now());

  /// Account the CURRENT session runs as, when it is a professional account.
  ///
  /// Used to ATTRIBUTE every cycle this store opens. A cycle that records no
  /// owner is byte-for-byte indistinguishable from legacy data, so it would be
  /// adoptable by whichever account logs in next. Stamping the live session
  /// account instead leaves `null` only when NO account can legitimately be
  /// held responsible (signed out, or a non-professional session).
  static String? _liveSessionOwnerId() {
    final u = UserStore.user.value;
    return (u != null && u.isProfessional) ? u.id : null;
  }

  /// Called by the admin panel once the D17 payment is approved.
  ///
  /// Starts (or renews) a full [durationDays]-day cycle opening at [at]
  /// (defaults to now), flips the status back to active and enables
  /// unlimited mode ([isPaidSubscriber] = true).
  ///
  /// The opened cycle is attributed to [ownerId], defaulting to the live
  /// session account ([_liveSessionOwnerId]) — see
  /// [markPaidPreservingCycle] for the ownership guard that consumes it.
  static Future<void> renew({DateTime? at, String? ownerId}) async {
    activatedAt.value = at ?? DateTime.now();
    status.value = SubscriptionStatus.active;
    isPaidSubscriber.value = true;
    _cycleOwnerId = ownerId ?? _liveSessionOwnerId();
    await persistToPrefs();
  }

  /// Marks the monthly plan as expired → dashboard gets paywalled.
  static Future<void> expire() async {
    status.value = SubscriptionStatus.expired;
    await persistToPrefs();
  }

  /// Mirrors a paid state WITHOUT restarting the 30-day cycle.
  ///
  /// Used by the session-sync path: the existing activatedAt/expiration
  /// timestamps from the persisted session state are PRESERVED instead of
  /// being extended on every sync (renew() would stack +30 days each time
  /// a pro logged back in).
  ///
  /// • A previously stored cycle belonging to [ownerId] is kept as-is → the
  ///   status reflects the real remaining time (active, or expired once the
  ///   30 days elapsed).
  /// • No cycle recorded on this device yet (fresh admin grant), or a cycle
  ///   left behind by a DIFFERENT account → a fresh cycle is seeded once,
  ///   exactly like a first [renew].
  ///
  /// The store is device-global and carries no per-account key of its own, so
  /// silently adopting a foreign cycle would attribute another account's
  /// remaining time — or its paywall — to the account logging in now.
  /// OWNER VALIDATION GUARD. The store is device-global and carries no
  /// per-account key of its own, so a recorded cycle may belong to ANY account
  /// that ever ran on this device. It is reused only when ownership is
  /// established for [ownerId] (and a cycle exists at all):
  ///
  ///  1. `ownerId == cycleOwner` - this account re-applies its own cycle.
  ///  2. `ownerId == null && cycleOwner == null` - neither side names an
  ///     account, so no account switch can be involved (unattributed local
  ///     writers; also the first grant on a clean device).
  ///  3. `cycleOwner == null` + an identified account - an UNOWNED/legacy
  ///     cycle. Usable only when the caller passes [adoptUnownedLegacyCycle]
  ///     after validating ownership against the authoritative source (the
  ///     persisted admin registry). The default (false) REFUSES and seeds a
  ///     fresh cycle: an unowned cycle is never inherited blindly across an
  ///     account switch.
  ///
  /// Everything else - two different identified accounts, or an identified
  /// account meeting an unattributed cycle it never opted into - is foreign
  /// and gets a fresh cycle, exactly like a first [renew].
  ///
  /// The store is device-global and carries no per-account key of its own, so
  /// silently adopting a foreign cycle would attribute another account's
  /// remaining time — or its paywall — to the account logging in now.
  static Future<void> markPaidPreservingCycle({
    String? ownerId,
    bool adoptUnownedLegacyCycle = false,
  }) async {
    final start = activatedAt.value;
    final now = DateTime.now();

    assert(
      !adoptUnownedLegacyCycle || ownerId != null,
      'An unowned legacy cycle can only be adopted on behalf of an explicit '
      'account: pass the validated ownerId together with the opt-in.',
    );

    final cycleOwner = _cycleOwnerId;
    final bool ownedHere;
    if (ownerId == null) {
      // Unattributed writer: it may only re-apply an equally unattributed
      // cycle. A cycle attributed to an account is NOT its to inherit.
      ownedHere = cycleOwner == null;
    } else if (cycleOwner == ownerId) {
      ownedHere = true;
    } else {
      // Unowned legacy cycle + identified account: explicit opt-in only.
      ownedHere = cycleOwner == null && adoptUnownedLegacyCycle;
    }
    final reusable = start != null && ownedHere;
    final effectiveStart = reusable ? start : now;

    status.value = isCycleOver(effectiveStart, now)
        ? SubscriptionStatus.expired
        : SubscriptionStatus.active;
    isPaidSubscriber.value = true;
    activatedAt.value = effectiveStart;
    _cycleOwnerId = ownerId;
    await persistToPrefs();
  }

  /// Wipes the persisted subscription state and restores the trial
  /// defaults (used on logout).
  static Future<void> reset() async {
    status.value = SubscriptionStatus.active;
    isPaidSubscriber.value = false;
    activatedAt.value = null;
    _cycleOwnerId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kIsPaid);
      await prefs.remove(_kActivatedAtMs);
      await prefs.remove(_kExpiresAtMs);
      await prefs.remove(_kStatusIndex);
      await prefs.remove(_kCycleOwnerId);
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  // ─── Local persistence (SharedPreferences) ──────────────────────────

  /// Writes the current subscription state to SharedPreferences.
  ///
  /// Fire-and-forget by callers; failures are swallowed so state mutations
  /// never break because storage happens to be unavailable.
  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsPaid, isPaidSubscriber.value);

      final activated = activatedAt.value;
      if (activated == null) {
        await prefs.remove(_kActivatedAtMs);
      } else {
        await prefs.setInt(_kActivatedAtMs, activated.millisecondsSinceEpoch);
      }

      final expires = expiresAt;
      if (expires == null) {
        await prefs.remove(_kExpiresAtMs);
      } else {
        await prefs.setInt(_kExpiresAtMs, expires.millisecondsSinceEpoch);
      }

      await prefs.setInt(_kStatusIndex, status.value.index);

      final owner = _cycleOwnerId;
      if (owner == null) {
        await prefs.remove(_kCycleOwnerId);
      } else {
        await prefs.setString(_kCycleOwnerId, owner);
      }
    } catch (_) {
      // Storage unavailable (e.g. tests without platform binding): ignore.
    }
  }

  /// Restores the persisted subscription state at app startup.
  ///
  /// Falls back safely to the default trial configuration when no saved
  /// preferences exist yet (fresh install).
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kIsPaid)) return; // fresh install → trial defaults

    isPaidSubscriber.value = prefs.getBool(_kIsPaid) ?? false;
    _cycleOwnerId = prefs.getString(_kCycleOwnerId);

    final activatedMs = prefs.getInt(_kActivatedAtMs);
    activatedAt.value = activatedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(activatedMs);

    final statusIndex =
        prefs.getInt(_kStatusIndex) ?? SubscriptionStatus.active.index;
    status.value = SubscriptionStatus
        .values[statusIndex.clamp(0, SubscriptionStatus.values.length - 1)];
  }
}
