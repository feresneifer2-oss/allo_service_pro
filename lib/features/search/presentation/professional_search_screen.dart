import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/features/requests/presentation/create_request_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/initials_avatar.dart';
import 'package:allo_service_pro/shared/widgets/primary_action_button.dart';

class ProfessionalSearchScreen extends StatefulWidget {
  const ProfessionalSearchScreen({super.key});

  @override
  State<ProfessionalSearchScreen> createState() =>
      _ProfessionalSearchScreenState();
}

class _ProfessionalSearchScreenState extends State<ProfessionalSearchScreen> {
  String? _selectedGovernorate;
  String? _selectedCity;
  String _searchQuery = '';
  List<ProfessionalModel> _filteredProfessionals = [];

  List<ProfessionalModel> get _allProfessionals => allProfessionals;

  List<String> get _governorates {
    final isArabic = appLocale.value.languageCode == 'ar';
    return isArabic
        ? TunisianLocations.getGovernoratesAr()
        : TunisianLocations.getGovernoratesFr();
  }

  List<String> _getCities(String governorate) {
    final isArabic = appLocale.value.languageCode == 'ar';
    if (isArabic) {
      return TunisianLocations.getCitiesAr(governorate);
    } else {
      return TunisianLocations.getCitiesFr(governorate);
    }
  }

  /// Pure filter computation. Only call from user-event handlers wrapped in
  /// [setState] — never during build — to avoid rebuild loops and jank.
  void _applyFilters() {
    _filteredProfessionals = _allProfessionals.where((pro) {
      // Filter by governorate (city in the professional model)
      if (_selectedGovernorate != null) {
        // Check if professional's city is in the selected governorate
        final citiesInGov = _getCities(_selectedGovernorate!);

        // Check both Arabic and French city names
        bool cityInGov =
            citiesInGov.contains(pro.city) || citiesInGov.contains(pro.cityFr);

        // Governorate-wide professionals store the governorate name itself
        // as their city (e.g. cityFr: 'Ariana'), which is not one of the
        // delegate-city entries — accept it as a valid match.
        if (!cityInGov) {
          for (final location in TunisianLocations.locations) {
            final matchesSelection = location.governorateFr ==
                    _selectedGovernorate ||
                location.governorateAr == _selectedGovernorate;
            final storesGovernorateName = pro.city == location.governorateAr ||
                pro.cityFr == location.governorateFr;
            if (matchesSelection && storesGovernorateName) {
              cityInGov = true;
              break;
            }
          }
        }

        if (!cityInGov) {
          return false;
        }
      }

      // Filter by city
      if (_selectedCity != null) {
        if (pro.city != _selectedCity && pro.cityFr != _selectedCity) {
          return false;
        }
      }

      // Filter by search query (name or profession)
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = pro.name.toLowerCase().contains(query);
        final matchesProfessionFr =
            pro.professionFr.toLowerCase().contains(query);
        final matchesProfessionAr =
            pro.professionAr.toLowerCase().contains(query);
        if (!matchesName && !matchesProfessionFr && !matchesProfessionAr) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(
          tr(context, fr: 'Trouver un professionnel', ar: 'البحث عن حرفي'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        // RTL direction so the Arabic layout flows right-to-left.
        child: Directionality(
          textDirection: TextDirection.rtl,
          // Keyboard-safe layout: tapping outside dismisses the keyboard and
          // the whole content scrolls up while the keyboard is open.
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Search form ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search by name or profession
                        TextField(
                          onChanged: (value) => _searchQuery = value,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: tr(context,
                                fr: 'Rechercher par nom ou profession...',
                                ar: 'ابحث بالاسم أو المهنة...'),
                            hintStyle:
                                const TextStyle(color: AppColors.slate400),
                            prefixIcon: const Icon(Icons.search,
                                color: AppColors.primary),
                            filled: true,
                            fillColor: AppColors.slate800,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Governorate selection
                        Text(
                          tr(context, fr: 'Gouvernorat', ar: 'الولاية'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.slate800,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedGovernorate,
                              hint: Text(
                                tr(context,
                                    fr: 'Tous les gouvernorats',
                                    ar: 'جميع الولايات'),
                                style:
                                    const TextStyle(color: AppColors.slate400),
                              ),
                              isExpanded: true,
                              dropdownColor: AppColors.slate800,
                              items: _governorates.map((gov) {
                                return DropdownMenuItem<String>(
                                  value: gov,
                                  child: Text(gov,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedGovernorate = value;
                                  _selectedCity = null;
                                  // Re-run filters immediately so results stay in sync
                                  // with the selected governorate (same UX as before,
                                  // but without filtering inside build()).
                                  _applyFilters();
                                });
                              },
                            ),
                          ),
                        ),

                        // City selection (only when governorate is selected)
                        if (_selectedGovernorate != null) ...[
                          const SizedBox(height: 20),
                          Text(
                            tr(context, fr: 'Ville', ar: 'المدينة'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.slate800,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCity,
                                hint: Text(
                                  tr(context,
                                      fr: 'Toutes les villes',
                                      ar: 'جميع المدن'),
                                  style:
                                      const TextStyle(color: AppColors.slate400),
                                ),
                                isExpanded: true,
                                dropdownColor: AppColors.slate800,
                                items: _getCities(_selectedGovernorate!)
                                    .map((city) {
                                  return DropdownMenuItem<String>(
                                    value: city,
                                    child: Text(city,
                                        style: const TextStyle(
                                            color: Colors.white)),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCity = value;
                                    _applyFilters();
                                  });
                                },
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Search button
                        PrimaryActionButton(
                          label: tr(context, fr: 'Rechercher', ar: 'بحث'),
                          icon: Icons.search,
                          onPressed: _performSearch,
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          height: 56,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Results header (outside the scrollable list, never overlapped) ──
                  if (_selectedGovernorate != null &&
                      _filteredProfessionals.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, fr: 'Résultats', ar: 'النتائج'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_filteredProfessionals.length} ${tr(context, fr: 'professionnel(s) trouvé(s)', ar: 'حرفي/حرفيون تم العثور عليهم')}',
                            style: const TextStyle(
                              color: AppColors.slate400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Results section: scrolls together with the whole view ──
                  _buildResultsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Parent is an unbounded scroll view — use vertical padding instead of
    // Center so the hint keeps its breathing room.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: AppColors.textSecondary,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, fr: 'Sélectionnez un gouvernorat', ar: 'اختر ولاية'),
            style: const TextStyle(
              color: AppColors.slate400,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context,
                fr: 'Nous afficherons les professionnels disponibles dans votre zone',
                ar: 'سنعرض الحرفيين المتاحين في منطقتك'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Builds whatever belongs under the fixed search form: hint state,
  /// no-results state, or the lazily-built results list.
  Widget _buildResultsSection() {
    if (_selectedGovernorate == null) {
      return _buildEmptyState();
    }

    if (_filteredProfessionals.isEmpty) {
      return _buildNoResults();
    }

    // Lazy building + shrinkWrap: cards are constructed lazily while the
    // unified scroll view handles all scrolling (keyboard-safe layout).
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredProfessionals.length,
      itemBuilder: (context, index) {
        final professional = _filteredProfessionals[index];
        return _ProfessionalCard(
          professional: professional,
          onRequest: () => _showRequestDialog(professional),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textSecondary,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            tr(context,
                fr: 'Aucun professionnel trouvé',
                ar: 'لم يتم العثور على حرفيين'),
            style: const TextStyle(
              color: AppColors.slate400,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context,
                fr: 'Essayez de modifier vos critères de recherche',
                ar: 'حاول تعديل معايير البحث'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _performSearch() {
    // Filtering runs here (user action), never inside build().
    setState(_applyFilters);
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

class _ProfessionalCard extends StatelessWidget {
  final ProfessionalModel professional;
  final VoidCallback onRequest;

  const _ProfessionalCard({
    required this.professional,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final profession = tr(context,
        fr: professional.professionFr, ar: professional.professionAr);
    final city = professional.getCityName(appLocale.value.languageCode);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: professional.name,
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                textStyle: const TextStyle(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
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
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profession,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      professional.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // City + Availability row
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$city • ${professional.distanceKm.toStringAsFixed(1)} km',
                  style:
                      const TextStyle(color: AppColors.slate400, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!professional.availableNow)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tr(context, fr: 'Indisponible', ar: 'غير متاح'),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Request button - separate row
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: professional.availableNow ? onRequest : null,
              icon: const Icon(Icons.send, size: 16),
              label: Text(
                tr(context, fr: 'Demander', ar: 'طلب'),
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: professional.availableNow
                    ? AppColors.secondary
                    : Colors.grey,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
