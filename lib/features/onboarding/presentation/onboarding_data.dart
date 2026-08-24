class OnboardingData {
  final String title;
  final String subtitle;
  final String image;

  const OnboardingData({
    required this.title,
    required this.subtitle,
    required this.image,
  });
}

const onboardingItems = [
  OnboardingData(
    title: 'Trouver un professionnel',
    subtitle: 'Trouvez rapidement des professionnels près de chez vous.',
    image: 'assets/images/logo.png',
  ),
  OnboardingData(
    title: 'Professionnels vérifiés',
    subtitle: 'Consultez les avis et choisissez le meilleur professionnel.',
    image: 'assets/images/logo.png',
  ),
  OnboardingData(
    title: 'Réservez facilement',
    subtitle: 'Réservez votre service en quelques secondes.',
    image: 'assets/images/logo.png',
  ),
];
