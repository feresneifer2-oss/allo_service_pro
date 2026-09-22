/// Central legal & about copy for Allo Service Pro (AR/FR).
///
/// Single source of truth consumed by [AboutScreen], [TermsScreen] and
/// [PrivacyPolicyScreen]. The wording below is the exact approved content —
/// do not paraphrase.
class LegalTexts {
  LegalTexts._();

  // ── Dynamic legal headers (Qodo) ──────────────────────────────────────
  // Hard-coded "Dernière mise à jour …" / "آخر تحديث …" strings are moved
  // here so the *approved* legal body never has to be touched when the
  // policy is revised — only `_legalDate` / `_appVersion` change.
  static const String _legalDate = '20 septembre 2026';

  /// Arabic-localized form of the SAME date (CodeRabbit): the Arabic legal
  /// headers must not carry a French month name ("20 septembre 2026").
  static const String _legalDateAr = '20 سبتمبر 2026';

  static const String _appVersion = '2.0';

  static const String _termsArHeader =
      'آخر تحديث: $_legalDateAr — الإصدار $_appVersion\n';
  static const String _termsFrHeader =
      'Dernière mise à jour : $_legalDate — Version $_appVersion\n';
  static const String _privacyFrHeader =
      'Dernière mise à jour : $_legalDate — Version $_appVersion\n';
  static const String _privacyArHeader =
      'آخر تحديث: $_legalDateAr — الإصدار $_appVersion\n';

  // ── À propos / من نحن ──────────────────────────────────────────────────
  static const String aboutAr =
      'ألو سيرفيس برو (Allo Service Pro) هي المنصة التونسية الرائدة للربط '
      'المباشر بين العملاء وأفضل المهنيين والحرفيين في جميع الولايات (سباكة، '
      'كهرباء، تنظيف، صيانة...). هدفنا تسهيل الخدمات المنزلية بضغطة زر مع '
      'ضمان السرعة والشفافية.';

  static const String aboutFr =
      "Allo Service Pro est la plateforme tunisienne de référence pour la "
      "mise en relation directe entre clients et professionnels qualifiés à "
      "travers toutes les gouvernorats. Notre mission est de simplifier vos "
      "services à domicile en un clic.";

  // ── Conditions d'utilisation / شروط الاستخدام ─────────────────────────
  static const String termsAr = '$_termsArHeader'
      '1. قبول الشروط: بإنشاء حساب أو باستخدام تطبيق «ألو سيرفيس برو» فإنك '
      'توافق على هذه الشروط وعلى سياسة الخصوصية. إذا لم تكن موافقاً، يُرجى '
      'عدم استخدام التطبيق.\n'
      '2. طبيعة الخدمة: التطبيق منصة رقمية وسيطة تربط بين العملاء والمهنيين '
      'المستقلين؛ ولا يشغّل التطبيق الخدمات ولا يوظّف المهنيين، ولا يُعدّ '
      'طرفاً في العقد المُبرم بينهما.\n'
      '3. حساب المستخدم: يجب أن تكون بيانات التسجيل صحيحة ومحدّثة، وأن يحافظ '
      'المستخدم على سرية رمز التحقق (OTP) الخاص بحسابه؛ وكل نشاط يجري عبر '
      'الحساب يُنسَب إلى صاحبه.\n'
      '4. التزامات العميل: تقديم عنوان دقيق ووصف صحيح للخدمة المطلوبة، '
      'والالتزام بالموعد المتفق عليه، والدفع للمهني مباشرة حسب الاتفاق '
      '(نقداً أو D17).\n'
      '5. التزامات المهني: تقديم بيانات مهنية صحيحة (الهوية، الشهادات، '
      'الخبرة)، والالتزام بجودة الخدمة والمواعيد والأسعار المعلنة، وتقديم '
      'فاتورة عند الطلب.\n'
      '6. الأتعاب والاشتراك: الأسعار المعروضة إرشادية ويُتفق عليها بين '
      'الطرفين. تخضع اشتراكات المهنيين ورصيد التوكنات للشروط المعلنة داخل '
      'التطبيق.\n'
      '7. الإلغاء: يمكن للعميل إلغاء الطلب قبل انطلاق المهني نحو مكان الخدمة '
      'دون أي رسوم. تُطبَّق إجراءات مكافحة الاستخدام المُسيء عند تكرار '
      'الإلغاء.\n'
      '8. المسؤولية: التطبيق غير مسؤول عن جودة الخدمة أو عن أي ضرر ينشأ عن '
      'تنفيذها، وتبقى المسؤولية قائمة بين العميل والمهني. تعمل المنصة على '
      'معالجة الشكاوى بحسن نية.\n'
      '9. الإيقاف: يجوز لنا تعليق أو إيقاف أي حساب يخالف هذه الشروط أو يُسيء '
      'استخدام المنصة.\n'
      '10. الملكية الفكرية: جميع العلامات والشعارات ومحتوى التطبيق محمية ولا '
      'يجوز إعادة استخدامها دون إذن كتابي مسبق.\n'
      '11. التعديلات: قد نُحدّث هذه الشروط، ويُعدّ استمرارك في استخدام '
      'التطبيق بعد التحديث موافقة عليه؛ ويُذكر تاريخ آخر تحديث في أعلى هذه '
      'الصفحة.\n'
      '12. القانون المطبّق: تخضع هذه الشروط للقانون التونسي، وتختص المحاكم '
      'التونسية بالنظر في أي نزاع.\n'
      '13. التواصل: الدعم متاح عبر التطبيق — واتساب +216 24 449 959 أو '
      'الهاتف 24449959.';

  static const String termsFr = '$_termsFrHeader'
      "1. Acceptation: la création d'un compte ou l'utilisation d'Allo Service "
      "Pro vaut acceptation des présentes conditions et de la politique de "
      "confidentialité. Si vous n'y adhérez pas, n'utilisez pas l'application.\n"
      "2. Rôle de la plateforme: Allo Service Pro est un intermédiaire "
      "numérique reliant clients et prestataires indépendants. Elle n'exécute "
      "pas les prestations, n'emploie pas les professionnels et n'est pas "
      "partie au contrat conclu entre eux.\n"
      "3. Compte utilisateur: les informations d'inscription doivent être "
      "exactes et à jour, et le code de vérification (OTP) doit rester "
      "confidentiel. Toute activité effectuée depuis un compte est réputée "
      "être celle de son titulaire.\n"
      "4. Engagements Client: fournir une adresse exacte et une description "
      "fidèle de la prestation, respecter le rendez-vous et payer le "
      "professionnel directement selon l'accord conclu (espèces ou D17).\n"
      "5. Engagements Pro: fournir des informations professionnelles exactes "
      "(identité, diplômes, expérience), garantir la qualité du service, "
      "respecter les tarifs et rendez-vous annoncés et délivrer une facture "
      "sur demande.\n"
      "6. Tarifs et abonnement: les prix affichés sont indicatifs et convenus "
      "entre les parties. Les abonnements professionnels et le solde de "
      "tokens relèvent des conditions affichées dans l'application.\n"
      "7. Annulation: gratuite pour le client avant le déplacement du "
      "professionnel. Les mesures anti-abus s'appliquent en cas d'annulations "
      "répétées.\n"
      "8. Responsabilité: la plateforme n'est pas responsable de la qualité de "
      "la prestation ni des dommages résultant de son exécution; cette "
      "responsabilité demeure entre le client et le professionnel. La "
      "plateforme traite les réclamations de bonne foi.\n"
      "9. Suspension: tout compte enfreignant ces conditions ou abusant de la "
      "plateforme peut être suspendu ou désactivé.\n"
      "10. Propriété intellectuelle: marques, logos et contenus de "
      "l'application sont protégés et ne peuvent être réutilisés sans accord "
      "écrit préalable.\n"
      "11. Modifications: ces conditions peuvent être mises à jour; la "
      "poursuite de l'utilisation après mise à jour vaut acceptation. La date "
      "de dernière mise à jour figure en haut de cette page.\n"
      "12. Droit applicable: les présentes conditions sont régies par le droit "
      "tunisien et tout litige relève des tribunaux tunisiens.\n"
      "13. Contact: support disponible dans l'application — WhatsApp "
      "+216 24 449 959 ou le 24449959.";

  // ── Politique de confidentialité / سياسة الخصوصية ─────────────────────
  static const String privacyAr = '$_privacyArHeader'
      '1. البيانات المجموعة: الاسم، البريد الإلكتروني (يُستخدم كمعرّف لتسجيل '
      'الدخول وإرسال رمز التحقق OTP)، رقم الهاتف (اختياري)، الموقع الجغرافي '
      '(GPS) لغرض تقديم الخدمة، إضافة إلى مستندات التحقق (بطاقة الهوية أو '
      'الشهادة المهنية وصورة شخصية) ورسائل المحادثة والوسائط المتبادلة داخل '
      'الطلب.\n'
      '2. استخدام البيانات: تُستخدم البيانات حصرياً لتوصيل الطلبات، والتحقق من '
      'هوية المهنيين، وتسهيل التواصل بين العميل والمهني، وإرسال الإشعارات، '
      'ومكافحة الاستخدام المُسيء، وتحسين جودة الخدمة.\n'
      '3. الاستضافة ومزوّدو الخدمة: تُخزَّن البيانات على بنية سحابية لدى مزوّد '
      'الاستضافة Supabase، وتُستخدم خدمة إشعارات لإرسال التنبيهات وواتساب '
      'للتواصل مع الدعم. لا نبيع بياناتك ولا نشاركها مع أي طرف ثالث لأغراض '
      'تجارية.\n'
      '4. مدة الاحتفاظ: نحتفظ ببيانات الحساب ما دام الحساب قائماً، وبسجل '
      'الطلبات والرسائل المدة اللازمة لمعالجة النزاعات والامتثال القانوني، ثم '
      'تُحذف أو تُجهَّل.\n'
      '5. حماية البيانات: تُنقل البيانات عبر اتصال مشفَّر وتُخزَّن بصلاحيات '
      'وصول مقيّدة، ولا يطّلع على مستندات التحقق إلا فريق المراجعة.\n'
      '6. حقوق المستخدم: يمكنك تعديل بياناتك في أي وقت من إعدادات البروفايل، '
      'ومسح جلستك وبياناتك المحلية المخزنة على هذا الجهاز عبر خيار «تسجيل '
      'الخروج». لأي طلب آخر يخص بياناتك تواصل معنا عبر الدعم.\n'
      '7. خصوصية الأطفال: التطبيق غير موجّه لمن هم دون 18 سنة، ولا نجمع '
      'بياناتهم عن قصد.\n'
      '8. التعديلات: قد نُحدّث سياسة الخصوصية، وسنُشعرك بأي تغيير جوهري داخل '
      'التطبيق؛ ويُذكر تاريخ آخر تحديث في أعلى هذه الصفحة.\n'
      '9. التواصل: لأي سؤال حول بياناتك — واتساب +216 24 449 959 أو الهاتف '
      '24449959.';

  static const String privacyFr = '$_privacyFrHeader'
      "1. Données collectées: nom, adresse e-mail (identifiant de connexion et "
      "envoi du code OTP), numéro de téléphone facultatif, position GPS pour "
      "exécuter le service, ainsi que les pièces de vérification (CIN, diplôme "
      "ou patente et selfie) et les messages et médias échangés dans le cadre "
      "de la commande.\n"
      "2. Usage: mise en relation des commandes, vérification de l'identité des "
      "professionnels, communication client-professionnel, notifications, "
      "prévention des abus et amélioration du service.\n"
      "3. Hébergement et sous-traitants: les données sont hébergées sur "
      "l'infrastructure Supabase, un service de notifications est utilisé pour "
      "les alertes et WhatsApp pour le support. Vos données ne sont jamais "
      "vendues ni cédées à des tiers à des fins commerciales.\n"
      "4. Conservation: les données du compte sont conservées tant que le "
      "compte existe; l'historique des commandes et des messages est conservé "
      "le temps nécessaire à la gestion des litiges et au respect des "
      "obligations légales, puis supprimé ou anonymisé.\n"
      "5. Protection: les échanges sont chiffrés en transit et l'accès aux "
      "données est restreint; seules les équipes de vérification consultent les "
      "pièces justificatives.\n"
      "6. Vos droits: vous pouvez modifier vos données à tout moment depuis "
      "votre profil, et effacer votre session ainsi que les données locales "
      "stockées sur cet appareil via l'option « Déconnexion ». Pour toute autre "
      "demande, contactez le support.\n"
      "7. Mineurs: l'application ne s'adresse pas aux personnes de moins de "
      "18 ans.\n"
      "8. Modifications: cette politique peut être mise à jour; tout changement "
      "substantiel est signalé dans l'application. La date de dernière mise à "
      "jour figure en haut de cette page.\n"
      "9. Contact: pour toute question — WhatsApp +216 24 449 959 ou le "
      "24449959.";
}
