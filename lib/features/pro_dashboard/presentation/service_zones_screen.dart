import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ServiceZonesScreen extends StatefulWidget {
  const ServiceZonesScreen({super.key});

  @override
  State<ServiceZonesScreen> createState() => _ServiceZonesScreenState();
}

class _ServiceZonesScreenState extends State<ServiceZonesScreen> {
  final Set<String> _selectedGovernorates = {};
  final Map<String, Set<String>> _selectedCities = {};

  @override
  void initState() {
    super.initState();
    // Load existing zones
    _selectedGovernorates.addAll(ProProfileStore.serviceZones.value);
  }

  String getGovernorateName(TunisianLocation location) {
    final isArabic = appLocale.value.languageCode == 'ar';
    return isArabic ? location.governorateAr : location.governorateFr;
  }

  List<String> getCitiesNames(TunisianLocation location) {
    final isArabic = appLocale.value.languageCode == 'ar';
    return location.cities.map((city) => isArabic ? city.ar : city.fr).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(
          tr(context, fr: 'Zones de service', ar: 'مناطق الخدمة'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: _saveZones,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: TunisianLocations.locations.length,
        itemBuilder: (context, index) {
          final location = TunisianLocations.locations[index];
          final govName = getGovernorateName(location);
          final isSelected = _selectedGovernorates.contains(govName);
          final selectedCities = _selectedCities[govName] ?? {};

          return ExpansionTile(
            key: ValueKey(govName),
            initiallyExpanded: isSelected,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: AppColors.slate800,
            collapsedBackgroundColor: AppColors.slate800,
            leading: Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedGovernorates.add(govName);
                  } else {
                    _selectedGovernorates.remove(govName);
                    _selectedCities.remove(govName);
                  }
                });
              },
              activeColor: AppColors.secondary,
              checkColor: Colors.white,
            ),
            title: Text(
              govName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '${selectedCities.length} ${tr(context, fr: 'ville(s) sélectionnée(s)', ar: 'مدينة/مدن مختارة')}',
              style: const TextStyle(color: AppColors.slate400, fontSize: 12),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context,
                          fr: 'Sélectionner les villes', ar: 'اختر المدن'),
                      style: const TextStyle(
                        color: AppColors.slate400,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: location.cities.map((city) {
                        final cityName = appLocale.value.languageCode == 'ar'
                            ? city.ar
                            : city.fr;
                        final isCitySelected =
                            selectedCities.contains(cityName);
                        return FilterChip(
                          label: Text(
                            cityName,
                            style: TextStyle(
                              color: isCitySelected
                                  ? Colors.white
                                  : AppColors.slate400,
                              fontSize: 12,
                            ),
                          ),
                          selected: isCitySelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                selectedCities.add(cityName);
                                _selectedCities[govName] = selectedCities;
                                _selectedGovernorates.add(govName);
                              } else {
                                selectedCities.remove(cityName);
                                if (selectedCities.isEmpty) {
                                  _selectedGovernorates.remove(govName);
                                }
                              }
                            });
                          },
                          selectedColor: AppColors.secondary,
                          backgroundColor: AppColors.slate900,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isCitySelected
                                  ? AppColors.secondary
                                  : const Color(0xFF334155),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_selectedGovernorates.length} ${tr(context, fr: 'gouvernorat(s)', ar: 'معتمدية/معتمديات')}',
                style: const TextStyle(color: AppColors.slate400),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saveZones,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                  ),
                  child: Text(
                    tr(context, fr: 'Enregistrer', ar: 'حفظ'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveZones() {
    ProProfileStore.updateServiceZones(_selectedGovernorates.toList());
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(context, fr: 'Zones enregistrées', ar: 'تم حفظ المناطق'),
        ),
        backgroundColor: AppColors.secondary,
      ),
    );
  }
}
