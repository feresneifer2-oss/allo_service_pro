import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

import 'package:allo_service_pro/shared/app_locale.dart';
import '../../../booking/presentation/booking_screen.dart';

void showSubServiceSheet(
  BuildContext context,
  String serviceName,
  List<String> subServices,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final bottomPadding = MediaQuery.of(context).padding.bottom;

      return SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomPadding),
          children: [
            Text(
              serviceName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, fr: "Choisissez un service", ar: "اختر خدمة"),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ...subServices.map((name) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => BookingScreen(
                                serviceTitleFr: '$serviceName — $name',
                                serviceTitleAr: '$serviceName — $name',
                              ),
                            ),
                          );
                        },
                        style:
                            ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text(
                          tr(context, fr: "Reserver", ar: "احجز"),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}
