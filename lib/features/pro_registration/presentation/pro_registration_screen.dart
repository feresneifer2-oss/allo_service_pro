import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/core/data/tunisian_locations.dart';
import 'package:allo_service_pro/core/services/document_media_service.dart';
import 'package:allo_service_pro/core/services/supabase_storage_service.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/verification_gate_screen.dart';

import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/app_image.dart';

class ProRegistrationScreen extends StatefulWidget {
  const ProRegistrationScreen({super.key});

  @override
  State<ProRegistrationScreen> createState() => _ProRegistrationScreenState();
}

class _ProRegistrationScreenState extends State<ProRegistrationScreen> {
  final _pageController = PageController();
  int _step = 0;

  // SUBMIT GUARD (CodeRabbit): a single in-flight submission must not be
  // re-entered by a double-tap (the wallet deduction + registry insert would
  // otherwise double-book the PRO code or the token cost). A second tap while
  // the future is pending is a no-op until the current one settles.
  bool _submitting = false;

  // REAL capture state (CodeRabbit / Supabase prep): the wizard no longer
  // fakes uploads. Each tile stores the ABSOLUTE local path of the photo
  // picked through [DocumentMediaService] — exactly what the future
  // Supabase Storage upload task will read — instead of a boolean flag.
  String? _docPhotoPath;
  String? _selfiePhotoPath;
  final List<String> _galleryPhotos = [];

  // A professional's contact number is entered LATER (profile completion) —
  // the identity that matters here is the verified e-mail. The legacy
  // hardcoded mock phone is gone: nothing fabricated reaches the admin
  // registry (or the future Supabase `pending_pros` table) anymore.

  final _nameController = TextEditingController();
  final _experienceController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _governorate = 'تونس';
  String? _city;

  /// The authentication e-mail captured ONCE when the form mounts.
  ///
  /// It is the Email-OTP identity and must survive every rebuild / wizard step
  /// / resubmission unchanged: reading it back from the live session at submit
  /// time risked resolving it AFTER a state reload (or a `null` session),
  /// which silently degraded the pro's record to a phone-only legacy account.
  late final String _email;

  @override
  void initState() {
    super.initState();
    // Immutable capture — taken before any rebuild can mutate the session.
    _email = _resolveSessionEmail();
    // Set default governorate based on language
    final isArabic = appLocale.value.languageCode == 'ar';
    _governorate = isArabic ? 'تونس' : 'Tunis';
    _city = isArabic ? 'تونس المدينة' : 'Tunis Ville';
    _selectedCategory = ServicesCatalog.categories.first;
  }

  /// Snapshots the session e-mail and normalizes it (trim + lowercase) so the
  /// value bound to the credential registry is byte-identical to the key used
  /// by login / OTP verification.
  String _resolveSessionEmail() {
    final raw = UserStore.user.value?.email ?? '';
    return raw.trim().toLowerCase();
  }

  /// The e-mail actually committed with the registration: the immutable
  /// snapshot, falling back to the live session only if the snapshot was empty
  /// (e.g. the screen was opened without a hydrated session).
  String get _committedEmail {
    if (_email.isNotEmpty) return _email;
    return _resolveSessionEmail();
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

  // Documents
  String _docType = 'diploma'; // 'diploma' | 'patent' | 'license' | 'card'

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _experienceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      // ── Submit Pro Registration ──
      // The pre-filled mock identity is gone, so the name must be validated:
      // an unnamed draft could never be reviewed (nor matched against the
      // future Supabase `professionals` row).
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context,
                fr: 'Veuillez indiquer votre nom complet.',
                ar: 'المرجو إدخال اسمك الكامل.')),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      // Proof of work / profession photo is MANDATORY — and now a REAL file:
      // a flag alone can never satisfy an admin review (nor a future Supabase
      // Storage upload), so the requirement is a picked path.
      final proof = _docPhotoPath;
      if (proof == null || proof.isEmpty) {
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

      // SUBMIT GUARD (CodeRabbit): a double-tap must never re-enter the
      // submission — the registry insert + token accounting would otherwise
      // double-book the same draft. The flag is released in the `finally`
      // below, so EVERY exit path (validation early-return, a thrown async
      // failure, or the success navigation) re-arms the button.
      if (_submitting) return;
      // setState (not a bare field write): the button's
      // `onPressed: _submitting ? null : _next` must ALSO disable VISUALLY, so
      // a fast double-tap lands on a dead button instead of a silent no-op.
      setState(() => _submitting = true);
      final committedEmail = _committedEmail;
      // Validate session identity before any mutation. Registration requires
      // both a resolved e-mail AND an existing credential record — otherwise
      // the draft is an orphan the admin panel could never match to an account.
      try {
        if (!mounted || committedEmail.isEmpty) {
          if (committedEmail.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr(context,
                    fr: "Session expirée : reconnectez-vous pour terminer l'inscription.",
                    ar: 'انتهت الجلسة: سجّل الدخول مجدداً لإكمال التسجيل.')),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
        if (!UserStore.hasCredentialRecord(email: committedEmail)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context,
                  fr: 'Aucun compte vérifié trouvé pour cet e-mail — reconnectez-vous.',
                  ar: 'لا يوجد حساب موثق لهذا البريد — سجّل الدخول مجدداً.')),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        // Contact phone: the real, session-bound value (trimmed) — or a plain
        // dash placeholder when the account has none yet. The fabricated
        // '+216 20 123 456' mock is gone: contact data will be OWNED by the
        // Supabase `professionals` row (profile completion) — this draft must
        // never invent it.
        final session = UserStore.user.value;
        final contactPhone = (session?.phone ?? '').trim();
        // Every wizard input is mapped into the submission payload — name,
        // category (profession), pricing, experience, governorate/city,
        // description text, document TYPE + photo, selfie, and the full
        // work-gallery selection — so nothing the pro entered is silently
        // dropped before admin review / backend sync.
        final experienceYears = int.tryParse(_experienceController.text.trim());
        final description = _descriptionController.text.trim();
        // AWAIT ACTIVE UPLOADS (CodeRabbit): the storage mirrors are
        // fire-and-forget — any upload still in flight has NOT populated
        // `_docRemotePath` / `_selfieRemotePath` / `_galleryRemotePaths` yet.
        // Waiting for every pending upload settles the remote handles BEFORE
        // the snapshot below is taken, so the dossier carries each capture's
        // durable path when one exists (never a raced null / stale path).
        if (_activeUploads.isNotEmpty) {
          await Future.wait(List<Future<void>>.of(_activeUploads));
        }
        // Snapshot the remote handles ALIGNED with the local gallery so the
        // registry payload carries a durable, admin-readable path per photo.
        // Uploads that never completed stay `null` (filtered out below) — the
        // payload must never carry a fabricated or mis-indexed URL.
        final galleryRemotePaths = <String?>[
          for (var i = 0; i < _galleryPhotos.length; i++)
            i < _galleryRemotePaths.length ? _galleryRemotePaths[i] : null,
        ];
        final newPro = PendingProModel(
          id: 'pro_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          phone: contactPhone.isEmpty ? '-' : contactPhone,
          email: committedEmail.isEmpty ? null : committedEmail,
          professionFr: _selectedCategory?.fr ?? 'Peintre',
          professionAr: _selectedCategory?.ar ?? 'دهّان',
          city: _city ?? _governorate,
          submittedAt:
              '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
          // The REAL proof picked in step 5 (absolute local path, or an asset
          // path for admin-seeded records). The hardcoded
          // 'assets/images/doc_placeholder.png' mock is gone: the admin must
          // review the document the professional actually submitted.
          docImage: proof,
          selfiePath: _selfiePhotoPath,
          status: 'pending',
          experienceYears: experienceYears,
          description: description.isEmpty ? null : description,
          docType: _docType,
          galleryPhotos: List.from(_galleryPhotos),
          // Remote Supabase Storage handles resolved from the uploads above:
          // durable paths an admin (on ANY device) resolves to a signed URL.
          // Nullable on purpose — an offline capture keeps only its local path.
          proofImagePath: _docRemotePath,
          selfieImagePath: _selfieRemotePath,
          galleryImagePaths: [
            for (final remote in galleryRemotePaths)
              if (remote != null && remote.isNotEmpty) remote,
          ],
          // Step-2 specialty chips are PERSISTED in the payload too (not just
          // mirrored into the session store): the admin reviews exactly the
          // services the pro declared, and the future Supabase row receives
          // the full bilingual list.
          specialtiesFr: [for (final s in _selectedSpecialties) s.fr],
          specialtiesAr: [for (final s in _selectedSpecialties) s.ar],
          pricingType: _pricingType,
          priceFrom: _pricingType == 'quote' ? null : _priceFrom,
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

        // Bind the professional identity to the local session, then land on
        // the verification gate (pending approval / WhatsApp inquiry).
        // The e-mail is re-bound explicitly from the immutable snapshot so a
        // session rebuild cannot drop the Email-OTP identity.
        await UserStore.set(
          name: registered.name,
          phone: registered.phone,
          email: committedEmail.isEmpty ? null : committedEmail,
          role: UserRole.professional,
          proCode: registered.proCode,
          proofPath: registered.docImage,
          selfiePath: registered.selfiePath,
          verificationStatus: ProVerification.pending,
        );
        if (!mounted) return;
        // AWAITED (CodeRabbit): `bindProAccount` persists the credential record
        // (and the proof/selfie snapshot) to SharedPreferences ASYNCHRONOUSLY.
        // The verification gate MUST only push AFTER the record is durable, or
        // a restart simulation would land on a screen whose state cannot
        // round-trip through prefs.
        await UserStore.bindProAccount(
          proCode: registered.proCode,
          verificationStatus: ProVerification.pending,
          proofPath: registered.docImage,
          selfiePath: registered.selfiePath,
        );
        // Surface the registration payload on the client-facing professional
        // model as well so the profile/feed show the real craft the pro picked
        // (verified pros map from the registry entry — see
        // ProfessionalsRepository.live).
        // NOTE: experience/description/work-gallery have no ProfessionalModel
        // slots yet — they travel with the registry payload (and the future
        // Supabase row) until the model grows matching fields.

        if (!mounted) return;
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
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VerificationGateScreen()),
        );
      } finally {
        // RE-ARM (CodeRabbit): NO exit path — a validation early-return, a
        // thrown async failure, or the success navigation — may leave the
        // submit button permanently disabled. `mounted`-guarded because the
        // success path may already have replaced (and disposed) this route.
        if (mounted) {
          setState(() => _submitting = false);
        } else {
          // Disposed State: nothing observes the flag anymore, but it is still
          // released so a stale closure can never see a held guard.
          _submitting = false;
        }
      }
    }
  }

  /// REAL photo capture for the work gallery (image_picker): the legacy
  /// `_addMockPhoto` pushed fabricated 'photo_1'/'photo_2' strings that never
  /// rendered anywhere. A picked photo is persisted to the durable `pro_media`
  /// folder (survives restarts) and its absolute path flows into
  /// [ProProfileStore.workImages] — ready for the Supabase Storage upload.
  Future<void> _pickWorkPhoto({required bool fromCamera}) async {
    final path = await DocumentMediaService.pickWorkPhoto(
      fromCamera: fromCamera,
    );
    if (path == null) return; // user cancelled / permission denied
    if (!mounted) return;
    setState(() => _galleryPhotos.add(path));
    // SUPABASE STORAGE MIRROR: gallery tiles land in the PRIVATE documents
    // bucket too (`<uid>/work_<ts>`) — the pro's portfolio becomes durable
    // backend data, not a device-only artifact.
    _mirrorDocumentToStorage(path, kind: 'work');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context,
            fr: 'Photo de réalisation ajoutée !', ar: 'تمت إضافة صورة العمل!')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// REAL proof-of-work capture (step 5). A failed or cancelled pick changes
  /// NOTHING — the old flow silently flipped a `_docUploaded` flag with no
  /// photo behind it, so an admin could receive a "verified-looking" dossier
  /// with no document at all.
  ///
  /// SUPABASE STORAGE MIRROR: after the durable local copy succeeds, the file
  /// is also pushed to the PRIVATE `documents` bucket (`<uid>/proof_<ts>`)
  /// so the backend/admin review owns a durable copy. Fire-and-forget and
  /// failure-tolerant: the local path stays the source of truth for the
  /// wizard UI and the registry payload — an offline capture simply lives
  /// local-only.
  Future<void> _pickProof({required bool fromCamera}) async {
    final path = await DocumentMediaService.pickDocument(
      fromCamera: fromCamera,
    );
    if (path == null) return;
    if (!mounted) return;
    setState(() {
      _docPhotoPath = path;
      // CAPTURE REPLACEMENT (CodeRabbit): the previous remote handle is STALE
      // the moment the local capture is replaced — clear it so the dossier
      // can never ship a URL belonging to the OLD photo. The upload mirrored
      // below re-correlates the NEW capture at this exact same slot.
      _docRemotePath = null;
    });
    _mirrorDocumentToStorage(path, kind: 'proof');
  }

  /// REAL selfie-with-document capture (recommended for fast review).
  /// Same storage mirroring contract as [_pickProof] (`<uid>/selfie_<ts>`).
  Future<void> _pickSelfie({required bool fromCamera}) async {
    final path = await DocumentMediaService.pickSelfieWithDocument(
      fromCamera: fromCamera,
    );
    if (path == null) return;
    if (!mounted) return;
    setState(() {
      _selfiePhotoPath = path;
      // CAPTURE REPLACEMENT (CodeRabbit): same stale-handle rule as
      // [_pickProof] — the slot is cleared first, then re-correlated by the
      // fresh upload below.
      _selfieRemotePath = null;
    });
    _mirrorDocumentToStorage(path, kind: 'selfie');
  }

  /// Fire-and-forget upload of a dossier capture to the PRIVATE `documents`
  /// bucket. Never blocks the wizard; failures are logged inside the service
  /// and the local file remains the operative copy. Every in-flight future is
  /// tracked in [_activeUploads] so the submit path can await them before it
  /// snapshots the remote handles (CodeRabbit).
  final List<Future<void>> _activeUploads = <Future<void>>[];

  void _mirrorDocumentToStorage(String localPath, {required String kind}) {
    // SECURE PREFIX (CodeRabbit): private-document paths MUST be namespaced
    // by the AUTHENTICATED Supabase user UUID when one exists — a device-side
    // local session id is only a fallback, never the preferred prefix.
    final uid = SupabaseAuthService.currentUserId ?? UserStore.user.value?.id;
    if (uid == null || uid.isEmpty) return;
    // SLOT CORRELATION (CodeRabbit): the gallery index is captured at UPLOAD
    // START — resolving it again at completion (after a delete/replace) could
    // attribute the upload to the WRONG tile.
    final galleryIdx = kind == 'work' ? _galleryPhotos.indexOf(localPath) : -1;
    // ACTIVE-CAPTURE CORRELATION (CodeRabbit): each new capture bumps its
    // channel's session token; a completion whose session has since been
    // replaced (the user re-took the proof/selfie while the previous upload
    // was still in flight) must NOT clobber the fresh slot with a stale
    // remote handle.
    final proofSession = kind == 'proof' ? ++_proofUploadSession : -1;
    final selfieSession = kind == 'selfie' ? ++_selfieUploadSession : -1;
    final future = SupabaseStorageService.uploadDocument(
      uid,
      File(localPath),
      kind: kind,
    ).then((String? remotePath) {
      if (remotePath == null || remotePath.isEmpty) return;
      if (!mounted) return;
      if (kind == 'proof') {
        if (proofSession == _proofUploadSession) _docRemotePath = remotePath;
      } else if (kind == 'selfie') {
        if (selfieSession == _selfieUploadSession) {
          _selfieRemotePath = remotePath;
        }
      } else if (kind == 'work' && galleryIdx >= 0) {
        // Guard the write: only THIS capture's slot may receive the handle —
        // if the tile was deleted/replaced mid-upload its slot moved or
        // changed and the stale result is discarded instead of mis-indexed.
        if (galleryIdx < _galleryPhotos.length &&
            _galleryPhotos[galleryIdx] == localPath) {
          // Grow-on-demand padding (CodeRabbit): the mirror list is lazily
          // sized — indexing it directly threw RangeError on the FIRST
          // upload and silently dropped every remote work-gallery handle.
          while (_galleryRemotePaths.length <= galleryIdx) {
            _galleryRemotePaths.add(null);
          }
          _galleryRemotePaths[galleryIdx] = remotePath;
        }
      }
    }, onError: (Object e, StackTrace st) {
      // Failures are logged inside the service — the local path remains
      // the operative copy, so the wizard never aborts for a network blip.
      debugPrint('ProRegistrationScreen._mirrorDocumentToStorage '
          '($kind) failed: $e');
    });
    _activeUploads.add(future);
    // The future never errors (onError above), so the bookkeeping continuation
    // is safe to fire-and-forget.
    unawaited(future.whenComplete(() => _activeUploads.remove(future)));
  }

  /// Remote Supabase Storage paths resolved from the uploads above, kept
  /// alongside the local paths so the registry payload carries durable,
  /// admin-readable handles (not just device-local artifacts).
  String? _docRemotePath;
  String? _selfieRemotePath;

  /// Capture-session tokens for the proof/selfie upload channels: bumped on
  /// every new capture so a stale in-flight upload can never overwrite the
  /// fresh capture's remote handle (CodeRabbit).
  int _proofUploadSession = 0;
  int _selfieUploadSession = 0;
  // Padded to match `_galleryPhotos` length at read time (index lookup above).
  final List<String?> _galleryRemotePaths = [];

  /// Source chooser shared by the three capture surfaces: a bottom sheet
  /// offering camera & gallery (the same two sources the chat uses).
  void _chooseSource(void Function({required bool fromCamera}) pick) {
    showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(
                  tr(sheetContext, fr: 'Prendre une photo', ar: 'التقاط صورة')),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(tr(sheetContext,
                  fr: 'Choisir dans la galerie', ar: 'اختيار من المعرض')),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
          ],
        ),
      ),
    ).then((String? source) {
      if (source == 'camera') pick(fromCamera: true);
      if (source == 'gallery') pick(fromCamera: false);
    });
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
      resizeToAvoidBottomInset: true,
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
                            onTap: () => _chooseSource(_pickWorkPhoto),
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
                                              const EdgeInsetsDirectional.only(
                                                  end: 8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySurface,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Stack(
                                            children: [
                                              // The REAL picked photo
                                              // (overflow-proof tile), with
                                              // the old icon-only placeholder
                                              // as its error fallback.
                                              Positioned.fill(
                                                child: AppImage(
                                                  _galleryPhotos[index],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  fit: BoxFit.cover,
                                                  errorIcon:
                                                      Icons.image_outlined,
                                                ),
                                              ),
                                              Positioned(
                                                top: 2,
                                                right: 2,
                                                child: GestureDetector(
                                                  // INDEX-ALIGNED DELETE (CodeRabbit):
                                                  // `_galleryRemotePaths` is padded in
                                                  // parallel with `_galleryPhotos` (see
                                                  // `_mirrorDocumentToStorage`), so dropping
                                                  // a tile MUST drop the entry at the very
                                                  // same index — otherwise every later
                                                  // upload is attributed to the WRONG photo
                                                  // and a stale remote path ships in the
                                                  // dossier.
                                                  onTap: () => setState(() {
                                                    _galleryPhotos
                                                        .removeAt(index);
                                                    if (index <
                                                        _galleryRemotePaths
                                                            .length) {
                                                      _galleryRemotePaths
                                                          .removeAt(index);
                                                    }
                                                  }),
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
                        // REAL capture: camera or gallery. Nothing is marked
                        // "uploaded" unless a photo actually came back.
                        onTap: () => _chooseSource(_pickProof),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 130,
                          decoration: BoxDecoration(
                            color: _docPhotoPath != null
                                ? AppColors.success.withValues(alpha: 0.08)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _docPhotoPath != null
                                  ? AppColors.success
                                  : AppColors.primary,
                              width: 1.5,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: _docPhotoPath != null
                              ? Row(
                                  children: [
                                    // The REAL document photo, clipped and
                                    // covered inside a bounded tile.
                                    SizedBox(
                                      width: 110,
                                      height: 130,
                                      child: AppImage(
                                        _docPhotoPath!,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(14.5),
                                          bottomLeft: Radius.circular(14.5),
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.check_circle_rounded,
                                              color: AppColors.success,
                                              size: 32),
                                          const SizedBox(height: 6),
                                          Text(
                                            tr(context,
                                                fr: 'Document ajouté ✓',
                                                ar: 'تمت إضافة الوثيقة ✓'),
                                            style: const TextStyle(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _chooseSource(_pickProof),
                                            child: Text(
                                              tr(context,
                                                  fr: 'Changer', ar: 'تغيير'),
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        ],
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
                        // REAL capture: the selfie is a real photo (camera
                        // first, gallery as fallback), never a silent flag.
                        onTap: () => _chooseSource(_pickSelfie),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: double.infinity,
                          height: 130,
                          decoration: BoxDecoration(
                            color: _selfiePhotoPath != null
                                ? AppColors.success.withValues(alpha: 0.08)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _selfiePhotoPath != null
                                  ? AppColors.success
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                          child: _selfiePhotoPath != null
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 110,
                                      height: 130,
                                      child: AppImage(
                                        _selfiePhotoPath!,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(14.5),
                                          bottomLeft: Radius.circular(14.5),
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.check_circle_rounded,
                                              color: AppColors.success,
                                              size: 32),
                                          const SizedBox(height: 6),
                                          Text(
                                            tr(context,
                                                fr: 'Selfie ajouté ✓',
                                                ar: 'تمت إضافة الصورة ✓'),
                                            style: const TextStyle(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _chooseSource(_pickSelfie),
                                            child: Text(
                                              tr(context,
                                                  fr: 'Changer', ar: 'تغيير'),
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        ],
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
                    onPressed: _submitting ? null : _next,
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
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
