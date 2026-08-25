import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ProRegistrationScreen extends StatefulWidget {
  const ProRegistrationScreen({super.key});

  @override
  State<ProRegistrationScreen> createState() => _ProRegistrationScreenState();
}

class _ProRegistrationScreenState extends State<ProRegistrationScreen> {
  final _pageController = PageController();
  int _step = 0;

  final _nameController = TextEditingController(text: 'Ahmed Ben Ali');
  final _experienceController = TextEditingController(text: '8');
  final _descriptionController = TextEditingController();
  String _governorate = 'تونس';
  String? _city;

  @override
  void initState() {
    super.initState();
    // Set default governorate based on language
    final isArabic = appLocale.value.languageCode == 'ar';
    _governorate = isArabic ? 'تونس' : 'Tunis';
    _city = isArabic ? 'تونس المدينة' : 'Tunis Ville';
    _selectedCategory = ServicesCatalog.categories.first;
  }

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

  // Category & Specialties Selection
  CatalogCategory? _selectedCategory;
  final List<CatalogType> _selectedSpecialties = [];

  // Pricing
  String _pricingType = 'fixed'; // 'hourly', 'fixed', 'quote'
  int _priceFrom = 50;

  // Gallery Photos
  final List<String> _galleryPhotos = [];

  // Documents
  String _docType = 'diploma'; // 'diploma' | 'patent' | 'license' | 'card'
  bool _docUploaded = false;
  bool _selfieUploaded = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _experienceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      // ── Submit Pro Registration ──
      // Proof of work / profession photo is MANDATORY.
      if (!_docUploaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context,
                fr: 'Veuillez téléverser une preuve (photo métier).',
                ar: 'المرجو رفع إثبات المهنة (صورة).')),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final newPro = PendingProModel(
        id: 'pro_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text,
        phone: '+216 20 123 456', // Mock phone
        professionFr: _selectedCategory?.fr ?? 'Peintre',
        professionAr: _selectedCategory?.ar ?? 'دهّان',
        city: _city ?? _governorate,
        submittedAt:
            '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
        docImage: 'assets/images/doc_placeholder.png',
        status: 'pending',
      );

      // Assigns the unique PRO-XXXXX code and queues for admin review.
      final registered = AdminStore.registerPro(newPro);

      ProProfileStore.professionFr = newPro.professionFr;
      ProProfileStore.professionAr = newPro.professionAr;
      ProProfileStore.selectedSpecialties.value =
          List.from(_selectedSpecialties);
      ProProfileStore.pricingType.value = _pricingType;
      ProProfileStore.priceFrom.value = _priceFrom;
      ProProfileStore.workImages.value = List.from(_galleryPhotos);
      ProProfileStore.serviceZones.value = [_governorate];
      ProProfileStore.verificationStatus.value = ProVerificationStatus.pending;

      // Bind the professional identity to the local session, then land on
      // the verification gate (pending approval / WhatsApp inquiry).
      UserStore.set(
        name: registered.name,
        phone: registered.phone,
        role: UserRole.professional,
        proCode: registered.proCode,
        proofPath: registered.docImage,
        verificationStatus: ProVerification.pending,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              fr: 'Votre demande est en cours de vérification par l\'administrateur.',
              ar: 'طلبك قيد المراجعة من قبل المسؤول.',
            ),
          ),
          backgroundColor: AppColors.secondary,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerificationGateScreen()),
      );
    }
  }

  void _addMockPhoto() {
    setState(() {
      _galleryPhotos.add('photo_${_galleryPhotos.length + 1}');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context,
            fr: 'Photo de réalisation ajoutée !', ar: 'تمت إضافة صورة العمل!')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      tr(context, fr: 'Informations', ar: 'معلومات'),
      tr(context, fr: 'Métier', ar: 'المهنة'),
      tr(context, fr: 'Tarifs & Zone', ar: 'الأسعار والمنطقة'),
      tr(context, fr: 'Description', ar: 'الوصف المعرض'),
      tr(context, fr: 'Documents', ar: 'الوثائق'),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          tr(context, fr: 'Compte professionnel', ar: 'حساب مهني'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          // Custom beautiful progress bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tr(context,
                          fr: 'Étape ${_step + 1} sur 5',
                          ar: 'الخطوة ${_step + 1} من 5'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                    Text(
                      steps[_step],
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(steps.length, (i) {
                    final active = i <= _step;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i < steps.length - 1 ? 6 : 0),
                        height: 6,
                        decoration: BoxDecoration(
                          color:
                              active ? AppColors.primary : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Step 1: Info Personnelles
                _Step(
                  title: tr(context,
                      fr: 'Informations personnelles', ar: 'معلومات شخصية'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, fr: 'Nom complet', ar: 'الاسم الكامل'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: tr(context,
                              fr: 'Ex: Ahmed Ben Ali', ar: 'مثال: أحمد بن علي'),
                          prefixIcon: const Icon(Icons.person_outline_rounded,
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),

                // Step 2: Profession & Spécialités
                _Step(
                  title: tr(context,
                      fr: 'Profession & Spécialités', ar: 'المهنة والاختصاصات'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context,
                            fr: 'Quelle est votre catégorie de métier ?',
                            ar: 'ما هو مجال عملك الرئيسي؟'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<CatalogCategory>(
                        initialValue: _selectedCategory,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.category_outlined,
                              color: AppColors.primary),
                        ),
                        items: ServicesCatalog.categories.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(tr(context, fr: c.fr, ar: c.ar)),
                          );
                        }).toList(),
                        onChanged: (cat) {
                          setState(() {
                            _selectedCategory = cat;
                            _selectedSpecialties.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_selectedCategory != null) ...[
                        Text(
                          tr(context,
                              fr: 'Sélectionnez vos spécialités / services :',
                              ar: 'اختر اختصاصاتك / الخدمات التي تقدمها:'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedCategory!.types.map((type) {
                            final isSelected =
                                _selectedSpecialties.contains(type);
                            return FilterChip(
                              label:
                                  Text(tr(context, fr: type.fr, ar: type.ar)),
                              selected: isSelected,
                              selectedColor: AppColors.primarySurface,
                              checkmarkColor: AppColors.primary,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey.shade300,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedSpecialties.add(type);
                                  } else {
                                    _selectedSpecialties.remove(type);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Step 3: Tarification & Zone
                _Step(
                  title: tr(context,
                      fr: 'Tarifs, Expérience & Zone',
                      ar: 'الأسعار، الخبرة والمنطقة'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context,
                                      fr: 'Années d\'expérience',
                                      ar: 'سنوات الخبرة'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _experienceController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.star_border_rounded,
                                        color: AppColors.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context, fr: 'Gouvernorat', ar: 'الولاية'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _governorate,
                                  items: _governorates
                                      .map((g) => DropdownMenuItem(
                                          value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _governorate = v ?? _governorate;
                                      _city = null;
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr(context, fr: 'Ville', ar: 'المدينة'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _city,
                        hint: Text(
                          tr(context,
                              fr: 'Sélectionner une ville', ar: 'اختر مدينة'),
                        ),
                        items: _getCities(_governorate)
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() => _city = v),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 15),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        tr(context,
                            fr: 'Mode de tarification',
                            ar: 'طريقة احتساب الأسعار'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                  tr(context, fr: 'Tarif Horaire', ar: 'ساعة')),
                              selected: _pricingType == 'hourly',
                              onSelected: (val) {
                                if (val) {
                                  setState(() => _pricingType = 'hourly');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                  tr(context, fr: 'Prix Fixe', ar: 'مقطوع')),
                              selected: _pricingType == 'fixed',
                              onSelected: (val) {
                                if (val) {
                                  setState(() => _pricingType = 'fixed');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(tr(context,
                                  fr: 'Sur Devis', ar: 'حسب الطلب')),
                              selected: _pricingType == 'quote',
                              onSelected: (val) {
                                if (val) {
                                  setState(() => _pricingType = 'quote');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_pricingType != 'quote') ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tr(context,
                                  fr: 'Tarif minimum indicatif',
                                  ar: 'أقل سعر مقترح'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '$_priceFrom DT',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _priceFrom.toDouble(),
                          min: 10,
                          max: 300,
                          divisions: 29,
                          activeColor: AppColors.secondary,
                          inactiveColor: Colors.grey.shade200,
                          onChanged: (val) =>
                              setState(() => _priceFrom = val.toInt()),
                        ),
                      ],
                    ],
                  ),
                ),

                // Step 4: Description & Galerie Photos
                _Step(
                  title: tr(context,
                      fr: 'Description & Galerie', ar: 'الوصف ومعرض الأعمال'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context,
                            fr: 'Description de vos services',
                            ar: 'وصف خدماتك وخبراتك'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: tr(
                            context,
                            fr: 'Décrivez vos services, spécialités, matériel…',
                            ar: 'صف خدماتك، أسلوب عملك، الأدوات التي تستعملها...',
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        tr(context,
                            fr: 'Galerie de vos réalisations',
                            ar: 'صور لأعمالك السابقة'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          InkWell(
                            onTap: _addMockPhoto,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.primary, width: 1.5),
                              ),
                              child: const Icon(Icons.add_a_photo_outlined,
                                  color: AppColors.primary, size: 28),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 80,
                              child: _galleryPhotos.isEmpty
                                  ? Center(
                                      child: Text(
                                        tr(context,
                                            fr: 'Aucune photo ajoutée',
                                            ar: 'لم يتم إضافة صور بعد'),
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13),
                                      ),
                                    )
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _galleryPhotos.length,
                                      itemBuilder: (_, index) {
                                        return Container(
                                          width: 80,
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySurface,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Stack(
                                            children: [
                                              const Center(
                                                child: Icon(
                                                    Icons.image_outlined,
                                                    color: AppColors.primary),
                                              ),
                                              Positioned(
                                                top: 2,
                                                right: 2,
                                                child: GestureDetector(
                                                  onTap: () => setState(() =>
                                                      _galleryPhotos
                                                          .removeAt(index)),
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                        Icons.close,
                                                        color: Colors.white,
                                                        size: 14),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Step 5: Documents Professionnels
                _Step(
                  title: tr(context,
                      fr: 'Document professionnel', ar: 'الوثيقة المهنية'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.verified_user_rounded,
                                color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr(
                                  context,
                                  fr: 'Un document officiel prouve que vous exercez dans ce domaine. Il vous permet d\'obtenir le badge "Certifié" et d\'être mis en avant.',
                                  ar: 'وثيقة رسمية تثبت أنك محترف في هذا المجال. تمنحك شارة "موثّق" وترفع ظهورك للحرفاء.',
                                ),
                                style: const TextStyle(
                                    color: AppColors.primaryDark,
                                    fontSize: 12.5,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Document type selector
                      Text(
                        tr(context, fr: 'Type de document', ar: 'نوع الوثيقة'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DocTypeChip(
                            label: tr(context, fr: 'Diplôme', ar: 'شهادة'),
                            icon: Icons.school_rounded,
                            value: 'diploma',
                            selected: _docType == 'diploma',
                            onTap: () => setState(() => _docType = 'diploma'),
                          ),
                          _DocTypeChip(
                            label: tr(context, fr: 'Patente', ar: 'البراءة'),
                            icon: Icons.business_center_rounded,
                            value: 'patent',
                            selected: _docType == 'patent',
                            onTap: () => setState(() => _docType = 'patent'),
                          ),
                          _DocTypeChip(
                            label: tr(context, fr: 'Licence', ar: 'رخصة'),
                            icon: Icons.assignment_rounded,
                            value: 'license',
                            selected: _docType == 'license',
                            onTap: () => setState(() => _docType = 'license'),
                          ),
                          _DocTypeChip(
                            label:
                                tr(context, fr: 'Carte pro', ar: 'بطاقة مهنية'),
                            icon: Icons.badge_rounded,
                            value: 'card',
                            selected: _docType == 'card',
                            onTap: () => setState(() => _docType = 'card'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Upload document photo
                      Text(
                        tr(context,
                            fr: 'Photo du document', ar: 'صورة الوثيقة'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => _docUploaded = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 130,
                          decoration: BoxDecoration(
                            color: _docUploaded
                                ? AppColors.success.withValues(alpha: 0.08)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _docUploaded
                                  ? AppColors.success
                                  : AppColors.primary,
                              width: 1.5,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: _docUploaded
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded,
                                        color: AppColors.success, size: 40),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr(context,
                                          fr: 'Document téléchargé ✓',
                                          ar: 'تم رفع الوثيقة ✓'),
                                      style: const TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _docUploaded = false),
                                      child: Text(
                                        tr(context, fr: 'Changer', ar: 'تغيير'),
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_a_photo_rounded,
                                        color: AppColors.primary, size: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr(context,
                                          fr: 'Appuyer pour photographier',
                                          ar: 'اضغط لالتقاط صورة'),
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      tr(context,
                                          fr: 'JPG, PNG, PDF',
                                          ar: 'JPG، PNG، PDF'),
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Selfie with document
                      Text(
                        tr(context,
                            fr: 'Selfie avec le document',
                            ar: 'صورة سيلفي مع الوثيقة'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          context,
                          fr: 'Prenez une photo de vous tenant le document pour confirmer votre identité.',
                          ar: 'التقط صورة لك وأنت تمسك بالوثيقة لتأكيد هويتك.',
                        ),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => _selfieUploaded = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 130,
                          decoration: BoxDecoration(
                            color: _selfieUploaded
                                ? AppColors.success.withValues(alpha: 0.08)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _selfieUploaded
                                  ? AppColors.success
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: _selfieUploaded
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded,
                                        color: AppColors.success, size: 40),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr(context,
                                          fr: 'Selfie téléchargé ✓',
                                          ar: 'تم رفع الصورة ✓'),
                                      style: const TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                          () => _selfieUploaded = false),
                                      child: Text(
                                        tr(context, fr: 'Changer', ar: 'تغيير'),
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.face_rounded,
                                        color: Colors.grey, size: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr(context,
                                          fr: 'Selfie avec le document',
                                          ar: 'سيلفي مع الوثيقة'),
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      tr(context,
                                          fr: 'Recommandé pour une vérification rapide',
                                          ar: 'مُوصى به للتحقق السريع'),
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Warning note
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.secondarySurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: AppColors.secondary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr(
                                  context,
                                  fr: 'Vos documents sont traités en toute confidentialité. La vérification prend 24–48h.',
                                  ar: 'وثائقك تُعالَج بسرية تامة. المراجعة تستغرق 24 إلى 48 ساعة.',
                                ),
                                style: const TextStyle(
                                    color: AppColors.secondaryDark,
                                    fontSize: 12,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Bar navigation
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (_step > 0) ...[
                  OutlinedButton(
                    onPressed: () {
                      _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                      setState(() => _step--);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 24),
                      side: const BorderSide(color: Colors.grey),
                    ),
                    child: Text(
                      tr(context, fr: 'Retour', ar: 'رجوع'),
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      _step < 4
                          ? tr(context, fr: 'Suivant', ar: 'التالي')
                          : tr(context, fr: 'Soumettre', ar: 'إرسال'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _DocTypeChip extends StatelessWidget {
  const _DocTypeChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? Colors.white : AppColors.textSecondary,
                size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
