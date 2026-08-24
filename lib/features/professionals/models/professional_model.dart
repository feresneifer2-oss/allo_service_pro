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
  final int priceFrom;
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
    this.priceFrom = 50,
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
  });

  String getCityName(String languageCode) {
    return languageCode == 'ar' ? city : (cityFr.isEmpty ? city : cityFr);
  }
}
