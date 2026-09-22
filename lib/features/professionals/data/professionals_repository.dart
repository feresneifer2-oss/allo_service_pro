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
      // Live listing mirrors the registration payload: the pro's submitted
      // experience, description (in BOTH languages) and pricing entry point
      // travel into the client feed instead of hardcoded defaults. A blank
      // description falls back to the generic verified-pro copy.
      final rawDescription = p.description?.trim() ?? '';
      final aboutFallback =
          'Professionnel vérifié par Allo Service (identifiant ${p.proCode ?? p.id}).';
      final aboutArFallback =
          'محترف موثّق من Allo Service (المعرّف ${p.proCode ?? p.id}).';
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
        // Quote mode is preserved verbatim: a pro who registered with
        // pricingType 'quote' carries priceFrom == null, and the client UI
        // branches on pricingType FIRST ('Sur devis' badge) so the `?? 50`
        // numeric fallback below never renders for quote pros — it only
        // satisfies the non-nullable model field.
        pricingType: p.pricingType ?? 'fixed',
        // Quote mode (CodeRabbit): priceFrom stays NULL/unset — no numeric
        // fallback (like 50) may ever be exposed for quote-based services.
        // The client UI branches on pricingType FIRST ('Sur devis' badge).
        priceFrom: p.pricingType == 'quote' ? null : (p.priceFrom ?? 50),
        experienceYears: p.experienceYears ?? 1,
        aboutFr: rawDescription.isNotEmpty ? rawDescription : aboutFallback,
        aboutAr: rawDescription.isNotEmpty ? rawDescription : aboutArFallback,
        // Submitted specialties (wizard step 2) publish into the client
        // model so the profile / feed list the EXACT services the pro
        // declared; the profession label is the fallback when the pro
        // picked none.
        servicesFr: p.specialtiesFr.isNotEmpty
            ? List<String>.from(p.specialtiesFr)
            : [p.professionFr],
        servicesAr: p.specialtiesAr.isNotEmpty
            ? List<String>.from(p.specialtiesAr)
            : [p.professionAr],
        // Work gallery: the photos the pro submitted in the wizard step 4
        // travel into the client-facing model, so the feed / profile tiles
        // render the REAL work instead of an empty placeholder list.
        workImages: List<String>.from(p.galleryPhotos),
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
