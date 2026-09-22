import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';

enum SearchResultType { category, service, professional }

class SearchResult {
  final SearchResultType type;
  final String titleFr;
  final String titleAr;
  final String? subtitleFr;
  final String? subtitleAr;
  final IconData? icon;
  final String? serviceId;
  final String? categoryId;
  final ProfessionalModel? professional;

  /// Price hint (TND) shown as a chip on service results when known.
  final int? priceFrom;

  const SearchResult({
    required this.type,
    required this.titleFr,
    required this.titleAr,
    this.subtitleFr,
    this.subtitleAr,
    this.icon,
    this.serviceId,
    this.categoryId,
    this.professional,
    this.priceFrom,
  });
}

/// Unified search across the full 99-service catalog (`AppServicesCatalog`),
/// the navigation categories and every live professional (mock + approved
/// registrations).
class SearchService {
  SearchService._();

  static List<SearchResult> search(String query) {
    if (query.trim().isEmpty) return [];

    final q = query.toLowerCase().trim();
    final results = <SearchResult>[];
    // Dedupe on (name, category): the same craft can legitimately exist in
    // two categories (e.g. "Demenagement" under Maison AND Transport) —
    // both contexts must surface. Only exact name+category twins collapse.
    final seenServiceKeys = <String>{};

    // ── Categories (legacy ids — they drive the home sheets navigation) ──
    for (final cat in ServicesCatalog.categories) {
      if (cat.fr.toLowerCase().contains(q) || cat.ar.contains(q)) {
        results.add(SearchResult(
          type: SearchResultType.category,
          titleFr: cat.fr,
          titleAr: cat.ar,
          icon: cat.icon,
          categoryId: cat.id,
        ));
      }
    }

    // ── Services: the full 99-item catalog ──
    final categoryNamesFr = {
      for (final c in AppServicesCatalog.categories) c.id: c.nameFr,
    };
    final categoryNamesAr = {
      for (final c in AppServicesCatalog.categories) c.id: c.nameAr,
    };
    for (final service in AppServicesCatalog.services) {
      if (service.nameFr.toLowerCase().contains(q) ||
          service.nameAr.contains(q)) {
        final key = '${service.nameFr.toLowerCase()}|${service.categoryId}';
        if (!seenServiceKeys.add(key)) continue;
        results.add(SearchResult(
          type: SearchResultType.service,
          titleFr: service.nameFr,
          titleAr: service.nameAr,
          subtitleFr: categoryNamesFr[service.categoryId],
          subtitleAr: categoryNamesAr[service.categoryId],
          icon: service.icon,
          serviceId: service.id,
          categoryId: service.categoryId,
        ));
      }
    }

    // ── Professionals: mock + approved live registrations ──
    for (final pro in ProfessionalsRepository.all) {
      if (pro.name.toLowerCase().contains(q) ||
          pro.professionFr.toLowerCase().contains(q) ||
          pro.professionAr.contains(q) ||
          pro.city.toLowerCase().contains(q)) {
        results.add(SearchResult(
          type: SearchResultType.professional,
          titleFr: pro.name,
          titleAr: pro.name,
          subtitleFr: pro.professionFr,
          subtitleAr: pro.professionAr,
          icon: Icons.handyman_rounded,
          professional: pro,
          priceFrom: pro.priceFrom,
        ));
      }
    }

    return results;
  }
}
