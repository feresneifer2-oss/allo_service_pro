import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/professional/presentation/professional_profile_screen.dart';
import 'package:allo_service_pro/features/professionals/data/mock_professionals.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/professional_card.dart';

class ProfessionalsListScreen extends StatefulWidget {
  const ProfessionalsListScreen({
    super.key,
    required this.serviceId,
    required this.serviceTitleFr,
    required this.serviceTitleAr,
  });

  final String serviceId;
  final String serviceTitleFr;
  final String serviceTitleAr;

  @override
  State<ProfessionalsListScreen> createState() =>
      _ProfessionalsListScreenState();
}

class _ProfessionalsListScreenState extends State<ProfessionalsListScreen> {
  String? _city;
  double _minRating = 0;
  bool _verifiedOnly = false;
  bool _availableOnly = false;
  double _maxDistance = 20;

  List<ProfessionalModel> get _filtered {
    var list = professionalsForService(widget.serviceId);
    if (_city != null) list = list.where((p) => p.city == _city).toList();
    if (_minRating > 0) {
      list = list.where((p) => p.rating >= _minRating).toList();
    }
    if (_verifiedOnly) list = list.where((p) => p.verified).toList();
    if (_availableOnly) list = list.where((p) => p.availableNow).toList();
    list = list.where((p) => p.distanceKm <= _maxDistance).toList();
    return list;
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 8, 24, MediaQuery.of(ctx).padding.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, fr: 'Filtres', ar: 'فلاتر'),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  Text(tr(context, fr: 'Région', ar: 'المنطقة')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text(tr(context, fr: 'Toutes', ar: 'الكل')),
                        selected: _city == null,
                        onSelected: (_) => setSheet(() => _city = null),
                      ),
                      ...allCities.map(
                        (c) => FilterChip(
                          label: Text(c),
                          selected: _city == c,
                          onSelected: (_) => setSheet(() => _city = c),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                      '${tr(context, fr: 'Note min', ar: 'تقييم min')}: $_minRating'),
                  Slider(
                    value: _minRating,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    activeColor: AppColors.secondary,
                    onChanged: (v) => setSheet(() => _minRating = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context,
                        fr: 'Verified uniquement', ar: 'Verified فقط')),
                    value: _verifiedOnly,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setSheet(() => _verifiedOnly = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context,
                        fr: 'Disponible maintenant', ar: 'متاح الآن')),
                    value: _availableOnly,
                    activeThumbColor: AppColors.success,
                    onChanged: (v) => setSheet(() => _availableOnly = v),
                  ),
                  Text(
                      '${tr(context, fr: 'Distance max', ar: 'مسافة max')}: ${_maxDistance.toStringAsFixed(0)} km'),
                  Slider(
                    value: _maxDistance,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setSheet(() => _maxDistance = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      child: Text(tr(context, fr: 'Appliquer', ar: 'تطبيق')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        tr(context, fr: widget.serviceTitleFr, ar: widget.serviceTitleAr);
    final list = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: tr(context, fr: 'Filtres', ar: 'فلاتر'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr(context, fr: 'Trouver un professionnel', ar: 'البحث عن محترف'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (_city != null) ...[
              const SizedBox(height: 8),
              Text(
                tr(context, fr: '$title à $_city', ar: '$title في $_city'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 16),
            if (list.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    tr(context,
                        fr: 'Aucun professionnel trouvé', ar: 'لا يوجد محترف'),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...list.map((pro) {
                final profession =
                    tr(context, fr: pro.professionFr, ar: pro.professionAr);
                return ProfessionalCard(
                  name: pro.name,
                  profession: profession,
                  rating: pro.rating,
                  location: pro.city,
                  verified: pro.verified,
                  buttonText: tr(context, fr: 'Voir', ar: 'عرض'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfessionalProfileScreen(professionalId: pro.id),
                      ),
                    );
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}
