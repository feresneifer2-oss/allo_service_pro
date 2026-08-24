import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/features/requests/presentation/create_request_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProfessionalProfileScreen extends StatelessWidget {
  const ProfessionalProfileScreen({
    super.key,
    required this.professionalId,
  });

  final String professionalId;

  @override
  Widget build(BuildContext context) {
    final pro = professionalById(professionalId);
    if (pro == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
            child: Text(tr(context,
                fr: 'Professionnel introuvable',
                ar: 'لم يتم العثور على الحرفي'))),
      );
    }

    // Override values if it's the current user profile (pro_1)
    var finalPro = pro;
    if (professionalId == 'pro_1') {
      final currentUser = UserStore.user.value;
      finalPro = ProfessionalModel(
        id: pro.id,
        name: (currentUser != null && currentUser.name.trim().isNotEmpty)
            ? currentUser.name.trim()
            : pro.name,
        professionFr: ProProfileStore.professionFr ?? pro.professionFr,
        professionAr: ProProfileStore.professionAr ?? pro.professionAr,
        serviceIds: pro.serviceIds,
        rating: ProProfileStore.rating.value,
        city: ProProfileStore.serviceZones.value.isNotEmpty
            ? ProProfileStore.serviceZones.value.join(', ')
            : pro.city,
        servicesCount: ProProfileStore.completedServices.value,
        verified: ProProfileStore.verificationStatus.value ==
            ProVerificationStatus.approved,
        availableNow: ProProfileStore.isAvailable.value,
        distanceKm: pro.distanceKm,
        priceFrom: ProProfileStore.priceFrom.value,
        pricingType: ProProfileStore.pricingType.value,
        workImages: ProProfileStore.workImages.value.isNotEmpty
            ? ProProfileStore.workImages.value
            : pro.workImages,
        punctualityRate: ProProfileStore.punctualityRate.value,
        acceptanceRate: ProProfileStore.acceptanceRate.value,
        responseTimeMin: ProProfileStore.responseTimeMin.value,
        hasBrandedUniform: ProProfileStore.hasBrandedUniform.value,
        experienceYears: pro.experienceYears,
        aboutFr: pro.aboutFr,
        aboutAr: pro.aboutAr,
        servicesFr: ProProfileStore.selectedSpecialties.value.isNotEmpty
            ? ProProfileStore.selectedSpecialties.value
                .map((s) => s.fr)
                .toList()
            : pro.servicesFr,
        servicesAr: ProProfileStore.selectedSpecialties.value.isNotEmpty
            ? ProProfileStore.selectedSpecialties.value
                .map((s) => s.ar)
                .toList()
            : pro.servicesAr,
        reviewCount: pro.reviewCount,
      );
    }

    final profession =
        tr(context, fr: finalPro.professionFr, ar: finalPro.professionAr);
    final about = tr(context, fr: finalPro.aboutFr, ar: finalPro.aboutAr);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Profil', ar: 'الملف')),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _HeaderCard(
                    name: finalPro.name,
                    profession: profession,
                    rating: finalPro.rating,
                    location: finalPro.city,
                    servicesCount: finalPro.servicesCount,
                    verified: finalPro.verified,
                    pricingType: finalPro.pricingType,
                    priceFrom: finalPro.priceFrom,
                  ),
                  const SizedBox(height: 16),

                  // Badges & Distinctions
                  _Section(
                    title: tr(context,
                        fr: 'Distinctions & Badges',
                        ar: 'الأوسمة والتميز المهني'),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (finalPro.verified)
                          _BadgeTile(
                            icon: Icons.verified_rounded,
                            color: Colors.blue.shade700,
                            bgColor: Colors.blue.shade50,
                            label:
                                tr(context, fr: 'Certifié', ar: 'موثّق معتمد'),
                          ),
                        if (finalPro.servicesCount >= 100)
                          _BadgeTile(
                            icon: Icons.workspace_premium_rounded,
                            color: Colors.amber.shade800,
                            bgColor: Colors.amber.shade50,
                            label: tr(context,
                                fr: 'Top Professionnel',
                                ar: 'مهني مميز للغاية'),
                          ),
                        if (finalPro.rating >= 4.8 &&
                            finalPro.reviewCount >= 30)
                          _BadgeTile(
                            icon: Icons.thumb_up_rounded,
                            color: AppColors.secondary,
                            bgColor: AppColors.secondarySurface,
                            label: tr(context, fr: 'Recommandé', ar: 'موصى به'),
                          ),
                        if (finalPro.hasBrandedUniform)
                          _BadgeTile(
                            icon: Icons.checkroom_rounded,
                            color: const Color(0xFF057A55),
                            bgColor: const Color(0xFFECFDF5),
                            label: tr(context,
                                fr: 'Équipé (Uniforme officiel)',
                                ar: 'مرتدي الزي الرسمي'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Statistiques d'engagement
                  _Section(
                    title: tr(context,
                        fr: 'Statistiques d\'engagement',
                        ar: 'مؤشرات الالتزام والنشاط'),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatMetric(
                            icon: Icons.alarm_rounded,
                            color: AppColors.primary,
                            title: tr(context,
                                fr: 'Ponctualité', ar: 'الالتزام بالوقت'),
                            value:
                                '${(finalPro.punctualityRate * 100).toInt()}%',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatMetric(
                            icon: Icons.task_alt_rounded,
                            color: AppColors.secondary,
                            title: tr(context,
                                fr: 'Acceptation', ar: 'قبول الطلبات'),
                            value:
                                '${(finalPro.acceptanceRate * 100).toInt()}%',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatMetric(
                            icon: Icons.bolt_rounded,
                            color: AppColors.success,
                            title: tr(context,
                                fr: 'Rép. moyenne', ar: 'سرعة الرد'),
                            value: '${finalPro.responseTimeMin} min',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _Section(
                    title: tr(context,
                        fr: 'Services & Spécialités',
                        ar: 'الخدمات والاختصاصات'),
                    child: Column(
                      children: List.generate(finalPro.servicesFr.length, (i) {
                        final s = tr(context,
                            fr: finalPro.servicesFr[i],
                            ar: finalPro.servicesAr[i]);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: AppColors.secondary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(s,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600))),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context, fr: 'Expérience', ar: 'الخبرة'),
                    child: Text(
                      tr(context,
                          fr: '${finalPro.experienceYears} ans',
                          ar: '${finalPro.experienceYears} سنوات'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context, fr: 'À propos', ar: 'نبذة'),
                    child: Text(about,
                        style: const TextStyle(
                            color: AppColors.textSecondary, height: 1.5)),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context,
                        fr: 'Galerie de réalisations', ar: 'معرض الأعمال'),
                    child: finalPro.workImages.isEmpty
                        ? Text(
                            tr(context,
                                fr: 'Aucune réalisation publiée.',
                                ar: 'لا توجد أعمال منشورة.'),
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          )
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: finalPro.workImages.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                            itemBuilder: (_, index) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(
                                        color: AppColors.primarySurface,
                                        child: const Icon(
                                          Icons.image_outlined,
                                          color: AppColors.primary,
                                          size: 32,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          color: Colors.black45,
                                          child: Text(
                                            '${tr(context, fr: 'Projet', ar: 'مشروع')} ${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: tr(context, fr: 'Avis', ar: 'التقييمات'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ...List.generate(
                                5,
                                (_) => const Icon(Icons.star_rounded,
                                    color: AppColors.secondary, size: 22)),
                            const SizedBox(width: 8),
                            Text(
                              '${finalPro.rating} (${finalPro.reviewCount})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            context,
                            fr: 'Excellent travail, très professionnel !',
                            ar: 'شغل ممتاز، محترف جداً!',
                          ),
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
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
                        builder: (_) => CreateRequestScreen(
                          serviceTitleFr: finalPro.professionFr,
                          serviceTitleAr: finalPro.professionAr,
                          professionalId: finalPro.id,
                          professionalName: finalPro.name,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary),
                  child: Text(tr(context,
                      fr: 'Demander ce service', ar: 'اطلب هذه الخدمة')),
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
    required this.pricingType,
    required this.priceFrom,
  });

  final String name;
  final String profession;
  final double rating;
  final String location;
  final int servicesCount;
  final bool verified;
  final String pricingType;
  final int priceFrom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 12,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.primarySurface,
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              if (verified) ...const [
                SizedBox(width: 6),
                Icon(Icons.verified_rounded,
                    color: AppColors.primary, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(profession,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Chip(Icons.star_rounded, AppColors.secondary,
                  rating.toStringAsFixed(1)),
              _Chip(Icons.location_on_rounded, AppColors.error, location),
              _Chip(
                Icons.work_outline_rounded,
                AppColors.primary,
                tr(context,
                    fr: '$servicesCount services', ar: '$servicesCount خدمة'),
              ),
              _Chip(
                Icons.payments_outlined,
                AppColors.success,
                pricingType == 'quote'
                    ? tr(context, fr: 'Sur devis', ar: 'حسب الطلب')
                    : pricingType == 'hourly'
                        ? '$priceFrom DT / H'
                        : '$priceFrom DT',
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
        Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatMetric extends StatelessWidget {
  const _StatMetric({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
