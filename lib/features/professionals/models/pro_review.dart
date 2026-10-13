import 'package:flutter/foundation.dart';

/// Phase 4E: one individual review for a professional.
/// Read from the RPC list_pro_reviews(pro_id).
@immutable
class ProReview {
  const ProReview({
    required this.orderId,
    required this.clientName,
    required this.rating,
    this.reviewComment,
    required this.createdAt,
  });

  final String orderId;
  final String clientName;
  final double rating;
  final String? reviewComment;
  final DateTime createdAt;

  /// Tolerant decode from the RPC row.
  static ProReview? fromRow(Map<String, dynamic> row) {
    final orderId = (row['order_id'] as String?)?.trim() ?? '';
    if (orderId.isEmpty) return null;
    final ratingRaw = row['rating'];
    final rating = ratingRaw is num ? ratingRaw.toDouble() : null;
    if (rating == null) return null;
    final clientName = (row['client_name'] as String?)?.trim() ?? 'Client';
    final comment = (row['review_comment'] as String?)?.trim();
    final createdRaw = row['created_at'];
    final createdAt = createdRaw is String
        ? DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    return ProReview(
      orderId: orderId,
      clientName: clientName.isEmpty ? 'Client' : clientName,
      rating: rating,
      reviewComment: (comment != null && comment.isNotEmpty) ? comment : null,
      createdAt: createdAt,
    );
  }
}
