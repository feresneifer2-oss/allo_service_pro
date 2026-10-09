class ProfessionalModel {
  final String id;
  final String name;
  final String professionFr;
  final String professionAr;
  final List<String> serviceIds;
  final double rating;
  final String city; // Arabic city name
  final String cityFr; // French city name
  final int servicesCount;
  final bool verified;
  final bool availableNow;
  final double distanceKm;
  final int? priceFrom;
  final String pricingType; // 'hourly', 'fixed', 'quote'
  final List<String> workImages;
  final double punctualityRate;
  final double acceptanceRate;
  final int responseTimeMin;
  final bool hasBrandedUniform;
  final int experienceYears;
  final String aboutFr;
  final String aboutAr;
  final List<String> servicesFr;
  final List<String> servicesAr;
  final int reviewCount;

  /// Admin-assigned badges ('CIN Vérifié', 'Recommandé', 'Top Pro', …),
  /// synced in real time from [AdminStore.pendingPros] via
  /// [ProfessionalsRepository].
  final List<String> badges;

  /// Supabase Auth UUID (`auth.users.id` / `profiles.id`) of the approved
  /// professional behind this catalog entry — the identity a server-backed
  /// `orders.pro_id` will eventually carry.
  ///
  /// Phase 3J (local-model propagation only): populated from
  /// `PendingProModel.authUid` for live registrations, `null` for the curated
  /// mock catalog (which has no auth identity). The public `id` / PRO-XXXXX
  /// routing identifier is UNCHANGED — this field is never displayed.
  final String? authUid;

  const ProfessionalModel({
    required this.id,
    required this.name,
    required this.professionFr,
    required this.professionAr,
    required this.serviceIds,
    required this.rating,
    required this.city,
    this.cityFr = '',
    required this.servicesCount,
    this.verified = true,
    this.availableNow = false,
    this.distanceKm = 5.0,
    this.priceFrom,
    this.pricingType = 'fixed',
    this.workImages = const [],
    this.punctualityRate = 0.95,
    this.acceptanceRate = 0.90,
    this.responseTimeMin = 30,
    this.hasBrandedUniform = false,
    required this.experienceYears,
    required this.aboutFr,
    required this.aboutAr,
    required this.servicesFr,
    required this.servicesAr,
    this.reviewCount = 24,
    this.badges = const [],
    this.authUid,
  });

  String getCityName(String languageCode) {
    return languageCode == 'ar' ? city : (cityFr.isEmpty ? city : cityFr);
  }

  /// Returns a copy carrying [value] as [availableNow], or `this` when nothing
  /// would change.
  ///
  /// Used by [ProfessionalsRepository] to overlay the LIVE availability board
  /// (`ProAvailabilityStore`) onto the curated / registered feed without
  /// mutating the source catalog — the immutable model stays a value object,
  /// and every non-availability field is carried over verbatim.
  ProfessionalModel withAvailability(bool value) {
    if (value == availableNow) return this;
    return ProfessionalModel(
      id: id,
      name: name,
      professionFr: professionFr,
      professionAr: professionAr,
      serviceIds: serviceIds,
      rating: rating,
      city: city,
      cityFr: cityFr,
      servicesCount: servicesCount,
      verified: verified,
      availableNow: value,
      distanceKm: distanceKm,
      priceFrom: priceFrom,
      pricingType: pricingType,
      workImages: workImages,
      punctualityRate: punctualityRate,
      acceptanceRate: acceptanceRate,
      responseTimeMin: responseTimeMin,
      hasBrandedUniform: hasBrandedUniform,
      experienceYears: experienceYears,
      aboutFr: aboutFr,
      aboutAr: aboutAr,
      servicesFr: servicesFr,
      servicesAr: servicesAr,
      reviewCount: reviewCount,
      badges: badges,
      // Phase 3J: availability overlay is a clone — the auth identity must
      // survive it, otherwise a realtime toggle would strip the UID.
      authUid: authUid,
    );
  }
}
