import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

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
  String professionFr,
  String professionAr,
) {
  final title = tr(context, fr: professionFr, ar: professionAr);

  final matches = ProfessionalsRepository.all
      .where((p) => p.professionFr.toLowerCase() == professionFr.toLowerCase())
      .toList();
  final pros = matches.isNotEmpty
      ? matches
      : ProfessionalsRepository.all.toList()
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
              ...pros.map((ProfessionalModel pro) {
                return ProfessionalCard(
                  name: pro.name,
                  profession:
                      tr(context, fr: pro.professionFr, ar: pro.professionAr),
                  rating: pro.rating,
                  location: pro.cityFr,
                  verified: pro.verified,
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
