import 'package:flutter/material.dart';

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
            const Text(
              "Choisissez un service",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ...subServices.map((name) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
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
                      width: 90,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => BookingScreen(
                                serviceTitle: '$serviceName - $name',
                                professionalName: 'À sélectionner',
                              ),
                            ),
                          );
                        },
                        style:
                            ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                        child: const Text("RÃ©server",
                            style: TextStyle(fontSize: 12)),
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
