import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_availability_store.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for the client-facing professionals feed.
///
/// Merges the curated mock catalog with every LIVE registration that the
/// admin approved (PRO-XXXXX holders), so newly verified pros show up in
/// the home feed, search and booking sheets immediately — no Firebase,
/// straight from the local AdminStore registry (SharedPreferences-backed).
///
/// AVAILABILITY OVERLAY: each entry's `availableNow` reflects the persisted
/// `pro_availability` row of that professional (online = "accepts new
/// requests"), merged through [ProAvailabilityStore] — hydrated at boot and
/// kept fresh by the `realtime:public:pro_availability` channel. When a pro has
/// no row yet (never toggled) the entry's own default stands: the overlay only
/// ever applies a value somebody actually set.
class ProfessionalsRepository {
  ProfessionalsRepository._();

  /// Approved registrations converted to client-facing models.
  /// Deactivated pros are excluded entirely — clients never see them.
  static List<ProfessionalModel> get live {
    final approved = AdminStore.pendingPros.value
        .where((p) => p.status == 'approved' && !p.deactivated)
        .toList();

    return approved.map((p) {
      final code = p.proCode ?? p.id;
      // Phase 4G: use the first zone as city, no fake 'Tunis' fallback.
      final cityFr = (p.zones.isNotEmpty) ? p.zones.first : (p.city ?? '');
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
        id: code,
        name: p.name,
        professionFr: p.professionFr,
        professionAr: p.professionAr,
        categoryId: p.categoryId,
        serviceIds: p.serviceIds,
        // Phase 4D: real server-computed aggregates hydrated from
        // public.orders (0.0/0 = no ratings yet — never a fake 5.0).
        rating: p.rating,
        city: loc?.governorateAr ?? cityFr,
        cityFr: cityFr,
        // Phase 4G: real count from service_ids.
        servicesCount: p.serviceIds.length,
        verified: true,
        // PERSISTED availability (Supabase `pro_availability`): an approved pro
        // is listed according to their own flag, not unconditionally. `true` is
        // only the fallback for a pro who has no row yet — the value the
        // registration flow implies until the very first toggle.
        availableNow: ProAvailabilityStore.isOnline(code, fallback: true),
        // Quote mode is preserved verbatim: a pro who registered with
        // pricingType 'quote' carries priceFrom == null, and the client UI
        // branches on pricingType FIRST ('Sur devis' badge) so the `?? 50`
        // numeric fallback below never renders for quote pros — it only
        // satisfies the non-nullable model field.
        pricingType: p.pricingType ?? 'fixed',
        // Quote mode (CodeRabbit): priceFrom stays NULL/unset — no numeric
        // fallback (like 50) may ever be exposed for quote-based services.
        // The client UI branches on pricingType FIRST ('Sur devis' badge).
        // Phase 4G: no fake 50 DT — null when the pro hasn't set a price.
        priceFrom: p.pricingType == 'quote' ? null : p.priceFrom,
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
        // Phase 4D: real count hydrated alongside [rating] above.
        reviewCount: p.reviewCount,
        badges: p.badges,
        // Phase 3J: propagate the registered auth identity into the
        // client-facing model. The public `id` above stays the PRO-XXXXX
        // routing code — `authUid` travels alongside it, never replaces it.
        authUid: p.authUid,
      );
    }).toList();
  }

  /// Applies the live availability overlay to an ALREADY-CACHED list.
  ///
  /// Screens that store their results in state (the search screen does) would
  /// otherwise keep rendering the flags captured when the list was built: this
  /// is the single seam they call on a realtime change, so a toggle reaches a
  /// card that was materialized minutes earlier. Non-availability fields are
  /// preserved, and unknown pros are returned untouched.
  static List<ProfessionalModel> withLiveAvailability(
    Iterable<ProfessionalModel> pros,
  ) =>
      pros.map(_withRemoteAvailability).toList();

  /// The full client-facing feed: curated catalog first, live pros on top.
  ///
  /// Every curated entry passes through the availability overlay
  /// ([_withRemoteAvailability]) exactly like the live registrations, so one
  /// realtime toggle repaints the whole feed with a single rule.
  ///
  /// Phase 4: RELEASE builds show ONLY real registered pros — the curated
  /// mock catalog (Ahmed Ben Ali, Fatma B. …) stays for debug/test/demo.
  static List<ProfessionalModel> get all {
    final livePros = live;
    if (kReleaseMode) return livePros; // production: real pros only
    return [
      ...livePros,
      ...allProfessionals.map(_withRemoteAvailability),
    ];
  }

  /// Applies the PERSISTED availability of [p] when the backend knows one.
  ///
  /// `null` (unknown pro / no row) leaves the entry UNCHANGED: the source
  /// model's own default stands, so a failed or pending hydration can never
  /// flip the whole catalog to "unavailable".
  static ProfessionalModel _withRemoteAvailability(ProfessionalModel p) {
    final remote = ProAvailabilityStore.remoteFlagFor(p.id);
    return remote == null ? p : p.withAvailability(remote);
  }

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

    // 2) LIVE pros by exact service id (Phase 4B — real serviceIds from
    //    registration).
    for (final p in live) {
      if (p.serviceIds.contains(serviceId)) merged[p.id] = p;
    }

    // 3) FALLBACK: live-approved pros matched by profession label when
    //    their ids are still empty (legacy rows).
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
    // Phase 4H: no fallback — if no pro serves this service, return empty.
    // Showing random pros misleads the client (e.g. Feres appears in
    // Mécanicien).
    return list;
  }
}
