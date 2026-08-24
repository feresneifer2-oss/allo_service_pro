class TunisianLocation {
  final String governorateAr;
  final String governorateFr;
  final List<TunisianCity> cities;

  const TunisianLocation({
    required this.governorateAr,
    required this.governorateFr,
    required this.cities,
  });
}

class TunisianCity {
  final String ar;
  final String fr;

  const TunisianCity({
    required this.ar,
    required this.fr,
  });
}

class TunisianLocations {
  TunisianLocations._();

  static const locations = [
    TunisianLocation(
      governorateAr: 'تونس',
      governorateFr: 'Tunis',
      cities: [
        TunisianCity(ar: 'تونس المدينة', fr: 'Tunis Ville'),
        TunisianCity(ar: 'باب البحر', fr: 'Bab Bhar'),
        TunisianCity(ar: 'باب سويقة', fr: 'Bab Saadoun'),
        TunisianCity(ar: 'العمران', fr: 'El Omrane'),
        TunisianCity(ar: 'العمران الأعلى', fr: 'El Omrane Supérieur'),
        TunisianCity(ar: 'التحرير', fr: 'El Tahrir'),
        TunisianCity(ar: 'المنزه', fr: 'El Menzeh'),
        TunisianCity(ar: 'حي الخضراء', fr: 'El Khadra'),
        TunisianCity(ar: 'باردو', fr: 'Bardo'),
        TunisianCity(ar: 'السيجومي', fr: 'El Segjoumi'),
        TunisianCity(ar: 'الزهور', fr: 'Ezzouhour'),
        TunisianCity(ar: 'الحرايرية', fr: 'El Hrairia'),
        TunisianCity(ar: 'سيدي حسين', fr: 'Sidi El Hassen'),
        TunisianCity(ar: 'جبل الجلود', fr: 'Jebel Jelloud'),
        TunisianCity(ar: 'الكبارية', fr: 'Kabaria'),
        TunisianCity(ar: 'سيدي البشير', fr: 'Sidi Bchir'),
        TunisianCity(ar: 'الوردية', fr: 'Ettadhamen'),
        TunisianCity(ar: 'قرطاج', fr: 'Carthage'),
        TunisianCity(ar: 'سيدي بوسعيد', fr: 'Sidi Bou Said'),
        TunisianCity(ar: 'حلق الوادي', fr: 'Halk El Oued'),
        TunisianCity(ar: 'المرسى', fr: 'La Marsa'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'أريانة',
      governorateFr: 'Ariana',
      cities: [
        TunisianCity(ar: 'أريانة المدينة', fr: 'Ariana Ville'),
        TunisianCity(ar: 'سكرة', fr: 'Sokra'),
        TunisianCity(ar: 'رواد', fr: 'Raoued'),
        TunisianCity(ar: 'قلعة الأندلس', fr: 'Kalaat El Andalous'),
        TunisianCity(ar: 'سيدي ثابت', fr: 'Sidi Thabet'),
        TunisianCity(ar: 'حي التضامن', fr: 'Ettadhamen'),
        TunisianCity(ar: 'المنيهلة', fr: 'La Mnihla'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'بن عروس',
      governorateFr: 'Ben Arous',
      cities: [
        TunisianCity(ar: 'بن عروس', fr: 'Ben Arous'),
        TunisianCity(ar: 'المدينة الجديدة', fr: 'Médina Nouvelle'),
        TunisianCity(ar: 'مغيرة', fr: 'Megrine'),
        TunisianCity(ar: 'المحمدية', fr: 'Mohamedia'),
        TunisianCity(ar: 'فوشانة', fr: 'Fouchana'),
        TunisianCity(ar: 'مرناق', fr: 'Mornag'),
        TunisianCity(ar: 'حمام الشط', fr: 'Hammam Chott'),
        TunisianCity(ar: 'حمام الأنف', fr: 'Hammam Lif'),
        TunisianCity(ar: 'بومهل البساتين', fr: 'Boumhel El Bassatine'),
        TunisianCity(ar: 'الزهراء', fr: 'Ezzahra'),
        TunisianCity(ar: 'رادس', fr: 'Radès'),
        TunisianCity(ar: 'مقرين', fr: 'Mégrine'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'منوبة',
      governorateFr: 'Manouba',
      cities: [
        TunisianCity(ar: 'منوبة', fr: 'Manouba'),
        TunisianCity(ar: 'الدندان', fr: 'Douar Hicher'),
        TunisianCity(ar: 'دوار هيشر', fr: 'Den Den'),
        TunisianCity(ar: 'وادي الليل', fr: 'Oued Lill'),
        TunisianCity(ar: 'المرناقية', fr: 'Mornaguia'),
        TunisianCity(ar: 'برج العامري', fr: 'Borj El Amri'),
        TunisianCity(ar: 'الجديدة', fr: 'El Jouada'),
        TunisianCity(ar: 'طبربة', fr: 'Tebourba'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'نابل',
      governorateFr: 'Nabeul',
      cities: [
        TunisianCity(ar: 'نابل', fr: 'Nabeul'),
        TunisianCity(ar: 'دار شعبان الفهري', fr: 'Dar Chaabane El Fehri'),
        TunisianCity(ar: 'بني خيار', fr: 'Bni Khiar'),
        TunisianCity(ar: 'قربة', fr: 'Korba'),
        TunisianCity(ar: 'منزل تميم', fr: 'Menzel Temime'),
        TunisianCity(ar: 'الميدة', fr: 'El Maïz'),
        TunisianCity(ar: 'قليبية', fr: 'Kelibia'),
        TunisianCity(ar: 'حمام الأغزاز', fr: 'Hammam Ghezèze'),
        TunisianCity(ar: 'الهوارية', fr: 'Hawaria'),
        TunisianCity(ar: 'تاكلسة', fr: 'Takelsa'),
        TunisianCity(ar: 'سليمان', fr: 'Soliman'),
        TunisianCity(ar: 'منزل بوزلفة', fr: 'Menzel Bouzelfa'),
        TunisianCity(ar: 'بني خلاد', fr: 'Bni Khalled'),
        TunisianCity(ar: 'قرمبالية', fr: 'Korba'),
        TunisianCity(ar: 'بوعرقوب', fr: 'Bou Argoub'),
        TunisianCity(ar: 'الحمامات', fr: 'Hammamet'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'زغوان',
      governorateFr: 'Zaghouan',
      cities: [
        TunisianCity(ar: 'زغوان', fr: 'Zaghouan'),
        TunisianCity(ar: 'الزريبة', fr: 'Zriba'),
        TunisianCity(ar: 'بئر مشارقة', fr: 'Bir Mcherga'),
        TunisianCity(ar: 'الفحص', fr: 'El Fahs'),
        TunisianCity(ar: 'الناظور', fr: 'Nadhour'),
        TunisianCity(ar: 'صواف', fr: 'Sawaf'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'بنزرت',
      governorateFr: 'Bizerte',
      cities: [
        TunisianCity(ar: 'بنزرت الشمالية', fr: 'Bizerte Nord'),
        TunisianCity(ar: 'بنزرت الجنوبية', fr: 'Bizerte Sud'),
        TunisianCity(ar: 'جرزونة', fr: 'Jerezoun'),
        TunisianCity(ar: 'منزل جميل', fr: 'Menzel Jemil'),
        TunisianCity(ar: 'منزل بورقيبة', fr: 'Menzel Bourguiba'),
        TunisianCity(ar: 'تينجة', fr: 'Tinja'),
        TunisianCity(ar: 'ماطر', fr: 'Mateur'),
        TunisianCity(ar: 'أوتيك', fr: 'Utique'),
        TunisianCity(ar: 'غار الملح', fr: 'Ghar El Melh'),
        TunisianCity(ar: 'سجنان', fr: 'Sejnane'),
        TunisianCity(ar: 'جومين', fr: 'Joumine'),
        TunisianCity(ar: 'غزالة', fr: 'Ghezala'),
        TunisianCity(ar: 'رأس الجبل', fr: 'Ras Jebel'),
        TunisianCity(ar: 'العالية', fr: 'El Alia'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'باجة',
      governorateFr: 'Béja',
      cities: [
        TunisianCity(ar: 'باجة الشمالية', fr: 'Béja Nord'),
        TunisianCity(ar: 'باجة الجنوبية', fr: 'Béja Sud'),
        TunisianCity(ar: 'عمدون', fr: 'Amdoun'),
        TunisianCity(ar: 'نفزة', fr: 'Nefza'),
        TunisianCity(ar: 'تيبار', fr: 'Tibar'),
        TunisianCity(ar: 'تستور', fr: 'Téboursouk'),
        TunisianCity(ar: 'قبلاط', fr: 'Kbalat'),
        TunisianCity(ar: 'مجاز الباب', fr: 'Mjez El Bab'),
        TunisianCity(ar: 'تبرسق', fr: 'Teboursok'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'جندوبة',
      governorateFr: 'Jendouba',
      cities: [
        TunisianCity(ar: 'جندوبة', fr: 'Jendouba'),
        TunisianCity(ar: 'جندوبة الشمالية', fr: 'Jendouba Nord'),
        TunisianCity(ar: 'بوسالم', fr: 'Bousalem'),
        TunisianCity(ar: 'بلطة بوعوان', fr: 'Boussellem'),
        TunisianCity(ar: 'طبرقة', fr: 'Tabarka'),
        TunisianCity(ar: 'عين دراهم', fr: 'Aïn Draham'),
        TunisianCity(ar: 'فرنانة', fr: 'Fernana'),
        TunisianCity(ar: 'غار الدماء', fr: 'Ghardimaou'),
        TunisianCity(ar: 'وادي مليز', fr: 'Oued Melliz'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'الكاف',
      governorateFr: 'Le Kef',
      cities: [
        TunisianCity(ar: 'الكاف الشرقية', fr: 'Le Kef Est'),
        TunisianCity(ar: 'الكاف الغربية', fr: 'Le Kef Ouest'),
        TunisianCity(ar: 'نبر', fr: 'Nebeur'),
        TunisianCity(ar: 'ساقية سيدي يوسف', fr: 'Sakiet Sidi Youssef'),
        TunisianCity(ar: 'تاجروين', fr: 'Tajerouine'),
        TunisianCity(ar: 'قلعة سنان', fr: 'Kalaat Senan'),
        TunisianCity(ar: 'القصور', fr: 'Ksar'),
        TunisianCity(ar: 'الدهماني', fr: 'Dahmani'),
        TunisianCity(ar: 'السرس', fr: 'Sers'),
        TunisianCity(ar: 'الجريصة', fr: 'Jerissa'),
        TunisianCity(ar: 'قلعة الخصبة', fr: 'Kalaat Khasba'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'سليانة',
      governorateFr: 'Siliana',
      cities: [
        TunisianCity(ar: 'سليانة الشمالية', fr: 'Siliana Nord'),
        TunisianCity(ar: 'سليانة الجنوبية', fr: 'Siliana Sud'),
        TunisianCity(ar: 'بورويس', fr: 'Bourouis'),
        TunisianCity(ar: 'قعفور', fr: 'Gaâfour'),
        TunisianCity(ar: 'العروسة', fr: 'L\'Aouassa'),
        TunisianCity(ar: 'سيدي بورويس', fr: 'Sidi Bourouis'),
        TunisianCity(ar: 'مكثر', fr: 'Makthar'),
        TunisianCity(ar: 'الروحية', fr: 'Rouhia'),
        TunisianCity(ar: 'كسرى', fr: 'Kesra'),
        TunisianCity(ar: 'برقو', fr: 'Bargou'),
        TunisianCity(ar: 'الحبابسة', fr: 'El Hababsia'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'سوسة',
      governorateFr: 'Sousse',
      cities: [
        TunisianCity(ar: 'سوسة المدينة', fr: 'Sousse Ville'),
        TunisianCity(ar: 'سوسة جوهرة', fr: 'Sousse Jawhara'),
        TunisianCity(ar: 'سوسة الرياض', fr: 'Sousse Riadh'),
        TunisianCity(ar: 'سوسة سيدي عبد الحميد', fr: 'Sousse Sidi Abdelhamid'),
        TunisianCity(
            ar: 'الزاوية القصيبة الثريات', fr: 'Zaouiet Sousse Mediouna'),
        TunisianCity(ar: 'حمام سوسة', fr: 'Hammam Sousse'),
        TunisianCity(ar: 'أكودة', fr: 'Akouda'),
        TunisianCity(ar: 'القلعة الكبرى', fr: 'Kalaat Kebira'),
        TunisianCity(ar: 'القلعة الصغرى', fr: 'Kalaat Sghira'),
        TunisianCity(ar: 'سيدي بوعلي', fr: 'Sidi Bou Ali'),
        TunisianCity(ar: 'هرقلة', fr: 'Hergla'),
        TunisianCity(ar: 'النفيضة', fr: 'Enfidha'),
        TunisianCity(ar: 'بوفيشة', fr: 'Bouficha'),
        TunisianCity(ar: 'كندار', fr: 'Kondar'),
        TunisianCity(ar: 'سيدي الهاني', fr: 'Sidi El Hani'),
        TunisianCity(ar: 'مساكن', fr: 'Msaken'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'المنستير',
      governorateFr: 'Monastir',
      cities: [
        TunisianCity(ar: 'المنستير', fr: 'Monastir'),
        TunisianCity(ar: 'الساحلين', fr: 'Sahline'),
        TunisianCity(ar: 'الوردانين', fr: 'Ouardanine'),
        TunisianCity(ar: 'جمال', fr: 'Jemmal'),
        TunisianCity(ar: 'بني بلة', fr: 'Bni Blel'),
        TunisianCity(ar: 'المكنين', fr: 'Moknine'),
        TunisianCity(ar: 'البقالطة', fr: 'Bekalta'),
        TunisianCity(ar: 'طبلبة', fr: 'Tebulba'),
        TunisianCity(ar: 'صيادة لمطة بوحجر', fr: 'Sayada-Lamta-Bou Hjar'),
        TunisianCity(ar: 'قصر هلال', fr: 'Ksar Hellal'),
        TunisianCity(ar: 'قصيبة المديوني', fr: 'Ksibet El Mediouni'),
        TunisianCity(ar: 'بني حسان', fr: 'Bni Hassen'),
        TunisianCity(ar: 'زرمدين', fr: 'Zeramdine'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'المهدية',
      governorateFr: 'Mahdia',
      cities: [
        TunisianCity(ar: 'المهدية', fr: 'Mahdia'),
        TunisianCity(ar: 'قصور الساف', fr: 'Ksour Essef'),
        TunisianCity(ar: 'الجم', fr: 'El Joumhour'),
        TunisianCity(ar: 'الشابة', fr: 'Chebba'),
        TunisianCity(ar: 'ملولش', fr: 'Melloulèche'),
        TunisianCity(ar: 'سيدي علوان', fr: 'Sidi Alouane'),
        TunisianCity(ar: 'هبيرة', fr: 'Hebira'),
        TunisianCity(ar: 'شربان', fr: 'Chorbane'),
        TunisianCity(ar: 'أولاد الشامخ', fr: 'Ouled Chamekh'),
        TunisianCity(ar: 'السواسي', fr: 'Souassi'),
        TunisianCity(ar: 'البرادعة', fr: 'Bradia'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'صفاقس',
      governorateFr: 'Sfax',
      cities: [
        TunisianCity(ar: 'صفاقس المدينة', fr: 'Sfax Ville'),
        TunisianCity(ar: 'صفاقس الغربية', fr: 'Sfax Ouest'),
        TunisianCity(ar: 'ساقية الزيت', fr: 'Sakiet Ezzit'),
        TunisianCity(ar: 'ساقية الداير', fr: 'Sakiet Eddaier'),
        TunisianCity(ar: 'الربض', fr: 'Rbade'),
        TunisianCity(ar: 'الحاجب', fr: 'El Hajeb'),
        TunisianCity(ar: 'جبنيانة', fr: 'Gremda'),
        TunisianCity(ar: 'العامرة', fr: 'Agareb'),
        TunisianCity(ar: 'الحنشة', fr: 'El Hencha'),
        TunisianCity(ar: 'عقارب', fr: 'Skhira'),
        TunisianCity(ar: 'منزل شاكر', fr: 'Menzel Chaker'),
        TunisianCity(ar: 'الغريبة', fr: 'Ghraiba'),
        TunisianCity(ar: 'بئر علي بن خليفة', fr: 'Bir Ali Ben Khalifa'),
        TunisianCity(ar: 'الصخيرة', fr: 'Sfax Kerkenna'),
        TunisianCity(ar: 'المحرص', fr: 'Mahres'),
        TunisianCity(ar: 'قرقنة', fr: 'Kerkennah'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'القيروان',
      governorateFr: 'Kairouan',
      cities: [
        TunisianCity(ar: 'القيروان الشمالية', fr: 'Kairouan Nord'),
        TunisianCity(ar: 'القيروان الجنوبية', fr: 'Kairouan Sud'),
        TunisianCity(ar: 'الشبيكة', fr: 'Chebika'),
        TunisianCity(ar: 'السبيخة', fr: 'Sbikha'),
        TunisianCity(ar: 'الوسلاتية', fr: 'Oueslatia'),
        TunisianCity(ar: 'حفوز', fr: 'Haffouz'),
        TunisianCity(ar: 'العلا', fr: 'El Ala'),
        TunisianCity(ar: 'حاجب العيون', fr: 'Hajeb El Ayoun'),
        TunisianCity(ar: 'نصر الله', fr: 'Nasrallah'),
        TunisianCity(ar: 'بوحجلة', fr: 'Bouhajla'),
        TunisianCity(ar: 'الشراردة', fr: 'Chrarda'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'القصرين',
      governorateFr: 'Kasserine',
      cities: [
        TunisianCity(ar: 'القصرين الشمالية', fr: 'Kasserine Nord'),
        TunisianCity(ar: 'القصرين الجنوبية', fr: 'Kasserine Sud'),
        TunisianCity(ar: 'الزهور', fr: 'Ezzouhour'),
        TunisianCity(ar: 'حاسي الفريد', fr: 'Hassi Frid'),
        TunisianCity(ar: 'سبيطلة', fr: 'Sbeitla'),
        TunisianCity(ar: 'سبيبة', fr: 'Sbiba'),
        TunisianCity(ar: 'جدليان', fr: 'Jdelliou'),
        TunisianCity(ar: 'العيون', fr: 'Elaoula'),
        TunisianCity(ar: 'فوسانة', fr: 'Foussana'),
        TunisianCity(ar: 'تالة', fr: 'Thala'),
        TunisianCity(ar: 'فريانة', fr: 'Feriana'),
        TunisianCity(ar: 'مجل بلعباس', fr: 'Majel Belabbès'),
        TunisianCity(ar: 'حيدرة', fr: 'Hydra'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'سيدي بوزيد',
      governorateFr: 'Sidi Bouzid',
      cities: [
        TunisianCity(ar: 'سيدي بوزيد الغربية', fr: 'Sidi Bouzid Ouest'),
        TunisianCity(ar: 'سيدي بوزيد الشرقية', fr: 'Sidi Bouzid Est'),
        TunisianCity(ar: 'جلمة', fr: 'Jelma'),
        TunisianCity(ar: 'سبالة أولاد عسكر', fr: 'Sbiba Ouled Asker'),
        TunisianCity(ar: 'بئر الحفي', fr: 'Bir El Hafey'),
        TunisianCity(ar: 'سيدي علي بن عون', fr: 'Sidi Ali Ben Aoun'),
        TunisianCity(ar: 'منزل بوزيان', fr: 'Menzel Bouzaiane'),
        TunisianCity(ar: 'المكناسي', fr: 'Meknassi'),
        TunisianCity(ar: 'السوق الجديد', fr: 'Souk Jedid'),
        TunisianCity(ar: 'المزونة', fr: 'Mezzouna'),
        TunisianCity(ar: 'الرقاب', fr: 'Regueb'),
        TunisianCity(ar: 'أولاد حفوز', fr: 'Ouled Haffouz'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'قابس',
      governorateFr: 'Gabès',
      cities: [
        TunisianCity(ar: 'قابس المدينة', fr: 'Gabès Ville'),
        TunisianCity(ar: 'قابس الغربية', fr: 'Gabès Ouest'),
        TunisianCity(ar: 'قابس الجنوبية', fr: 'Gabès Sud'),
        TunisianCity(ar: 'قابس الشرقية', fr: 'Gabès Est'),
        TunisianCity(ar: 'غنوش', fr: 'Ghannouch'),
        TunisianCity(ar: 'المطوية', fr: 'Matmata'),
        TunisianCity(ar: 'وذرف', fr: 'Oudhref'),
        TunisianCity(ar: 'الحامة', fr: 'El Hamma'),
        TunisianCity(ar: 'مطماطة', fr: 'Methennia'),
        TunisianCity(ar: 'مارث', fr: 'Mareth'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'مدنين',
      governorateFr: 'Médenine',
      cities: [
        TunisianCity(ar: 'مدنين الشمالية', fr: 'Médenine Nord'),
        TunisianCity(ar: 'مدنين الجنوبية', fr: 'Médenine Sud'),
        TunisianCity(ar: 'بني خداش', fr: 'Bni Khedach'),
        TunisianCity(ar: 'بن قردان', fr: 'Ben Guerdane'),
        TunisianCity(ar: 'جرجيس', fr: 'Jerba'),
        TunisianCity(ar: 'جربة حومة السوق', fr: 'Djerba Houmet Souk'),
        TunisianCity(ar: 'جربة ميدون', fr: 'Djerba Midoun'),
        TunisianCity(ar: 'جربة أجيم', fr: 'Djerba Ajim'),
        TunisianCity(ar: 'سيدي مخلوف', fr: 'Sidi Makhlouf'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'تطاوين',
      governorateFr: 'Tataouine',
      cities: [
        TunisianCity(ar: 'تطاوين الشمالية', fr: 'Tataouine Nord'),
        TunisianCity(ar: 'تطاوين الجنوبية', fr: 'Tataouine Sud'),
        TunisianCity(ar: 'الصمار', fr: 'Smâr'),
        TunisianCity(ar: 'بئر الأحمر', fr: 'Bir Lahmer'),
        TunisianCity(ar: 'غمراسن', fr: 'Ghemrassen'),
        TunisianCity(ar: 'ذهيبة', fr: 'Dehiba'),
        TunisianCity(ar: 'رمادة', fr: 'Remada'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'قفصة',
      governorateFr: 'Gafsa',
      cities: [
        TunisianCity(ar: 'قفصة الشمالية', fr: 'Gafsa Nord'),
        TunisianCity(ar: 'قفصة الجنوبية', fr: 'Gafsa Sud'),
        TunisianCity(ar: 'القصر', fr: 'El Ksar'),
        TunisianCity(ar: 'سيدي عيش', fr: 'Sidi Aïch'),
        TunisianCity(ar: 'بلخير', fr: 'Boulifa'),
        TunisianCity(ar: 'القطار', fr: 'Métlaoui'),
        TunisianCity(ar: 'أم العرائس', fr: 'Oum Larayes'),
        TunisianCity(ar: 'الرديف', fr: 'Redeyef'),
        TunisianCity(ar: 'المتلوي', fr: 'Moularès'),
        TunisianCity(ar: 'المظيلة', fr: 'Mdhilla'),
        TunisianCity(ar: 'سيدي بوبكر', fr: 'Sidi Bou Baker'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'توزر',
      governorateFr: 'Tozeur',
      cities: [
        TunisianCity(ar: 'توزر', fr: 'Tozeur'),
        TunisianCity(ar: 'دقاش', fr: 'Degache'),
        TunisianCity(ar: 'تمغزة', fr: 'Tameghza'),
        TunisianCity(ar: 'نفطة', fr: 'Nefta'),
        TunisianCity(ar: 'حزوة', fr: 'Hazoua'),
      ],
    ),
    TunisianLocation(
      governorateAr: 'قبلي',
      governorateFr: 'Kebili',
      cities: [
        TunisianCity(ar: 'قبلي الجنوبية', fr: 'Kebili Sud'),
        TunisianCity(ar: 'قبلي الشمالية', fr: 'Kebili Nord'),
        TunisianCity(ar: 'دوز الشمالية', fr: 'Douz Nord'),
        TunisianCity(ar: 'دوز الجنوبية', fr: 'Douz Sud'),
        TunisianCity(ar: 'سوق الأحد', fr: 'Souk Lahad'),
        TunisianCity(ar: 'الفوار', fr: 'Faouar'),
      ],
    ),
  ];

  static List<String> getGovernoratesAr() {
    return locations.map((loc) => loc.governorateAr).toList();
  }

  static List<String> getGovernoratesFr() {
    return locations.map((loc) => loc.governorateFr).toList();
  }

  static List<String> getCitiesAr(String governorateAr) {
    final location = locations.firstWhere(
      (loc) => loc.governorateAr == governorateAr,
      orElse: () => const TunisianLocation(
          governorateAr: '', governorateFr: '', cities: []),
    );
    return location.cities.map((city) => city.ar).toList();
  }

  static List<String> getCitiesFr(String governorateFr) {
    final location = locations.firstWhere(
      (loc) => loc.governorateFr == governorateFr,
      orElse: () => const TunisianLocation(
          governorateAr: '', governorateFr: '', cities: []),
    );
    return location.cities.map((city) => city.fr).toList();
  }

  static TunisianLocation? getLocationByAr(String governorateAr) {
    try {
      return locations.firstWhere((loc) => loc.governorateAr == governorateAr);
    } catch (_) {
      return null;
    }
  }

  static TunisianLocation? getLocationByFr(String governorateFr) {
    try {
      return locations.firstWhere((loc) => loc.governorateFr == governorateFr);
    } catch (_) {
      return null;
    }
  }
}
