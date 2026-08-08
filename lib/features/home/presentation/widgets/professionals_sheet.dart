import 'dart:async';
import 'package:flutter/material.dart';

import 'package:allo_service_pro/features/booking/presentation/booking_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import 'professional_card.dart';

void showProfessionalsSheet(
  BuildContext context,
  String professionFr,
  String professionAr,
) {
  final title = tr(context, fr: professionFr, ar: professionAr);

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
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  fr: "Professionnels disponibles",
                  ar: "المحترفون المتوفرون",
                ),
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),

              ProfessionalCard(
                name: "Ahmed Ben Ali",
                profession: tr(context, fr: professionFr, ar: professionAr),
                rating: 4.9,
                location: "Ariana",
                verified: true,
                buttonText: tr(context, fr: "Réserver", ar: "احجز"),
                onPressed: () {
                  final nav = Navigator.of(context, rootNavigator: true);
                  nav.pop();
                  Future.microtask(() {
                    nav.push(
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          serviceTitle: professionFr,
                          professionalName: "Ahmed Ben Ali",
                        ),
                      ),
                    );
                  });
                },
              ),

              ProfessionalCard(
                name: "Hatem Trabelsi",
                profession: tr(context, fr: professionFr, ar: professionAr),
                rating: 4.8,
                location: "Tunis",
                verified: true,
                buttonText: tr(context, fr: "Réserver", ar: "احجز"),
                onPressed: () {
                  final nav = Navigator.of(context, rootNavigator: true);
                  nav.pop();
                  Future.microtask(() {
                    nav.push(
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          serviceTitle: professionFr,
                          professionalName: "Hatem Trabelsi",
                        ),
                      ),
                    );
                  });
                },
              ),
            ],
          );
        },
      );
    },
  );
}