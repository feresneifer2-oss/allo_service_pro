import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/catalog/services_catalog.dart';

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
  static bool deductTokens(int amount) {
    if (tokens.value >= amount) {
      tokens.value -= amount;
      return true;
    }
    return false;
  }

  static void addTokens(int amount) {
    tokens.value += amount;
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
