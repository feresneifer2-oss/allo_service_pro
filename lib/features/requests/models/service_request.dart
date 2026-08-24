import '../../../core/models/request_status.dart';

class ServiceRequest {
  final String id;
  final String serviceTitleFr;
  final String serviceTitleAr;
  final String professionalId;
  final String professionalName;
  final String customerName;
  final String customerId;
  final DateTime dateTime;
  final String address;
  final String message;
  final List<String> photoPaths;
  final RequestStatus status;
  final double? rating;
  final String? reviewComment;
  final DateTime createdAt;

  const ServiceRequest({
    required this.id,
    required this.serviceTitleFr,
    required this.serviceTitleAr,
    required this.professionalId,
    required this.professionalName,
    required this.customerName,
    this.customerId = '',
    required this.dateTime,
    required this.address,
    required this.message,
    this.photoPaths = const [],
    this.status = RequestStatus.pending,
    this.rating,
    this.reviewComment,
    required this.createdAt,
  });

  ServiceRequest copyWith({
    RequestStatus? status,
    double? rating,
    String? reviewComment,
  }) {
    return ServiceRequest(
      id: id,
      serviceTitleFr: serviceTitleFr,
      serviceTitleAr: serviceTitleAr,
      professionalId: professionalId,
      professionalName: professionalName,
      customerName: customerName,
      customerId: customerId,
      dateTime: dateTime,
      address: address,
      message: message,
      photoPaths: photoPaths,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      reviewComment: reviewComment ?? this.reviewComment,
      createdAt: createdAt,
    );
  }
}
