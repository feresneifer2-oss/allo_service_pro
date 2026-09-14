import 'package:flutter/material.dart';

import '../../../core/data/tunisian_locations.dart';
import '../../../shared/app_locale.dart';
import '../../auth/application/user_store.dart';
import '../../professionals/data/professionals_repository.dart';
import '../../professionals/models/professional_model.dart';
import '../../professional/presentation/professional_profile_screen.dart';
import '../../professionals/presentation/professionals_list_screen.dart';

import 'widgets/banner_card.dart';
import 'widgets/home_header.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/service_grid.dart';

import '../application/governorate_filter_store.dart';

import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/professional_card.dart';
import '../../../core/theme/app_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: UserStore.user,
          builder: (context, user, _) {
            final userName =
                user?.name.split(' ').first ?? UserStore.displayName;
            // Default the page filter to the profile's saved governorate.
            GovernorateFilterStore.ensureSeeded();

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HomeHeader(userName: userName),
                  const SizedBox(height: 24),
                  const SearchBarWidget(),
                  const SizedBox(height: 24),
                  const BannerCard(),
                  const SizedBox(height: 30),
                  const ServiceGrid(),
                  const SizedBox(height: 30),
                  // "Moussa bihom" — reactive recommendations: rebuilds
                  // instantly when the governorate filter or locale changes.
                  const _RecommendedSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

}

/// "Moussa bihom" — recommended pros + a working "Voir tout" entry into
/// the full filterable list.
///
/// REACTIVE BY DESIGN: the section listens to BOTH the page governorate
/// filter ([GovernorateFilterStore]) and the active locale ([appLocale]),
/// so changing the wilaya or switching AR/FR rebuilds the cards instantly
/// — previously the filter values were read directly in build() with no
/// listener, so changes never refreshed the list.
class _RecommendedSection extends StatelessWidget {
  const _RecommendedSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: GovernorateFilterStore.governorateFr,
      builder: (context, govFr, _) {
        // set(ar, fr) always updates both notifiers simultaneously, so
        // listening to the FR one and reading both .values is safe.
        return ValueListenableBuilder<Locale>(
          valueListenable: appLocale,
          builder: (context, locale, _) {
            final isArabic = locale.languageCode == 'ar';
            final selectedGov =
                isArabic ? GovernorateFilterStore.governorateAr.value : govFr;
            final pros = _recommendedPros(selectedGov, isArabic);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: SectionTitle(
                        title: tr(
                          context,
                          fr: 'Professionnels recommandés',
                          ar: 'محترفون موصى بهم',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfessionalsListScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(
                        tr(context, fr: 'Voir tout', ar: 'عرض الكل'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...pros.take(3).map((pro) {
                  final profession = tr(
                    context,
                    fr: pro.professionFr,
                    ar: pro.professionAr,
                  );
                  // City label follows the active locale (AR name in
                  // Arabic, French name otherwise, with an AR fallback
                  // when the French name is missing).
                  final location = isArabic
                      ? pro.city
                      : (pro.cityFr.isNotEmpty ? pro.cityFr : pro.city);

                  return ProfessionalCard(
                    name: pro.name,
                    profession: profession,
                    rating: pro.rating,
                    location: location,
                    verified: pro.verified,
                    priceFrom: pro.priceFrom,
                    pricingType: pro.pricingType,
                    buttonText: tr(context, fr: 'Voir', ar: 'عرض'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfessionalProfileScreen(
                            professionalId: pro.id,
                          ),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }

  /// Returns the recommended pros. When a governorate is selected, the
  /// matching pros are surfaced first; the rest of the catalog fills in
  /// the remaining slots so the user always sees up to 3 results.
  List<ProfessionalModel> _recommendedPros(
    String? selectedGov,
    bool isArabic,
  ) {
    if (selectedGov == null || selectedGov.isEmpty) {
      // No governorate yet → show the global ranking (already top-rated).
      return List<ProfessionalModel>.from(ProfessionalsRepository.all)
        ..sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          if (byRating != 0) return byRating;
          return b.reviewCount.compareTo(a.reviewCount);
        });
    }

    bool inGov(ProfessionalModel p) {
      if (isArabic) {
        return TunisianLocations.getGovernorateArFromCityAr(p.city) ==
                selectedGov ||
            p.city == selectedGov;
      }
      return TunisianLocations.getGovernorateFrFromCityFr(p.cityFr) ==
              selectedGov ||
          p.cityFr == selectedGov;
    }

    final matched =
        ProfessionalsRepository.all.where(inGov).toList(growable: false);
    final others = ProfessionalsRepository.all.where((p) => !inGov(p)).toList();
    return [...matched, ...others];
  }
}
