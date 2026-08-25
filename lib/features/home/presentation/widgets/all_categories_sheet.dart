import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import 'category_services_sheet.dart';

void showAllCategoriesSheet(BuildContext context) {
  final rootContext = context;
  final categories = ServicesCatalog.categories;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final isRtl = Directionality.of(sheetContext) == TextDirection.rtl;

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
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr(rootContext,
                          fr: "Toutes les categories", ar: "كل التصنيفات"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.slate800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              ...categories.map((c) {
                final title = tr(rootContext, fr: c.fr, ar: c.ar);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      final navigator = Navigator.of(sheetContext);
                      navigator.pop();
                      showCategoryServicesSheet(navigator.context, c);
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: AppColors.primarySurface,
                            shape: BoxShape.circle,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: AppServicesCatalog.imageForLegacyCategory(
                                      c.id) ==
                                  null
                              ? Icon(
                                  c.icon,
                                  color: AppColors.blue600,
                                  size: 22,
                                )
                              : Image.asset(
                                  AppServicesCatalog.imageForLegacyCategory(
                                      c.id)!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    c.icon,
                                    color: AppColors.blue600,
                                    size: 22,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.slate800,
                            ),
                          ),
                        ),
                        Icon(
                          isRtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
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
