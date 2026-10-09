import '../../../core/models/request_status.dart';

class ServiceRequest {
  final String id;
  final String serviceTitleFr;
  final String serviceTitleAr;
  final String professionalId;

  /// Supabase Auth UUID of the professional this order is assigned to — the
  /// `ProfessionalModel.authUid` captured from the SAME pro identified by
  /// [professionalId] at creation time (Phase 3K, local booking flow).
  ///
  /// [professionalId] stays the display/routing id (`PRO-XXXXX` / `pro_N`);
  /// this field IS the server identity bound to `orders.pro_id` (Phase 3L).
  /// Nullable by design:
  ///   • `null` → curated mock catalog pros (their `authUid` has always been
  ///     null) or an id the registry does not know — `toRow` still emits the
  ///     key and `OrdersRepository.insertOrderDetailed` refuses the write
  ///     BEFORE any network round-trip (a null uid can never satisfy the
  ///     uuid `pro_id` column, and nothing is derived from `professionalId`);
  ///   • never displayed, never used for routing.
  /// On the wire it travels as `pro_id` (see `OrdersRepository.toRow`), so a
  /// queued payload or hydrated row round-trips it like any other column.
  final String? professionalAuthUid;
  final String professionalName;
  final String customerName;
  final String customerId;
  final DateTime dateTime;
  final String address;
  final String message;

  /// Payment method chosen by the client at checkout: 'cash' | 'd17' |
  /// 'flouci'. No gateway — the pro collects the payment directly; the
  /// choice is recorded on the order (and surfaced in chat if needed).
  final String paymentMethod;
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
    this.professionalAuthUid,
    required this.professionalName,
    required this.customerName,
    this.customerId = '',
    required this.dateTime,
    required this.address,
    required this.message,
    this.paymentMethod = 'cash',
    this.photoPaths = const [],
    this.status = RequestStatus.pending,
    this.rating,
    this.reviewComment,
    required this.createdAt,
  });

  ServiceRequest copyWith({
    /// RE-KEYING SEAM (CodeRabbit): an offline creation whose id already exists
    /// on the backend is re-keyed with a fresh client UUID and retried. Every
    /// other field is carried over verbatim, so the re-keyed order stays the
    /// SAME logical order for the client, the pro and the admin.
    String? id,
    RequestStatus? status,
    double? rating,
    String? reviewComment,
    String? paymentMethod,

    /// Phase 3K: carried verbatim (like `professionalId`) so the re-key
    /// seam and every status/rating patch keep the captured identity. A
    /// non-null argument wins over the stored value — used by the remote
    /// merges in `RequestStore` to INHERIT the local uid into a wire-built
    /// row that cannot carry one yet. Passing `null` never clears it.
    String? professionalAuthUid,
  }) {
    return ServiceRequest(
      id: id ?? this.id,
      serviceTitleFr: serviceTitleFr,
      serviceTitleAr: serviceTitleAr,
      professionalId: professionalId,
      professionalAuthUid: professionalAuthUid ?? this.professionalAuthUid,
      professionalName: professionalName,
      customerName: customerName,
      customerId: customerId,
      dateTime: dateTime,
      address: address,
      message: message,
      photoPaths: photoPaths,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      reviewComment: reviewComment ?? this.reviewComment,
      createdAt: createdAt,
    );
  }
}
