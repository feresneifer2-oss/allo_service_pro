import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/booking/presentation/booking_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProfessionalProfileScreen extends StatelessWidget {
  const ProfessionalProfileScreen({
    super.key,
    required this.name,
    required this.professionFr,
    required this.professionAr,
    required this.rating,
    required this.location,
    required this.servicesCount,
    this.verified = true,
    this.experienceYears = 5,
    this.aboutFr = 'Professionnel expérimenté et fiable.',
    this.aboutAr = 'محترف ذو خبرة وموثوق.',
    this.services = const [],
  });

  final String name;
  final String professionFr;
  final String professionAr;
  final double rating;
  final String location;
  final int servicesCount;
  final bool verified;
  final int experienceYears;
  final String aboutFr;
  final String aboutAr;
  final List<String> services;

  @override
  Widget build(BuildContext context) {
    final profession = tr(context, fr: professionFr, ar: professionAr);
    final about = tr(context, fr: aboutFr, ar: aboutAr);
    final serviceItems = services.isEmpty
        ? [
            tr(context, fr: '$professionFr — standard', ar: '$professionAr — عادي'),
            tr(context, fr: 'Service premium', ar: 'خدمة مميزة'),
          ]
        : services;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Profil', ar: 'الملف')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _HeaderCard(
                    name: name,
                    profession: profession,
                    rating: rating,
                    location: location,
                    servicesCount: servicesCount,
                    verified: verified,
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    title: tr(context, fr: 'Services', ar: 'الخدمات'),
                    child: Column(
                      children: serviceItems
                          .map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(s)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context, fr: 'Expérience', ar: 'الخبرة'),
                    child: Text(
                      tr(
                        context,
                        fr: '$experienceYears ans',
                        ar: '$experienceYears سنوات',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context, fr: 'À propos', ar: 'نبذة'),
                    child: Text(
                      about,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          serviceTitle: professionFr,
                          professionalName: name,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    tr(context, fr: 'Demander ce service', ar: 'اطلب هذه الخدمة'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.profession,
    required this.rating,
    required this.location,
    required this.servicesCount,
    required this.verified,
  });

  final String name;
  final String profession;
  final double rating;
  final String location;
  final int servicesCount;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: const Color(0xFFEFF6FF),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (verified) ...const [
                SizedBox(width: 6),
                Icon(Icons.verified_rounded, color: AppColors.primary, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(profession, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Chip(Icons.star_rounded, AppColors.secondary, rating.toStringAsFixed(1)),
              _Chip(Icons.location_on_rounded, AppColors.error, location),
              _Chip(
                Icons.work_outline_rounded,
                AppColors.primary,
                tr(context, fr: '$servicesCount services', ar: '$servicesCount خدمة'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
