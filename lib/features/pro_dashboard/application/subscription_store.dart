import 'package:flutter/material.dart';

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

  static final status =
      ValueNotifier<SubscriptionStatus>(SubscriptionStatus.active);

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
  /// (defaults to now) and flips the status back to active.
  static void renew({DateTime? at}) {
    activatedAt.value = at ?? DateTime.now();
    status.value = SubscriptionStatus.active;
  }

  /// Marks the monthly plan as expired → dashboard gets paywalled.
  static void expire() => status.value = SubscriptionStatus.expired;
}
