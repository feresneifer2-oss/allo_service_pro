import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import 'all_categories_sheet.dart';
import 'category_services_sheet.dart';

import 'package:allo_service_pro/shared/widgets/section_title.dart';
import 'package:allo_service_pro/shared/widgets/service_card.dart';

class ServiceGrid extends StatelessWidget {
  const ServiceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final top = <CatalogCategory>[
      ServicesCatalog.byId('home'),
      ServicesCatalog.byId('auto'),
      ServicesCatalog.byId('health'),
      ServicesCatalog.byId('beauty'),
      ServicesCatalog.byId('education'),
      ServicesCatalog.byId('tech'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                title: tr(context, fr: "Categories", ar: "التصنيفات"),
              ),
            ),
            TextButton(
              onPressed: () => showAllCategoriesSheet(context),
              child: Row(
                children: [
                  Text(tr(context, fr: "Voir tout", ar: "عرض الكل")),
                  const SizedBox(width: 6),
                  Icon(
                    isRtl
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 14,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 125,
          ),
          itemBuilder: (_, i) {
            final c = top[i];
            final title = tr(context, fr: c.fr, ar: c.ar);

            return ServiceCard(
              icon: c.icon,
              imagePath:
                  AppServicesCatalog.imageForLegacyCategory(c.id),
              title: title,
              onTap: () => showCategoryServicesSheet(context, c),
            );
          },
        ),
      ],
    );
  }
}
