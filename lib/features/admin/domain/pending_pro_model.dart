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
  final String? badge;

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
    );
  }
}
