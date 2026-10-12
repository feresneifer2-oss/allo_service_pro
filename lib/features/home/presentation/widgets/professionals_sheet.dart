import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/features/booking/presentation/booking_screen.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/professional_card.dart';

/// Draggable sheet listing the available professionals for a profession.
/// Tapping "Réserver" opens the unified booking flow, which creates a real
/// request the pro can accept or decline from their dashboard.
void showProfessionalsSheet(
  BuildContext context,
  String serviceId,
) {
  // Resolve the sheet title: new catalog first (ServiceItem ids like
  // 'peintre'), then the legacy nav catalog (CatalogType ids like 'painter').
  final catalogItem = AppServicesCatalog.byId(serviceId);
  final title = catalogItem != null
      ? tr(context, fr: catalogItem.nameFr, ar: catalogItem.nameAr)
      : tr(context, fr: serviceId, ar: serviceId);

  // ID-first: pros whose registered serviceIds include this service.
  // forService already merges curated + live pros and falls back to
  // label matching for legacy rows — NO fallback to ALL here: an empty
  // list means nobody serves this service.
  final pros = ProfessionalsRepository.forService(serviceId);
  final sorted = List<ProfessionalModel>.from(pros)
    ..sort((a, b) => b.rating.compareTo(a.rating));

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  fr: "Professionnels disponibles",
                  ar: "المحترفون المتوفرون",
                ),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ...sorted.map((ProfessionalModel pro) {
                return ProfessionalCard(
                  name: pro.name,
                  profession:
                      tr(context, fr: pro.professionFr, ar: pro.professionAr),
                  rating: pro.rating,
                  location: tr(context, fr: pro.cityFr, ar: pro.city),
                  verified: pro.verified,
                  priceFrom: pro.priceFrom,
                  pricingType: pro.pricingType,
                  buttonText: tr(context, fr: "Reserver", ar: "احجز"),
                  onPressed: () {
                    final nav = Navigator.of(context, rootNavigator: true);
                    nav.pop();
                    Future.microtask(() {
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => BookingScreen(
                            serviceTitleFr: pro.professionFr,
                            serviceTitleAr: pro.professionAr,
                            professionalId: pro.id,
                            professionalName: pro.name,
                          ),
                        ),
                      );
                    });
                  },
                );
              }),
            ],
          );
        },
      );
    },
  );
}
