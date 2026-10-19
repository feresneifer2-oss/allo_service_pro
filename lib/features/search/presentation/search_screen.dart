import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/services_catalog.dart';
import '../../../core/data/tunisian_locations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/app_locale.dart';
import '../../../shared/localization/app_localizations.dart';
import '../../home/presentation/widgets/category_services_sheet.dart';
import '../../pro_dashboard/application/pro_availability_store.dart';
import '../../professional/presentation/professional_profile_screen.dart';
import '../../professionals/data/professionals_repository.dart';
import '../../professionals/models/professional_model.dart';
import '../../professionals/presentation/professionals_list_screen.dart';
import '../../requests/presentation/create_request_screen.dart';
import '../application/search_service.dart';

/// Unified search screen — text + optional governorate/city refinement.
/// Replaces the two old search screens (nav-tab + professional browse).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Optional initial text (e.g., from Home search bar).
  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller;
  String _query = '';
  String? _selectedGovernorate;
  String? _selectedCity;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _query = widget.initialQuery ?? '';
    // REALTIME AVAILABILITY: results live in state; a persisted toggle on
    // `realtime:public:pro_availability` must repaint the "Indisponible"
    // badge + "Demander" CTA in ONE frame without a new search/remount.
    ProAvailabilityStore.onlineByProId.addListener(_onAvailabilityChanged);
  }

  @override
  void dispose() {
    ProAvailabilityStore.onlineByProId.removeListener(_onAvailabilityChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onAvailabilityChanged() {
    if (!mounted) return;
    // _filteredPros() re-reads ProfessionalsRepository.all (fresh availability
    // flags), so a plain rebuild reflects the new state.
    setState(() {});
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  /// Accent + case + diacritic insensitive normalization.
  /// "Béja" → "beja", "Gabès" → "gabes", "Médenine" → "medenine".
  String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll(RegExp(r'ç'), 'c')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
  }

  bool _matchesGovernorate(ProfessionalModel p, bool isAr) {
    if (_selectedGovernorate == null) return true;
    final gov = _selectedGovernorate!;
    final govNorm = _norm(gov);

    // 1) Direct match on the governorate name (post-Phase-4G `city` holds the
    //    Arabic governorate, `cityFr` the Latin one).
    if (_norm(p.city) == govNorm) return true;
    if (_norm(p.cityFr) == govNorm) return true;

    // 2) Delegate-city expansion (legacy parity): a pro in a delegate city
    //    (e.g. La Marsa) matches its governorate (Tunis).
    final cities = isAr
        ? TunisianLocations.getCitiesAr(gov)
        : TunisianLocations.getCitiesFr(gov);
    for (final c in cities) {
      if (_norm(p.city) == _norm(c)) return true;
      if (_norm(p.cityFr) == _norm(c)) return true;
    }

    // NOTE: ProfessionalModel has no `zones` field; city/cityFr already carry
    // the canonical governorate, so no zones loop is needed here.
    return false;
  }

  bool _matchesCity(ProfessionalModel p) {
    if (_selectedCity == null) return true;
    final c = _norm(_selectedCity!);
    return _norm(p.city) == c || _norm(p.cityFr) == c;
  }

  // ─── Part 2: logic ──────────────────────────────────────────────────

  List<ProfessionalModel> _filteredPros(bool isAr) {
    final base = ProfessionalsRepository.all;
    return base
        .where((p) => _matchesGovernorate(p, isAr) && _matchesCity(p))
        .where((p) {
      if (_query.trim().isEmpty) return true;
      final q = _norm(_query);
      return _norm(p.name).contains(q) ||
          _norm(p.professionFr).contains(q) ||
          _norm(p.professionAr).contains(q);
    }).toList();
  }

  List<SearchResult> _catalogResults() {
    if (_query.trim().isEmpty) return const [];
    return SearchService.search(_query)
        .where((r) =>
            r.type == SearchResultType.category ||
            r.type == SearchResultType.service)
        .toList();
  }

  Future<void> _openResult(SearchResult r) async {
    switch (r.type) {
      case SearchResultType.category:
        if (r.categoryId != null) {
          final cat = AppServicesCatalog.categoryById(r.categoryId!);
          if (cat != null) showCategoryServicesSheet(context, cat);
        }
        break;
      case SearchResultType.service:
        if (r.serviceId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfessionalsListScreen(serviceId: r.serviceId!),
            ),
          );
        }
        break;
      case SearchResultType.professional:
        if (r.professional != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ProfessionalProfileScreen(professionalId: r.professional!.id),
            ),
          );
        }
        break;
    }
  }

  // ─── Placeholder build (Part 2 will replace) ────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate900,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(tr(context, fr: 'Recherche', ar: 'البحث')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialQuery == null,
                style: const TextStyle(color: Colors.white),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: tr(context,
                      fr: 'Rechercher un professionnel...',
                      ar: 'ابحث عن محترف...'),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.slate800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _buildFilterRow(context),
            const SizedBox(height: 8),
            Expanded(
              child: _resultsList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    final isAr = AppLocalizations.isArabic(context);
    final governorates = isAr
        ? TunisianLocations.getGovernoratesAr()
        : TunisianLocations.getGovernoratesFr();
    final cities = _selectedGovernorate == null
        ? const <String>[]
        : (isAr
            ? TunisianLocations.getCitiesAr(_selectedGovernorate!)
            : TunisianLocations.getCitiesFr(_selectedGovernorate!));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.slate800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedGovernorate,
                  isExpanded: true,
                  dropdownColor: AppColors.slate800,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  hint: Text(
                    tr(context, fr: 'Tous les gouvernorats', ar: 'كل الولايات'),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  items: <DropdownMenuItem<String?>>[
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr(context,
                          fr: 'Tous les gouvernorats', ar: 'كل الولايات')),
                    ),
                    ...governorates.map(
                      (g) => DropdownMenuItem(value: g, child: Text(g)),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedGovernorate = v;
                    _selectedCity = null;
                  }),
                ),
              ),
            ),
          ),
          if (_selectedGovernorate != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedCity,
                    isExpanded: true,
                    dropdownColor: AppColors.slate800,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    hint: Text(
                      tr(context, fr: 'Toutes les villes', ar: 'كل المدن'),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      DropdownMenuItem(
                        value: null,
                        child: Text(tr(context,
                            fr: 'Toutes les villes', ar: 'كل المدن')),
                      ),
                      ...cities.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCity = v),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsList(BuildContext context) {
    final isAr = AppLocalizations.isArabic(context);
    final pros = _filteredPros(isAr);
    final catalog = _catalogResults();

    if (pros.isEmpty && catalog.isEmpty) {
      return _emptyState(context);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (catalog.isNotEmpty) ...[
          _sectionHeader(context,
              tr(context, fr: 'Catégories & Services', ar: 'الأقسام والخدمات')),
          for (final r in catalog) _catalogTile(context, r),
          const SizedBox(height: 16),
        ],
        if (pros.isNotEmpty) ...[
          _sectionHeader(
              context, tr(context, fr: 'Professionnels', ar: 'المحترفون')),
          for (final p in pros)
            _SearchProCard(
              professional: p,
              onRequest: () => _showRequestDialog(p),
              onOpenProfile: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfessionalProfileScreen(professionalId: p.id),
                  ),
                );
              },
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _catalogTile(BuildContext context, SearchResult r) {
    final isAr = AppLocalizations.isArabic(context);
    final title = isAr ? r.titleAr : r.titleFr;
    final subtitle = isAr ? (r.subtitleAr ?? '') : (r.subtitleFr ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        child: Icon(r.icon ?? Icons.category, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: () => unawaited(_openResult(r)),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              (_query.isEmpty && _selectedGovernorate == null)
                  ? tr(context,
                      fr: 'Tapez pour rechercher un professionnel',
                      ar: 'اكتب للبحث عن محترف')
                  : tr(context,
                      fr: 'Aucun résultat trouvé', ar: 'لا توجد نتائج'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  void _showRequestDialog(ProfessionalModel professional) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(
          tr(context, fr: 'Demander un service', ar: 'طلب خدمة'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '${tr(context, fr: 'Voulez-vous contacter', ar: 'هل تريد التواصل مع')} ${professional.name} ?',
          style: const TextStyle(color: AppColors.slate400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, fr: 'Annuler', ar: 'إلغاء')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRequestScreen(
                    serviceTitleFr: professional.professionFr,
                    serviceTitleAr: professional.professionAr,
                    professionalId: professional.id,
                    professionalName: professional.name,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
            ),
            child: Text(
              tr(context, fr: 'Continuer', ar: 'متابعة'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Availability-aware pro card for the unified search results.
/// Mirrors the legacy `_ProfessionalCard` contract: an "Indisponible" badge
/// when offline + a "Demander" CTA (disabled when offline). Tapping the card
/// body opens the pro profile; the CTA opens the request dialog.
class _SearchProCard extends StatelessWidget {
  const _SearchProCard({
    required this.professional,
    required this.onRequest,
    required this.onOpenProfile,
  });

  final ProfessionalModel professional;
  final VoidCallback onRequest;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final available = professional.availableNow;
    final trimmed = professional.name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProfile,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        professional.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.isArabic(context)
                            ? professional.professionAr
                            : professional.professionFr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate400,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.orange, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            professional.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.location_on_rounded,
                              size: 14, color: AppColors.slate400),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              AppLocalizations.isArabic(context)
                                  ? professional.city
                                  : professional.cityFr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.slate400, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!available) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr(context, fr: 'Indisponible', ar: 'غير متاح'),
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: available ? onRequest : null,
              icon: const Icon(Icons.send, size: 16),
              label: Text(tr(context, fr: 'Demander', ar: 'طلب')),
              style: ElevatedButton.styleFrom(
                backgroundColor: available ? AppColors.secondary : Colors.grey,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
