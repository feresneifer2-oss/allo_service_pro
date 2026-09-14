import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProProfileStore {
  ProProfileStore._();

  static final isAvailable = ValueNotifier<bool>(true);
  static final tokens = ValueNotifier<int>(150);
  static final completedServices = ValueNotifier<int>(127);
  static final rating = ValueNotifier<double>(4.9);
  static final verificationStatus = ValueNotifier<ProVerificationStatus>(
    ProVerificationStatus.approved,
  );

  static String? professionFr;
  static String? professionAr;
  static List<String> zones = ['Ariana', 'Tunis'];

  static final selectedSpecialties = ValueNotifier<List<CatalogType>>([]);
  static final pricingType =
      ValueNotifier<String>('fixed'); // 'hourly', 'fixed', 'quote'
  static final priceFrom = ValueNotifier<int>(50);
  static final workImages = ValueNotifier<List<String>>([]);

  static final punctualityRate = ValueNotifier<double>(0.98);
  static final acceptanceRate = ValueNotifier<double>(0.96);
  static final responseTimeMin = ValueNotifier<int>(15);
  static final hasBrandedUniform = ValueNotifier<bool>(true);

  // Service zones (governorates)
  static final serviceZones = ValueNotifier<List<String>>(['Ariana', 'Tunis']);

  /// True once the account has ACTUALLY consumed part of its supply (an order
  /// accepted on the trial plan spent real tokens). The ProShell lock uses
  /// this so a brand-new trial account never gets locked just because its
  /// balance was manually adjusted to 0 — only a trial that has been USED and
  /// ran dry is shown the "Tokens Épuisés" paywall.
  static final tokensConsumed = ValueNotifier<bool>(false);

  // Token management

  /// Unlimited mode: paid subscribers never spend tokens.
  static bool get hasUnlimitedTokens =>
      SubscriptionStore.isPaidSubscriber.value;

  // ─── Local persistence (SharedPreferences) ──────────────────────────
  static const String _kTokens = 'pro_tokens';
  static const String _kTokensConsumed = 'pro_tokens_consumed';

  /// Writes the token balance AND the consumption flag to SharedPreferences
  /// so the trial-lock state survives app restarts exactly like the balance.
  ///
  /// Failures are swallowed so gameplay mutations never break because
  /// storage happens to be unavailable.
  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTokens, tokens.value);
      await prefs.setBool(_kTokensConsumed, tokensConsumed.value);
    } catch (_) {
      // Storage unavailable (e.g. tests without platform binding): ignore.
    }
  }

  /// Restores the persisted token balance and consumption flag at app
  /// startup.
  ///
  /// Falls back to the default trial balance (150) when nothing is saved.
  /// The consumption flag is restored BEFORE the balance so any listener
  /// fired by the balance update already observes the final state.
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kTokens)) return;
    if (prefs.containsKey(_kTokensConsumed)) {
      tokensConsumed.value = prefs.getBool(_kTokensConsumed) ?? false;
    }
    tokens.value = prefs.getInt(_kTokens) ?? 150;
  }

  static bool deductTokens(int amount) {
    if (hasUnlimitedTokens) return true;
    if (tokens.value >= amount) {
      // Flag is flipped BEFORE the balance change so every listener woken
      // by the balance notification already sees the fresh consumed state.
      tokensConsumed.value = true; // real usage: depletion may lock later
      tokens.value -= amount;
      persistToPrefs();
      return true;
    }
    return false;
  }

  static void addTokens(int amount) {
    tokens.value += amount;
    persistToPrefs();
  }

  static void updateServiceZones(List<String> zones) {
    serviceZones.value = zones;
  }

  /// Restores the default trial profile state and clears the persisted
  /// token balance (used on logout). EVERY mutable field, notifier and
  /// cached property is reset so a previously logged-in professional can
  /// never leak data (tokens, pricing, photos, ratings, zones, badges…)
  /// into the next account on this device.
  static Future<void> reset() async {
    tokens.value = 150;
    isAvailable.value = true;
    completedServices.value = 127;
    rating.value = 4.9;
    verificationStatus.value = ProVerificationStatus.approved;
    selectedSpecialties.value = [];
    pricingType.value = 'fixed';
    priceFrom.value = 50;
    workImages.value = [];
    punctualityRate.value = 0.98;
    acceptanceRate.value = 0.96;
    responseTimeMin.value = 15;
    hasBrandedUniform.value = true;
    serviceZones.value = ['Ariana', 'Tunis'];
    zones = ['Ariana', 'Tunis'];
    professionFr = null;
    professionAr = null;
    tokensConsumed.value = false; // fresh trial: manual 0 never locks
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokens);
      await prefs.remove(_kTokensConsumed);
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

enum ProVerificationStatus {
  none,
  pending,
  approved,
  rejected,
}
