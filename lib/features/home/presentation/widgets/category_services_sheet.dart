import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import 'professionals_sheet.dart';

void showCategoryServicesSheet(
  BuildContext context,
  CatalogCategory category,
) {
  final title = tr(context, fr: category.fr, ar: category.ar);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, fr: "Choisissez un service", ar: "اختر خدمة"),
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ...category.types.map((t) {
                final label = tr(context, fr: t.fr, ar: t.ar);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () {
                            final navigator = Navigator.of(sheetContext);
                            navigator.pop();
                            showProfessionalsSheet(
                                navigator.context, t.fr, t.ar);
                          },
                          child: Text(tr(context, fr: "Voir", ar: "عرض")),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      );
    },
  );
}
