import 'package:flutter/material.dart';

import '../../../shared/app_locale.dart';
import 'widgets/banner_card.dart';
import 'widgets/home_header.dart';
import 'widgets/professional_card.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/section_title.dart';
import 'widgets/service_grid.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HomeHeader(userName: "Feres"),
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
                  fr: "Professionnels recommandés",
                  ar: "محترفون موصى بهم",
                ),
              ),

              const SizedBox(height: 18),

              ProfessionalCard(
                name: "Ahmed Ben Ali",
                profession: tr(context, fr: "Électricien", ar: "كهربائي"),
                rating: 4.9,
                location: "Ariana",
                verified: true,
                buttonText: tr(context, fr: "Voir", ar: "عرض"),
              ),

              ProfessionalCard(
                name: "Hatem Trabelsi",
                profession: tr(context, fr: "Plombier", ar: "سباك"),
                rating: 4.8,
                location: "Tunis",
                verified: true,
                buttonText: tr(context, fr: "Voir", ar: "عرض"),
              ),

              ProfessionalCard(
                name: "Sarra M.",
                profession: tr(context, fr: "Nettoyage", ar: "تنظيف"),
                rating: 4.7,
                location: "La Marsa",
                verified: true,
                buttonText: tr(context, fr: "Voir", ar: "عرض"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}