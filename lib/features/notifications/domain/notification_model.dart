class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type; // 'request', 'chat', 'system'

  /// Account the notification is addressed to (used for audit/debug).
  final String recipientId;

  /// Strict role routing: 'client' | 'professional'. Clients NEVER see
  /// professional-targeted notifications and vice-versa (enforced by
  /// [NotificationStore.getNotificationsForUser]).
  final String targetRole;
  final String? requestId;
  final DateTime createdAt;
  final bool isRead;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.recipientId,
    this.targetRole = 'client',
    this.requestId,
    required this.createdAt,
    this.isRead = false,
  });

  NotificationModel copyWith({
    String? id,
    String? title,
    String? message,
    String? type,
    String? recipientId,
    String? targetRole,
    String? requestId,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      recipientId: recipientId ?? this.recipientId,
      targetRole: targetRole ?? this.targetRole,
      requestId: requestId ?? this.requestId,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
