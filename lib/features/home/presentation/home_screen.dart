import 'package:flutter/material.dart';

import '../../../shared/app_locale.dart';
import '../../auth/application/user_store.dart';
import '../../professional/presentation/professional_profile_screen.dart';
import '../data/mock_professionals.dart';

import 'widgets/banner_card.dart';
import 'widgets/home_header.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/service_grid.dart';

import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/professional_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: UserStore.user,
          builder: (context, user, _) {
            final userName = user?.name.split(' ').first ?? UserStore.displayName;

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
                  ...recommendedProfessionals.map((pro) {
                    final profession = tr(
                      context,
                      fr: pro.professionFr,
                      ar: pro.professionAr,
                    );

                    return ProfessionalCard(
                      name: pro.name,
                      profession: profession,
                      rating: pro.rating,
                      location: pro.location,
                      servicesCount: pro.servicesCount,
                      verified: pro.verified,
                      buttonText: tr(context, fr: 'Voir', ar: 'عرض'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfessionalProfileScreen(
                              name: pro.name,
                              professionFr: pro.professionFr,
                              professionAr: pro.professionAr,
                              rating: pro.rating,
                              location: pro.location,
                              servicesCount: pro.servicesCount,
                              verified: pro.verified,
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