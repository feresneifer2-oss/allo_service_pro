import 'package:flutter/foundation.dart';

@immutable
class PendingProModel {
  const PendingProModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.professionFr,
    required this.professionAr,
    this.city,
    required this.submittedAt,
    this.docImage,
    required this.status,
    this.badge,
    this.proCode,
    this.tokens = 0,
    this.isPaid = false,
    this.rejectionReason,
    this.badges = const [],
  });

  final String id;
  final String name;
  final String phone;
  final String professionFr;
  final String professionAr;
  final String? city;
  final String submittedAt;
  final String? docImage;
  final String status;

  /// Legacy single badge (kept for old callers); prefer [badges].
  final String? badge;

  /// Unique public identifier: PRO-XXXXX.
  final String? proCode;
  final int tokens;
  final bool isPaid;
  final String? rejectionReason;
  final List<String> badges;

  PendingProModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? professionFr,
    String? professionAr,
    String? city,
    String? submittedAt,
    String? docImage,
    String? status,
    String? badge,
    String? proCode,
    int? tokens,
    bool? isPaid,
    String? rejectionReason,
    List<String>? badges,
  }) {
    return PendingProModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      professionFr: professionFr ?? this.professionFr,
      professionAr: professionAr ?? this.professionAr,
      city: city ?? this.city,
      submittedAt: submittedAt ?? this.submittedAt,
      docImage: docImage ?? this.docImage,
      status: status ?? this.status,
      badge: badge ?? this.badge,
      proCode: proCode ?? this.proCode,
      tokens: tokens ?? this.tokens,
      isPaid: isPaid ?? this.isPaid,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      badges: badges ?? this.badges,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phone': phone,
        'professionFr': professionFr,
        'professionAr': professionAr,
        'city': city,
        'submittedAt': submittedAt,
        'docImage': docImage,
        'status': status,
        'badge': badge,
        'proCode': proCode,
        'tokens': tokens,
        'isPaid': isPaid,
        'rejectionReason': rejectionReason,
        'badges': badges,
      };

  factory PendingProModel.fromJson(Map<String, dynamic> json) =>
      PendingProModel(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        professionFr: json['professionFr'] as String,
        professionAr: json['professionAr'] as String,
        city: json['city'] as String?,
        submittedAt: json['submittedAt'] as String,
        docImage: json['docImage'] as String?,
        status: json['status'] as String,
        badge: json['badge'] as String?,
        proCode: json['proCode'] as String?,
        tokens: (json['tokens'] as num?)?.toInt() ?? 0,
        isPaid: (json['isPaid'] as bool?) ?? false,
        rejectionReason: json['rejectionReason'] as String?,
        badges: [
          for (final b in (json['badges'] as List? ?? [])) b as String,
        ],
      );
}
