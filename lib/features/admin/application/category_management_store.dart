import 'package:flutter/material.dart';
import '../../../core/catalog/services_catalog.dart';

class CategoryManagementStore {
  CategoryManagementStore._();

  static final categories = ValueNotifier<List<CatalogCategory>>([
    ...ServicesCatalog.categories,
  ]);

  static void addCategory(CatalogCategory category) {
    final list = List<CatalogCategory>.from(categories.value);
    list.add(category);
    categories.value = list;
  }

  static void updateCategory(String id, CatalogCategory updatedCategory) {
    categories.value =
        categories.value.map((c) => c.id == id ? updatedCategory : c).toList();
  }

  static void deleteCategory(String id) {
    categories.value = categories.value.where((c) => c.id != id).toList();
  }

  static void addTypeToCategory(String categoryId, CatalogType type) {
    final category = categories.value.firstWhere((c) => c.id == categoryId);
    final updatedTypes = [...category.types, type];
    final updatedCategory = CatalogCategory(
      id: category.id,
      icon: category.icon,
      fr: category.fr,
      ar: category.ar,
      types: updatedTypes,
    );
    updateCategory(categoryId, updatedCategory);
  }

  static void removeTypeFromCategory(String categoryId, String typeId) {
    final category = categories.value.firstWhere((c) => c.id == categoryId);
    final updatedTypes = category.types.where((t) => t.id != typeId).toList();
    final updatedCategory = CatalogCategory(
      id: category.id,
      icon: category.icon,
      fr: category.fr,
      ar: category.ar,
      types: updatedTypes,
    );
    updateCategory(categoryId, updatedCategory);
  }

  static void updateTypeInCategory(
    String categoryId,
    String typeId,
    CatalogType updatedType,
  ) {
    final category = categories.value.firstWhere((c) => c.id == categoryId);
    final updatedTypes =
        category.types.map((t) => t.id == typeId ? updatedType : t).toList();
    final updatedCategory = CatalogCategory(
      id: category.id,
      icon: category.icon,
      fr: category.fr,
      ar: category.ar,
      types: updatedTypes,
    );
    updateCategory(categoryId, updatedCategory);
  }
}
