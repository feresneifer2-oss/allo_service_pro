import 'package:flutter/material.dart';

class CatalogCategory {
  final String id;
  final IconData icon;
  final String fr;
  final String ar;
  final List<CatalogType> types;

  const CatalogCategory({
    required this.id,
    required this.icon,
    required this.fr,
    required this.ar,
    required this.types,
  });
}

class CatalogType {
  final String id;
  final String fr;
  final String ar;

  const CatalogType({
    required this.id,
    required this.fr,
    required this.ar,
  });
}

class ServicesCatalog {
  ServicesCatalog._();

  static const categories = <CatalogCategory>[
    CatalogCategory(
      id: 'home',
      icon: Icons.home_rounded,
      fr: 'Maison',
      ar: 'المنزل',
      types: [
        CatalogType(id: 'mason', fr: 'Macon', ar: 'عامل بناء'),
        CatalogType(id: 'painter', fr: 'Peintre', ar: 'دهان'),
        CatalogType(id: 'electrician', fr: 'Electricien', ar: 'كهربائي'),
        CatalogType(id: 'plumber', fr: 'Plombier', ar: 'سباك'),
        CatalogType(id: 'ac', fr: 'Climatisation', ar: 'تركيب وصيانة المكيفات'),
        CatalogType(id: 'water_heater', fr: 'Chauffe-eau', ar: 'صيانة سخان الماء'),
        CatalogType(id: 'carpenter', fr: 'Menuisier', ar: 'نجار'),
        CatalogType(id: 'glazier', fr: 'Vitrier', ar: 'تركيب وإصلاح البلور'),
        CatalogType(id: 'locksmith', fr: 'Serrurier', ar: 'فتح الأقفال'),
        CatalogType(id: 'cleaner', fr: 'Femme de menage', ar: 'عاملة نظافة'),
        CatalogType(id: 'sofa_cleaning', fr: 'Nettoyage canapes', ar: 'تنظيف الكنبات والمفروشات'),
        CatalogType(id: 'pest_control', fr: 'Desinsectisation', ar: 'مكافحة الحشرات'),
        CatalogType(id: 'gardener', fr: 'Jardinier', ar: 'بستاني'),
        CatalogType(id: 'pool', fr: 'Entretien piscines', ar: 'صيانة المسابح'),
        CatalogType(id: 'window_cleaning', fr: 'Nettoyage vitres', ar: 'تنظيف النوافذ'),
        CatalogType(id: 'moving', fr: 'Demenagement', ar: 'نقل الأثاث'),
        CatalogType(id: 'furniture_assembly', fr: 'Montage meubles', ar: 'تركيب الأثاث'),
        CatalogType(id: 'roof_isolation', fr: 'Isolation toiture', ar: 'عزل الأسطح'),
        CatalogType(id: 'parabole', fr: 'Installation parabole', ar: 'تركيب parabole'),
        CatalogType(id: 'cctv', fr: 'Cameras surveillance', ar: 'تركيب كاميرات مراقبة'),
        CatalogType(id: 'doors', fr: 'Installation portes', ar: 'تركيب الأبواب'),
        CatalogType(id: 'windows', fr: 'Installation fenetres', ar: 'تركيب النوافذ'),
        CatalogType(id: 'plaster', fr: 'Platre / decoration', ar: 'تركيب الجبس والديكور'),
        CatalogType(id: 'handyman', fr: 'Handyman', ar: 'عامل صيانة عامة'),
      ],
    ),

    CatalogCategory(
      id: 'auto',
      icon: Icons.directions_car_rounded,
      fr: 'Auto',
      ar: 'السيارات',
      types: [
        CatalogType(id: 'mechanic', fr: 'Mecanicien', ar: 'ميكانيكي'),
        CatalogType(id: 'auto_electric', fr: 'Electricien auto', ar: 'كهربائي سيارات'),
        CatalogType(id: 'bodywork', fr: 'Tolier', ar: 'Tolier'),
        CatalogType(id: 'paint_auto', fr: 'Carrosserie & peinture', ar: 'سمكري ودهان سيارات'),
        CatalogType(id: 'tires', fr: 'Reparation pneus', ar: 'إصلاح الإطارات'),
        CatalogType(id: 'battery', fr: 'Remplacement batterie', ar: 'تبديل البطارية'),
        CatalogType(id: 'glass_auto', fr: 'Vitres / pare-brise', ar: 'إصلاح البلور'),
        CatalogType(id: 'lights', fr: 'Reparation eclairage', ar: 'إصلاح الأضواء'),
        CatalogType(id: 'locksmith_auto', fr: 'Serrurier automobile', ar: 'Serrurier Automobile'),
        CatalogType(id: 'ac_auto', fr: 'Climatisation auto', ar: 'صيانة Climatiseur'),
        CatalogType(id: 'car_wash', fr: 'Lavage auto', ar: 'Lavage Auto'),
        CatalogType(id: 'polish', fr: 'Polissage', ar: 'Polissage'),
        CatalogType(id: 'oil', fr: 'Vidange', ar: 'تغيير الزيت'),
        CatalogType(id: 'diagnostic', fr: 'Diagnostic electronique', ar: 'Diagnostic إلكتروني'),
        CatalogType(id: 'towing', fr: 'Depannage / remorquage', ar: 'Dépannage (سحب السيارات)'),
      ],
    ),

    CatalogCategory(
      id: 'health',
      icon: Icons.health_and_safety_rounded,
      fr: 'Sante',
      ar: 'الصحة',
      types: [
        CatalogType(id: 'gp', fr: 'Medecin generaliste', ar: 'طبيب عام'),
        CatalogType(id: 'specialist', fr: 'Medecin specialiste', ar: 'طبيب مختص'),
        CatalogType(id: 'dentist', fr: 'Dentiste', ar: 'طبيب أسنان'),
        CatalogType(id: 'nurse', fr: 'Infirmier', ar: 'ممرض'),
        CatalogType(id: 'kine', fr: 'Kinesitherapeute', ar: 'علاج طبيعي'),
        CatalogType(id: 'psych', fr: 'Psychologue', ar: 'أخصائي نفسي'),
        CatalogType(id: 'vision', fr: 'Opticien', ar: 'أخصائي بصريات'),
        CatalogType(id: 'pharmacy', fr: 'Livraison pharmacie', ar: 'صيدلية توصيل'),
      ],
    ),

    CatalogCategory(
      id: 'beauty',
      icon: Icons.brush_rounded,
      fr: 'Beaute',
      ar: 'الجمال',
      types: [
        CatalogType(id: 'barber', fr: 'Barbier', ar: 'حلاق رجال'),
        CatalogType(id: 'hair_women', fr: 'Coiffeuse', ar: 'كوافيرة'),
        CatalogType(id: 'nails', fr: 'Nail Artist', ar: 'Nail Artist'),
        CatalogType(id: 'makeup', fr: 'Makeup Artist', ar: 'Makeup Artist'),
        CatalogType(id: 'esthetic', fr: 'Esthetique', ar: 'أخصائي تجميل'),
        CatalogType(id: 'massage', fr: 'Massage', ar: 'Massage'),
        CatalogType(id: 'aesthetic_med', fr: 'Soins esthetiques', ar: 'تجميل'),
      ],
    ),

    CatalogCategory(
      id: 'education',
      icon: Icons.school_rounded,
      fr: 'Education',
      ar: 'التعليم',
      types: [
        CatalogType(id: 'tutor', fr: 'Professeur particulier', ar: 'مدرس خصوصي'),
        CatalogType(id: 'languages', fr: 'Professeur de langues', ar: 'مدرس لغات'),
        CatalogType(id: 'it', fr: 'Professeur informatique', ar: 'مدرس إعلامية'),
        CatalogType(id: 'music', fr: 'Professeur musique', ar: 'مدرس موسيقى'),
        CatalogType(id: 'swim', fr: 'Coach natation', ar: 'مدرب سباحة'),
        CatalogType(id: 'sport', fr: 'Coach sportif', ar: 'Coach Sportif'),
      ],
    ),

    CatalogCategory(
      id: 'tech',
      icon: Icons.computer_rounded,
      fr: 'Tech',
      ar: 'التكنولوجيا',
      types: [
        CatalogType(id: 'dev', fr: 'Developpeur', ar: 'مبرمج'),
        CatalogType(id: 'web', fr: 'Designer web', ar: 'مصمم مواقع'),
        CatalogType(id: 'mobile', fr: 'Developpeur mobile', ar: 'مطور تطبيقات'),
        CatalogType(id: 'graphic', fr: 'Graphic Designer', ar: 'Graphic Designer'),
        CatalogType(id: 'video_edit', fr: 'Montage video', ar: 'مونتاج فيديو'),
        CatalogType(id: 'photo', fr: 'Photographe', ar: 'مصور'),
        CatalogType(id: 'video', fr: 'Videaste', ar: 'مصور فيديو'),
        CatalogType(id: 'marketing', fr: 'Digital marketing', ar: 'Digital Marketing'),
        CatalogType(id: 'cyber', fr: 'Cyber security', ar: 'Cyber Security'),
        CatalogType(id: 'pc_repair', fr: 'Reparation PC', ar: 'صيانة الحواسيب'),
      ],
    ),

    CatalogCategory(
      id: 'family',
      icon: Icons.family_restroom_rounded,
      fr: 'Famille',
      ar: 'العائلة',
      types: [
        CatalogType(id: 'babysitter', fr: 'Babysitter', ar: 'Babysitter'),
        CatalogType(id: 'elder', fr: 'Aide seniors', ar: 'رعاية كبار السن'),
        CatalogType(id: 'pet', fr: 'Pet sitter', ar: 'Pet Sitter'),
        CatalogType(id: 'trainer', fr: 'Education animaux', ar: 'تدريب الحيوانات'),
      ],
    ),

    CatalogCategory(
      id: 'events',
      icon: Icons.celebration_rounded,
      fr: 'Evenements',
      ar: 'المناسبات',
      types: [
        CatalogType(id: 'wedding_photo', fr: 'Photographe mariage', ar: 'مصور أعراس'),
        CatalogType(id: 'videographer', fr: 'Videographer', ar: 'Videographer'),
        CatalogType(id: 'dj', fr: 'DJ', ar: 'DJ'),
        CatalogType(id: 'musician', fr: 'Musicien', ar: 'Musicien'),
        CatalogType(id: 'event_org', fr: 'Organisation', ar: 'تنظيم حفلات'),
        CatalogType(id: 'decor', fr: 'Decoration', ar: 'Décoration'),
        CatalogType(id: 'catering', fr: 'Traiteur', ar: 'Catering'),
      ],
    ),

    CatalogCategory(
      id: 'transport',
      icon: Icons.local_shipping_rounded,
      fr: 'Transport',
      ar: 'النقل',
      types: [
        CatalogType(id: 'moving', fr: 'Demenagement', ar: 'نقل الأثاث'),
        CatalogType(id: 'goods', fr: 'Transport marchandises', ar: 'نقل البضائع'),
        CatalogType(id: 'delivery', fr: 'Livraison express', ar: 'توصيل سريع'),
        CatalogType(id: 'driver', fr: 'Chauffeur prive', ar: 'سائق خاص'),
      ],
    ),

    CatalogCategory(
      id: 'business',
      icon: Icons.business_center_rounded,
      fr: 'Business',
      ar: 'الأعمال',
      types: [
        CatalogType(id: 'lawyer', fr: 'Avocat', ar: 'محامي'),
        CatalogType(id: 'accountant', fr: 'Comptable', ar: 'محاسب'),
        CatalogType(id: 'real_estate', fr: 'Agent immobilier', ar: 'وكيل عقاري'),
        CatalogType(id: 'legal', fr: 'Conseiller juridique', ar: 'مستشار قانوني'),
        CatalogType(id: 'consulting', fr: 'Consultant', ar: 'مستشار أعمال'),
      ],
    ),

    CatalogCategory(
      id: 'other_services',
      icon: Icons.local_laundry_service_rounded,
      fr: 'Autres',
      ar: 'خدمات أخرى',
      types: [
        CatalogType(id: 'laundry', fr: 'Lavage & repassage', ar: 'غسيل وكي الملابس'),
        CatalogType(id: 'tailor', fr: 'Tailleur', ar: 'خياط'),
        CatalogType(id: 'watch_repair', fr: 'Reparation montres', ar: 'إصلاح الساعات'),
        CatalogType(id: 'phone_repair', fr: 'Reparation telephones', ar: 'إصلاح الهواتف'),
        CatalogType(id: 'tv_repair', fr: 'Reparation TV', ar: 'إصلاح التلفاز'),
        CatalogType(id: 'fridge_repair', fr: 'Reparation refrigerateurs', ar: 'إصلاح الثلاجات'),
        CatalogType(id: 'washer_repair', fr: 'Reparation machines a laver', ar: 'إصلاح الغسالات'),
        CatalogType(id: 'oven_repair', fr: 'Reparation fours', ar: 'إصلاح الأفران'),
        CatalogType(id: 'coffee_repair', fr: 'Reparation machines a cafe', ar: 'إصلاح آلات القهوة'),
      ],
    ),
  ];

  static CatalogCategory byId(String id) =>
      categories.firstWhere((c) => c.id == id);
}