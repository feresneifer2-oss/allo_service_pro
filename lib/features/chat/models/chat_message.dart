/// Kind of content carried by a chat message.
enum ChatMessageType { text, voice, photo }

class ChatMessage {
  final String id;
  final String requestId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool isCustomer;

  /// Rich-media extension: voice notes & photos. Both roles (client & pro)
  /// send AND receive these identically — only the bubble side mirrors.
  final ChatMessageType type;

  /// Local file path for [ChatMessageType.voice] and [ChatMessageType.photo].
  final String? mediaPath;

  /// Recorded duration in seconds (voice notes only; 0 otherwise).
  final int voiceDurationSec;

  const ChatMessage({
    required this.id,
    required this.requestId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    required this.isCustomer,
    this.type = ChatMessageType.text,
    this.mediaPath,
    this.voiceDurationSec = 0,
  });

  bool get isVoice => type == ChatMessageType.voice;
  bool get isPhoto => type == ChatMessageType.photo;
  bool get isText => type == ChatMessageType.text;
  bool get hasMedia => type != ChatMessageType.text;
}
