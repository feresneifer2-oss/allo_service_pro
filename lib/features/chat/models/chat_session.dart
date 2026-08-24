/// Lifecycle state of a request-bound chat room.
enum ChatStatus { active, closed }

/// Why a chat room is unavailable right now (drives UI messaging).
enum ChatClosureReason { none, adminClosed, expired }

/// A chat room opens when an order is confirmed (10 tokens deducted) and
/// stays open for [expiryHours] hours — unless the admin closes it earlier.
class ChatSession {
  final String requestId;
  final bool active;
  final DateTime activatedAt;
  final DateTime? closedAt;
  final int expiryHours;

  const ChatSession({
    required this.requestId,
    this.active = true,
    required this.activatedAt,
    this.closedAt,
    this.expiryHours = 48,
  });

  DateTime get expiresAt => activatedAt.add(Duration(hours: expiryHours));

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
