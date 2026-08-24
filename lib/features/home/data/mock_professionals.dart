class MockProfessional {
  final String name;
  final String professionFr;
  final String professionAr;
  final double rating;
  final String location;
  final int servicesCount;
  final bool verified;

  const MockProfessional({
    required this.name,
    required this.professionFr,
    required this.professionAr,
    required this.rating,
    required this.location,
    required this.servicesCount,
    this.verified = true,
  });
}

const recommendedProfessionals = [
  MockProfessional(
    name: 'Ahmed Ben Ali',
    professionFr: 'Électricien',
    professionAr: 'كهربائي',
    rating: 4.9,
    location: 'Ariana',
    servicesCount: 127,
  ),
  MockProfessional(
    name: 'Hatem Trabelsi',
    professionFr: 'Plombier',
    professionAr: 'سباك',
    rating: 4.8,
    location: 'Tunis',
    servicesCount: 98,
  ),
  MockProfessional(
    name: 'Sarra M.',
    professionFr: 'Nettoyage',
    professionAr: 'تنظيف',
    rating: 4.7,
    location: 'La Marsa',
    servicesCount: 64,
  ),
];
