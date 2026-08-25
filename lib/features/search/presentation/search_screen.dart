import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/professional/presentation/professional_profile_screen.dart';
import 'package:allo_service_pro/features/professionals/presentation/professionals_list_screen.dart';
import 'package:allo_service_pro/features/search/application/search_service.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/empty_state_widget.dart';

import '../../home/presentation/widgets/category_services_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<SearchResult> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() => _results = SearchService.search(q));
  }

  void _openResult(SearchResult r) {
    switch (r.type) {
      case SearchResultType.category:
        final cat = ServicesCatalog.byId(r.categoryId!);
        showCategoryServicesSheet(context, cat);
      case SearchResultType.service:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfessionalsListScreen(
              serviceId: r.serviceId!,
              serviceTitleFr: r.titleFr,
              serviceTitleAr: r.titleAr,
            ),
          ),
        );
      case SearchResultType.professional:
        final pro = r.professional!;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfessionalProfileScreen(professionalId: pro.id),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Recherche', ar: 'بحث')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    fr: 'plombier, peinture, mécanicien...',
                    ar: 'سبّاك، دهان، ميكانicien...',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.primary),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: EmptyStateWidget(
                        icon: Icons.search_off_rounded,
                        title: tr(
                          context,
                          fr: 'Recherchez un service ou un professionnel',
                          ar: 'ابحث عن خدمة أو محترف',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        final title = tr(context, fr: r.titleFr, ar: r.titleAr);
                        final subtitle = r.subtitleFr != null
                            ? tr(context, fr: r.subtitleFr!, ar: r.subtitleAr!)
                            : null;

                        IconData icon;
                        Color iconColor;
                        switch (r.type) {
                          case SearchResultType.category:
                            icon = r.icon ?? Icons.category_rounded;
                            iconColor = AppColors.primary;
                          case SearchResultType.service:
                            icon = r.icon ?? Icons.handyman_rounded;
                            iconColor = AppColors.secondary;
                          case SearchResultType.professional:
                            icon = Icons.person_rounded;
                            iconColor = AppColors.primary;
                        }

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: iconColor.withValues(alpha: .12),
                            child: Icon(icon, color: iconColor, size: 22),
                          ),
                          title: Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: subtitle != null ? Text(subtitle) : null,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openResult(r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
