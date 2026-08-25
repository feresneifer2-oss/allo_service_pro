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

  /// Enterprise rule: a conversation closes automatically 4 days (96h)
  /// after acceptance — input is disabled and an inline notice shows.
  bool get isAutoClosed => DateTime.now().isAfter(expiresAt);

  /// Whole hours remaining before the automatic closure.
  int get hoursUntilAutoClose {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? 0 : d.inHours;
  }

  /// Whole minutes remaining (used for the final-hour countdown).
  int get minutesUntilAutoClose {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? 0 : d.inMinutes;
  }
}
