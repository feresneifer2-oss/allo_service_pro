import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SubscriptionStatus { active, expired }

/// Monthly unlimited-plan subscription state for a craftsperson.
///
/// The 15 TND / 1-month unlimited plan is activated manually by the admin
/// after receiving the D17 payment receipt over WhatsApp.
class SubscriptionStore {
  SubscriptionStore._();

  /// Price of one month of unlimited access (TND).
  static const int priceTnd = 15;

  /// Length of one subscription cycle, in days.
  static const int durationDays = 30;

  /// Support WhatsApp number (international format, no '+').
  static const String whatsappNumber = '21624449959';

  // ─── Local persistence keys (SharedPreferences) ────────────────────
  static const String _kIsPaid = 'sub_isPaidSubscriber';
  static const String _kActivatedAtMs = 'sub_activatedAtMs';
  static const String _kExpiresAtMs = 'sub_expiresAtMs';
  static const String _kStatusIndex = 'sub_statusIndex';

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

  /// Called by the admin panel once the D17 payment is approved.
  ///
  /// Starts (or renews) a full [durationDays]-day cycle opening at [at]
  /// (defaults to now), flips the status back to active and enables
  /// unlimited mode ([isPaidSubscriber] = true).
  static void renew({DateTime? at}) {
    activatedAt.value = at ?? DateTime.now();
    status.value = SubscriptionStatus.active;
    isPaidSubscriber.value = true;
    persistToPrefs();
  }

  /// Marks the monthly plan as expired → dashboard gets paywalled.
  static void expire() {
    status.value = SubscriptionStatus.expired;
    persistToPrefs();
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
