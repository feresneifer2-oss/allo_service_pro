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

  // Token management

  /// Unlimited mode: paid subscribers never spend tokens.
  static bool get hasUnlimitedTokens =>
      SubscriptionStore.isPaidSubscriber.value;

  // ─── Local persistence (SharedPreferences) ──────────────────────────
  static const String _kTokens = 'pro_tokens';

  /// Writes the token balance to SharedPreferences.
  ///
  /// Failures are swallowed so gameplay mutations never break because
  /// storage happens to be unavailable.
  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTokens, tokens.value);
    } catch (_) {
      // Storage unavailable (e.g. tests without platform binding): ignore.
    }
  }

  /// Restores the persisted token balance at app startup.
  ///
  /// Falls back to the default trial balance (150) when nothing is saved.
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kTokens)) return;
    tokens.value = prefs.getInt(_kTokens) ?? 150;
  }

  static bool deductTokens(int amount) {
    if (hasUnlimitedTokens) return true;
    if (tokens.value >= amount) {
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
}

enum ProVerificationStatus {
  none,
  pending,
  approved,
  rejected,
}
