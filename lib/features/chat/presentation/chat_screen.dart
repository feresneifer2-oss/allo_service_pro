import 'dart:async';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/data/chat_media_service.dart';
import 'package:allo_service_pro/features/chat/models/chat_message.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/chat/presentation/widgets/media_bubbles.dart';
import 'package:allo_service_pro/features/chat/presentation/widgets/voice_note_player.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.requestId, this.isCustomer});

  final String requestId;

  /// Viewer role. Null → inferred from the active session (UserStore).
  final bool? isCustomer;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  Timer? _recTimer;
  int _recSeconds = 0;
  bool _isRecording = false;

  /// Client vs pro viewer — drives bubble mirroring & sender identity.
  bool get _viewerIsCustomer =>
      widget.isCustomer ??
      !(UserStore.user.value?.isProfessional ?? false);

  @override
  void initState() {
    super.initState();
    VoiceNotePlayer.warmUp();
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _send({required bool isCustomer}) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    ChatStore.send(
      requestId: widget.requestId,
      senderId: isCustomer ? 'customer' : 'pro',
      senderName: isCustomer ? request.customerName : request.professionalName,
      text: text,
      isCustomer: isCustomer,
    );
    _controller.clear();
  }

  void _sendVoice() async {
    final isCustomer = _viewerIsCustomer;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    final (path, seconds) = await ChatMediaService.stopVoiceRecording();
    _recTimer?.cancel();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              fr: 'Enregistrement indisponible', ar: 'تعذّر التسجيل الصوتي')),
        ));
      }
      return;
    }
    ChatStore.sendVoice(
      requestId: widget.requestId,
      senderId: isCustomer ? 'customer' : 'pro',
      senderName: isCustomer ? request.customerName : request.professionalName,
      filePath: path,
      durationSec: seconds,
      isCustomer: isCustomer,
    );
  }

  void _startRecording() async {
    final ok = await ChatMediaService.startVoiceRecording();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              fr: 'Microphone indisponible', ar: 'الميكروفون غير متاح')),
        ));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recSeconds = 0;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSeconds++);
      });
    });
  }

  void _cancelRecording() async {
    _recTimer?.cancel();
    await ChatMediaService.cancelVoiceRecording();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recSeconds = 0;
      });
    }
  }

  void _attachPhoto() async {
    final isCustomer = _viewerIsCustomer;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    if (!mounted) return;
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: Text(tr(sheetCtx, fr: 'Galerie', ar: 'المعرض')),
              onTap: () => Navigator.pop(sheetCtx, false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary),
              title: Text(tr(sheetCtx, fr: 'Caméra', ar: 'الكاميرا')),
              onTap: () => Navigator.pop(sheetCtx, true),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null) return;
    final path = await ChatMediaService.pickPhoto(fromCamera: fromCamera);
    if (path == null) return;
    ChatStore.sendPhoto(
      requestId: widget.requestId,
      senderId: isCustomer ? 'customer' : 'pro',
      senderName: isCustomer ? request.customerName : request.professionalName,
      filePath: path,
      isCustomer: isCustomer,
    );
  }

  @override
  Widget build(BuildContext context) {
    // React live to admin closures / expiry / status changes.
    return ValueListenableBuilder<Map<String, ChatSession>>(
      valueListenable: ChatStore.sessions,
      builder: (_, __, ___) =>
          ValueListenableBuilder<Map<String, List<ChatMessage>>>(
        valueListenable: ChatStore.messages,
        builder: (_, __, ___) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final request = RequestStore.byId(widget.requestId);

    // Check if chat is allowed
    if (request == null || !RequestStore.isChatAllowed(widget.requestId)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(tr(context, fr: 'Chat', ar: 'محادثة'),
              style: const TextStyle(fontSize: 18)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded,
                  color: AppColors.textSecondary, size: 48),
              const SizedBox(height: 12),
              Text(
                _lockedTitle(context, request?.status),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (request?.status == RequestStatus.pending) ...[
                const SizedBox(height: 8),
                Text(
                  tr(context,
                      fr: 'Le professionnel doit accepter la demande pour activer le chat',
                      ar: 'يجب على الحرفي قبول الطلب لتفعيل المحادثة'),
                  style:
                      const TextStyle(color: AppColors.slate400, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    final header =
        '${tr(context, fr: request.serviceTitleFr, ar: request.serviceTitleAr)} — ${request.dateTime.day}/${request.dateTime.month} — ${request.dateTime.hour}:${request.dateTime.minute.toString().padLeft(2, '0')}';

    final msgs = ChatStore.forRequest(widget.requestId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, fr: 'Chat', ar: 'محادثة'),
                style: const TextStyle(fontSize: 18)),
            if (header.isNotEmpty)
              Text(header,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          // ⏳ Auto-close countdown (4 days after acceptance).
          Builder(
            builder: (_) {
              final session = ChatStore.sessionOf(widget.requestId);
              if (session == null || !session.active) {
                return const SizedBox.shrink();
              }
              final hours = session.hoursUntilAutoClose;
              final minutes = session.minutesUntilAutoClose;
              final countdown = hours >= 1
                  ? tr(context,
                      fr: 'Fermeture auto dans $hours h',
                      ar: 'الإغلاق التلقائي بعد $hours ساعة')
                  : tr(context,
                      fr: 'Fermeture auto dans $minutes min',
                      ar: 'بقت $minutes دقيقة على الإغلاق');
              return Container(
                width: double.infinity,
                color: AppColors.primarySurface,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '⏳ $countdown',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              );
            },
          ),
          Expanded(
            // Le seul abonnement à ChatStore.messages est celui de build() ;
            // cette liste lit simplement l'instantané courant à chaque
            // rebuild (pas d'écoute dupliquée).
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final isMe = m.isCustomer == _viewerIsCustomer;
                if (m.hasMedia) {
                  return Align(
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ChatMediaBubble(message: m, isMine: isMe),
                  );
                }
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .75),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                          color: isMe ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!RequestStore.isChatAllowed(widget.requestId)) ...[
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_rounded, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(context,
                          fr:
                              "Cette conversation s'est fermée automatiquement après 4 jours.",
                          ar: 'هذه المحادثة مغلقة تلقائياً بعد مرور 4 أيام'),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ] else
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: _isRecording
                ? Row(
                    children: [
                      const Icon(Icons.radio_button_checked_rounded,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$_recSeconds s',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      TextButton(
                        onPressed: _cancelRecording,
                        child: Text(tr(context,
                            fr: 'Annuler', ar: 'إلغاء')),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _sendVoice,
                        customBorder: const CircleBorder(),
                        child: const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.secondary,
                          child: Icon(Icons.send_rounded,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) =>
                              _send(isCustomer: _viewerIsCustomer),
                          decoration: InputDecoration(
                            hintText: tr(context,
                                fr: 'Votre message...', ar: 'رسالتك...'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _attachPhoto,
                        customBorder: const CircleBorder(),
                        child: const CircleAvatar(
                          radius: 19,
                          backgroundColor: AppColors.primarySurface,
                          child: Icon(Icons.add_photo_alternate_outlined,
                              size: 20, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _startRecording,
                        customBorder: const CircleBorder(),
                        child: const CircleAvatar(
                          radius: 19,
                          backgroundColor: AppColors.primarySurface,
                          child: Icon(Icons.mic_none_rounded,
                              size: 20, color: AppColors.secondary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _send(isCustomer: _viewerIsCustomer),
                        customBorder: const CircleBorder(),
                        child: const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.send_rounded,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _lockedTitle(BuildContext context, RequestStatus? status) {
    switch (ChatStore.closureStateOf(widget.requestId)) {
      case ChatClosureReason.adminClosed:
        return tr(context,
            fr: "Conversation clôturée par l'administration.",
            ar: 'أغلق الإدارة هذه المحادثة.');
      case ChatClosureReason.expired:
        return tr(context,
            fr: 'Fenêtre de chat expirée — confirmez à nouveau pour discuter.',
            ar: 'انتهت مدة المحادثة — أكّد الطلب من جديد للمحادثة.');
      case ChatClosureReason.none:
        break;
    }
    return status == RequestStatus.pending
        ? tr(context, fr: "En attente d'acceptation", ar: 'في انتظار القبول')
        : tr(context, fr: 'Chat non disponible', ar: 'المحادثة غير متاحة');
  }
}
