import 'package:flutter/foundation.dart';

@immutable
class PendingProModel {
  const PendingProModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.professionFr,
    required this.professionAr,
    this.city,
    required this.submittedAt,
    this.docImage,
    this.selfiePath,
    required this.status,
    this.badge,
    this.proCode,
    this.tokens = 0,
    this.isPaid = false,
    this.paidUntilMs,
    this.rejectionReason,
    this.badges = const [],
    this.deactivated = false,
    this.adminMessages = const [],
    // Registration payload (bound from the pro registration wizard so the
    // admin reviews exactly what the pro entered — no silent drops).
    this.experienceYears,
    this.description,
    this.docType,
    this.galleryPhotos = const [],
    // Remote Supabase Storage paths captured on upload (CodeRabbit: previously
    // the upload result was fire-and-forgotten, so the remote handle was
    // discarded and the dossier kept only the ephemeral local path —
    // unreadable by admin or any other device). The local path still drives
    // the in-wizard preview; these remote paths are the durable handles an
    // admin resolves to a signed URL for cross-device review.
    this.proofImagePath,
    this.selfieImagePath,
    this.galleryImagePaths = const [],
    this.specialtiesFr = const [],
    this.specialtiesAr = const [],
    // Pricing entry (wizard step 3): mirrors the pro's pricing mode + floor
    // price so the payload — and the client feed — never fall back to a
    // hardcoded default.
    this.pricingType,
    this.priceFrom,
  });

  final String id;
  final String name;
  final String phone;

  /// Authentication e-mail of the pro (Email-OTP identity). Optional so
  /// legacy / admin-seeded records stay valid; admin approval syncs the
  /// credential record through it.
  final String? email;
  final String professionFr;
  final String professionAr;
  final String? city;
  final String submittedAt;
  final String? docImage;
  final String? selfiePath;
  final String status;

  /// Legacy single badge (kept for old callers); prefer [badges].
  final String? badge;

  /// Unique public identifier: PRO-XXXXX.
  final String? proCode;
  final int tokens;
  final bool isPaid;

  /// Expiration timestamp (ms epoch) of the pro's 30-day paid cycle —
  /// per-pro source of truth so session sync NEVER extends it.
  final int? paidUntilMs;
  final String? rejectionReason;
  final List<String> badges;

  /// Years of experience entered on the registration wizard (step 3).
  final int? experienceYears;

  /// Free-text service description entered on the wizard (step 4).
  final String? description;

  /// Document kind selected on the wizard (diploma | patent | license | card).
  final String? docType;

  /// Work-gallery photo paths picked on the wizard (step 4).
  final List<String> galleryPhotos;

  /// Max entries persisted per gallery (Qodo): bounds the SharedPreferences
  /// payload so a runaway list can never balloon local storage.
  static const int kMaxGalleryPaths = 24;
  static const int kMaxAdminMessages = 50;

  /// Tolerant string-list decode for legacy/foreign JSON payloads: skips
  /// nulls/empty entries, coerces every element via `toString`, and caps the
  /// result at [max] entries — a corrupt or legacy record can never crash
  /// the registry load path.
  static List<String> _stringList(
    Object? raw,
    int max, {
    bool keepNewest = false,
  }) {
    if (raw is! List) return const <String>[];
    final out = <String>[
      for (final item in raw)
        if (item != null && item.toString().trim().isNotEmpty) item.toString(),
    ];
    if (out.length <= max) return out;
    // NEWEST-FIRST CAPPING (CodeRabbit): admin messages are appended
    // chronologically (newest LAST), so the cap must preserve the TAIL of
    // the list — dropping from the head would silently discard the newest
    // messages and keep only obsolete ones.
    return keepNewest ? out.sublist(out.length - max) : out.sublist(0, max);
  }

  /// Remote Supabase Storage paths of the proof / selfie / work-gallery
  /// captures, captured when the upload succeeds (CodeRabbit: previously the
  /// upload return value was discarded, so the remote handle was lost and the
  /// dossier kept only the ephemeral local path). The local [docImage] path is
  /// still the source of truth for the wizard preview; these remote paths are
  /// the durable handles an admin resolves (via a signed URL) for review on a
  /// different device.
  final String? proofImagePath;
  final String? selfieImagePath;
  final List<String> galleryImagePaths;

  /// Specialty/service labels picked on the wizard (step 2), in BOTH
  /// languages — persisted verbatim so admin review and the client feed
  /// show exactly the services the pro declared.
  final List<String> specialtiesFr;
  final List<String> specialtiesAr;

  /// Pricing mode selected on the wizard (fixed | hourly | quote).
  final String? pricingType;

  /// Indicative floor price (DT) selected on the wizard (step 3).
  final int? priceFrom;

  /// Admin-controlled deactivation: a deactivated pro loses dashboard
  /// access (no orders / chat) and disappears from client listings.
  final bool deactivated;

  /// Two-way verification thread ("AlloService|text" / "pro|text").
  final List<String> adminMessages;

  static const Object _unset = Object();

  PendingProModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? professionFr,
    String? professionAr,
    String? city,
    String? submittedAt,
    Object? docImage = _unset,
    Object? selfiePath = _unset,
    String? status,
    String? badge,
    String? proCode,
    int? tokens,
    bool? isPaid,
    Object? paidUntilMs = _unset,
    Object? rejectionReason = _unset,
    List<String>? badges,
    bool? deactivated,
    List<String>? adminMessages,
    int? experienceYears,
    String? description,
    String? docType,
    List<String>? galleryPhotos,
    String? proofImagePath,
    String? selfieImagePath,
    List<String>? galleryImagePaths,
    List<String>? specialtiesFr,
    List<String>? specialtiesAr,
    String? pricingType,
    int? priceFrom,
  }) {
    return PendingProModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      professionFr: professionFr ?? this.professionFr,
      professionAr: professionAr ?? this.professionAr,
      city: city ?? this.city,
      submittedAt: submittedAt ?? this.submittedAt,
      docImage:
          identical(docImage, _unset) ? this.docImage : docImage as String?,
      selfiePath: identical(selfiePath, _unset)
          ? this.selfiePath
          : selfiePath as String?,
      status: status ?? this.status,
      badge: badge ?? this.badge,
      proCode: proCode ?? this.proCode,
      tokens: tokens ?? this.tokens,
      isPaid: isPaid ?? this.isPaid,
      paidUntilMs: identical(paidUntilMs, _unset)
          ? this.paidUntilMs
          : paidUntilMs as int?,
      rejectionReason: identical(rejectionReason, _unset)
          ? this.rejectionReason
          : rejectionReason as String?,
      badges: badges ?? this.badges,
      deactivated: deactivated ?? this.deactivated,
      adminMessages: adminMessages ?? this.adminMessages,
      experienceYears: experienceYears ?? this.experienceYears,
      description: description ?? this.description,
      docType: docType ?? this.docType,
      galleryPhotos: galleryPhotos ?? this.galleryPhotos,
      proofImagePath: proofImagePath ?? this.proofImagePath,
      selfieImagePath: selfieImagePath ?? this.selfieImagePath,
      galleryImagePaths: galleryImagePaths ?? this.galleryImagePaths,
      specialtiesFr: specialtiesFr ?? this.specialtiesFr,
      specialtiesAr: specialtiesAr ?? this.specialtiesAr,
      pricingType: pricingType ?? this.pricingType,
      priceFrom: priceFrom ?? this.priceFrom,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'professionFr': professionFr,
        'professionAr': professionAr,
        'city': city,
        'submittedAt': submittedAt,
        'docImage': docImage,
        'selfiePath': selfiePath,
        'status': status,
        'badge': badge,
        'proCode': proCode,
        'tokens': tokens,
        'isPaid': isPaid,
        'paidUntilMs': paidUntilMs,
        'rejectionReason': rejectionReason,
        'badges': badges,
        'deactivated': deactivated,
        'adminMessages': adminMessages,
        'experienceYears': experienceYears,
        'description': description,
        'docType': docType,
        'galleryPhotos': galleryPhotos,
        'proofImagePath': proofImagePath,
        'selfieImagePath': selfieImagePath,
        'galleryImagePaths': galleryImagePaths,
        'specialtiesFr': specialtiesFr,
        'specialtiesAr': specialtiesAr,
        'pricingType': pricingType,
        'priceFrom': priceFrom,
      };

  factory PendingProModel.fromJson(Map<String, dynamic> json) =>
      PendingProModel(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        email: json['email'] as String?,
        professionFr: json['professionFr'] as String,
        professionAr: json['professionAr'] as String,
        city: json['city'] as String?,
        submittedAt: json['submittedAt'] as String,
        docImage: json['docImage'] as String?,
        selfiePath: json['selfiePath'] as String?,
        status: json['status'] as String,
        badge: json['badge'] as String?,
        proCode: json['proCode'] as String?,
        tokens: (json['tokens'] as num?)?.toInt() ?? 0,
        isPaid: (json['isPaid'] as bool?) ?? false,
        paidUntilMs: (json['paidUntilMs'] as num?)?.toInt(),
        rejectionReason: json['rejectionReason'] as String?,
        badges: [
          for (final b in (json['badges'] as List? ?? [])) b as String,
        ],
        deactivated: (json['deactivated'] as bool?) ?? false,
        // NEWEST-FIRST cap (CodeRabbit): messages arrive chronologically —
        // the cap must keep the newest ones, never the oldest.
        adminMessages: _stringList(
          json['adminMessages'],
          kMaxAdminMessages,
          keepNewest: true,
        ),
        experienceYears: (json['experienceYears'] as num?)?.toInt(),
        description: json['description'] as String?,
        docType: json['docType'] as String?,
        // DEFENSIVE SCHEMA FALLBACK (Qodo): legacy payloads may carry nulls
        // or non-string entries; never crash the registry load on them.
        galleryPhotos: _stringList(json['galleryPhotos'], kMaxGalleryPaths),
        proofImagePath: json['proofImagePath'] as String?,
        selfieImagePath: json['selfieImagePath'] as String?,
        galleryImagePaths:
            _stringList(json['galleryImagePaths'], kMaxGalleryPaths),
        specialtiesFr: [
          for (final s in (json['specialtiesFr'] as List? ?? [])) s as String,
        ],
        specialtiesAr: [
          for (final s in (json['specialtiesAr'] as List? ?? [])) s as String,
        ],
        pricingType: json['pricingType'] as String?,
        priceFrom: (json['priceFrom'] as num?)?.toInt(),
      );
}
