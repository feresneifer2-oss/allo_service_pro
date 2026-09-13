import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';

/// Single source of truth for the client-facing professionals feed.
///
/// Merges the curated mock catalog with every LIVE registration that the
/// admin approved (PRO-XXXXX holders), so newly verified pros show up in
/// the home feed, search and booking sheets immediately — no Firebase,
/// straight from the local AdminStore registry (SharedPreferences-backed).
class ProfessionalsRepository {
  ProfessionalsRepository._();

  /// Approved registrations converted to client-facing models.
  /// Deactivated pros are excluded entirely — clients never see them.
  static List<ProfessionalModel> get live {
    final approved = AdminStore.pendingPros.value
        .where((p) => p.status == 'approved' && !p.deactivated)
        .toList();

    return approved.map((p) {
      final cityFr = p.city ?? 'Tunis';
      final loc = TunisianLocations.getLocationByFr(cityFr);
      return ProfessionalModel(
        id: p.proCode ?? p.id,
        name: p.name,
        professionFr: p.professionFr,
        professionAr: p.professionAr,
        serviceIds: const [],
        rating: 5.0,
        city: loc?.governorateAr ?? cityFr,
        cityFr: cityFr,
        servicesCount: 0,
        verified: true,
        availableNow: true,
        priceFrom: 50,
        experienceYears: 1,
        aboutFr:
            'Professionnel vérifié par Allo Service (identifiant ${p.proCode ?? p.id}).',
        aboutAr: 'محترف موثّق من Allo Service (المعرّف ${p.proCode ?? p.id}).',
        servicesFr: [p.professionFr],
        servicesAr: [p.professionAr],
        reviewCount: 0,
        badges: p.badges,
      );
    }).toList();
  }

  /// The full client-facing feed: curated catalog first, live pros on top.
  static List<ProfessionalModel> get all => [...live, ...allProfessionals];

  static ProfessionalModel? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Pros serving a given service id. Live-approved registrations carry no
  /// catalog serviceIds (their craft IS the profession label), so the two
  /// candidate sets are MERGED and de-duplicated: catalog-matching suggested
  /// pros plus every live pro whose profession label matches the requested
  /// specialty — no valid active professional is ever omitted.
  static List<ProfessionalModel> forService(String serviceId) {
    final merged = <String, ProfessionalModel>{};

    // 1) Suggested (curated) pros matching the catalog service id exactly.
    for (final p in all) {
      if (p.serviceIds.contains(serviceId)) merged[p.id] = p;
    }

    // 2) Live-approved pros matched by profession label (their serviceIds
    //    list is intentionally empty — the label is their specialty).
    final item = AppServicesCatalog.byId(serviceId);
    if (item != null) {
      final fr = item.nameFr.toLowerCase();
      final ar = item.nameAr;
      for (final p in all) {
        if (merged.containsKey(p.id)) continue;
        if (p.professionFr.toLowerCase().contains(fr) ||
            p.professionAr.contains(ar)) {
          merged[p.id] = p;
        }
      }
    }

    final list = merged.values.toList();
    if (list.isEmpty && item == null) return all.take(6).toList();
    return list;
  }
}
