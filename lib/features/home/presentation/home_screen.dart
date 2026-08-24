import 'package:flutter/material.dart';

import '../../../shared/app_locale.dart';
import '../../auth/application/user_store.dart';
import '../../professionals/data/mock_professionals.dart';
import '../../professional/presentation/professional_profile_screen.dart';

import 'widgets/banner_card.dart';
import 'widgets/home_header.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/service_grid.dart';

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

            return SingleChildScrollView(
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
                  SectionTitle(
                    title: tr(
                      context,
                      fr: 'Professionnels recommandés',
                      ar: 'محترفون موصى بهم',
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...allProfessionals.take(3).map((pro) {
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
}
