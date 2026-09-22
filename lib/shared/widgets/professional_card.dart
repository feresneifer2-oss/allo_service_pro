import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProfessionalCard extends StatelessWidget {
  const ProfessionalCard({
    super.key,
    this.name = "Ahmed Ben Ali",
    this.profession = "Electricien",
    this.rating = 4.9,
    this.location = "Ariana",
    this.verified = true,
    this.buttonText = "Voir",
    this.priceFrom,
    this.pricingType = 'fixed',
    this.onPressed,
  });

  final String name;
  final String profession;
  final double rating;
  final String location;
  final bool verified;
  final String buttonText;

  /// Starting price in TND — rendered as a gold-bordered price chip.
  final int? priceFrom;

  /// How the price is charged: 'hourly', 'fixed' or 'quote'. Only 'hourly'
  /// appends the per-hour unit (DT/h / د.ت/ساعة) to the badge.
  final String pricingType;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.blue600,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  profession,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Trust badge: identity card verified by the admin
                    // (بطاقة هويّة مفعلة / CIN Vérifié).
                    if (verified)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF057A55)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user_rounded,
                                size: 14, color: Color(0xFF057A55)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                tr(context,
                                    fr: 'CIN Vérifié', ar: 'بطاقة هويّة مفعلة'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF057A55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Gold rating badge (Uber-style ★ 4.9).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFFC107),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFB8860B)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              rating.toStringAsFixed(1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF8A6D00),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _InfoChip(
                      icon: Icons.location_on_rounded,
                      iconColor: AppColors.error,
                      text: location,
                    ),
                    if (pricingType == 'quote')
                      // Quote-based pros: NO numeric price is ever rendered
                      // or exposed — only the explicit "Sur devis" badge.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tr(context, fr: 'Sur devis', ar: 'حسب الطلب'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (priceFrom != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          // Localized price badge: "dès X DT" / FR,
                          // "ابتداءً من X د.ت" / AR — with the per-hour unit
                          // appended only for hourly pricing.
                          tr(
                            context,
                            fr: pricingType == 'hourly'
                                ? 'dès $priceFrom DT/h'
                                : 'dès $priceFrom DT',
                            ar: pricingType == 'hourly'
                                ? 'ابتداءً من $priceFrom د.ت/ساعة'
                                : 'ابتداءً من $priceFrom د.ت',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Flexible so the CTA shrinks on narrow screens instead of
          // pushing the content column into a RIGHT OVERFLOW.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: onPressed ?? () {},
                  child: Text(
                    buttonText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
        ),
      ],
    );
  }
}
