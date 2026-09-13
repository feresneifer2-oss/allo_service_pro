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
                  // "Moussa bihom" — recommended pros + a working
                  // "Voir tout" entry into the full filterable list.
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
                  // Governorate-aware recommendation: if a governorate is set in
                  // UserStore, prioritize and show only matching professionals.
                  ..._filteredPros(context).take(3).map((pro) {
                    final profession = tr(
                      context,
                      fr: pro.professionFr,
                      ar: pro.professionAr,
                    );

                    return ProfessionalCard(
                      name: pro.name,
                      profession: profession,
                      rating: pro.rating,
                      location: pro.city, // ✅ صححناها
                      verified: pro.verified,
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
              ),
            );
          },
        ),
      ),
    );
  }

  /// Returns the recommended pros. When the user has chosen a governorate,
  /// the matching pros are surfaced first; the rest of the catalog fills in
  /// the remaining slots so the user always sees up to 3 results.
  List<ProfessionalModel> _filteredPros(BuildContext context) {
    final isArabic = appLocale.value.languageCode == 'ar';
    final selectedGov = isArabic
        ? GovernorateFilterStore.governorateAr.value
        : GovernorateFilterStore.governorateFr.value;

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
