import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
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
  });
}

class SearchService {
  SearchService._();

  static List<SearchResult> search(String query) {
    if (query.trim().isEmpty) return [];

    final q = query.toLowerCase().trim();
    final results = <SearchResult>[];

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

      for (final type in cat.types) {
        if (type.fr.toLowerCase().contains(q) || type.ar.contains(q)) {
          results.add(SearchResult(
            type: SearchResultType.service,
            titleFr: type.fr,
            titleAr: type.ar,
            subtitleFr: cat.fr,
            subtitleAr: cat.ar,
            icon: cat.icon,
            serviceId: type.id,
            categoryId: cat.id,
          ));
        }
      }
    }

    for (final pro in allProfessionals) {
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
          professional: pro,
        ));
      }
    }

    return results;
  }
}
