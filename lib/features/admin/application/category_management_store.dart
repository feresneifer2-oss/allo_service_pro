import 'package:flutter/material.dart';
import '../../../core/data/services_catalog.dart';

/// Admin CRUD over the service catalog. In-memory only (no persistence).
/// Phase 6-2c-1D: migrated to ServiceCategoryData + ServiceItem (flat).
class CategoryManagementStore {
  CategoryManagementStore._();

  /// Mutable list seeded from the unified catalog.
  static final categories = ValueNotifier<List<ServiceCategoryData>>(
    List<ServiceCategoryData>.from(AppServicesCatalog.categories),
  );

  /// Flat list of all services, seeded from the unified catalog.
  static final services = ValueNotifier<List<ServiceItem>>(
    List<ServiceItem>.from(AppServicesCatalog.services),
  );

  // ── Categories ────────────────────────────────────────────────────

  static void addCategory(ServiceCategoryData category) {
    categories.value = [...categories.value, category];
  }

  static void updateCategory(String id, ServiceCategoryData category) {
    categories.value = categories.value
        .map((c) => c.id == id ? category : c)
        .toList(growable: false);
  }

  static void deleteCategory(String id) {
    categories.value =
        categories.value.where((c) => c.id != id).toList(growable: false);
    services.value =
        services.value.where((s) => s.categoryId != id).toList(growable: false);
  }

  // ── Services (flat) ───────────────────────────────────────────────

  static void addServiceToCategory(ServiceItem item) {
    services.value = [...services.value, item];
  }

  static void removeServiceFromCategory(String serviceId) {
    services.value =
        services.value.where((s) => s.id != serviceId).toList(growable: false);
  }

  /// Convenience: return services for a category (replaces `category.types`).
  static List<ServiceItem> servicesInCategory(String categoryId) {
    return services.value
        .where((s) => s.categoryId == categoryId)
        .toList(growable: false);
  }
}
