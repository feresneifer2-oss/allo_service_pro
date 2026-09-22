import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  Timer? _recTimer;
  Timer? _countdownTimer;
  int _recSeconds = 0;
  bool _isRecording = false;

  /// VOICE LIFECYCLE GUARD (CodeRabbit): `_sendVoice` must first STOP the
  /// recorder and only then uploads / appends the note. While that stop +
  /// upload sequence is in flight, a concurrent CANCEL would call
  /// `recorder.stop()` a second time and UNLINK the pending take
  /// (`cancelVoiceRecording` deletes the file) — the note would silently vanish
  /// mid-send. This flag serializes the two paths: every recorder-touching
  /// entry point refuses to run while it is set.
  bool _isStoppingOrSendingVoice = false;

  /// True once [dispose] ran. Read by [_startRecording]'s continuation: a
  /// recorder handshake still in flight when the screen closes must NOT leave
  /// a live microphone behind (CodeRabbit) — the continuation cancels the take
  /// and releases the hardware instead of arming a recording nobody can stop.
  bool _disposed = false;

  /// True while [_startRecording]'s recorder handshake (permission prompt,
  /// directory resolution, native `start`) is in flight. [dispose] defers the
  /// media teardown to the handshake continuation in that case, exactly like
  /// it already defers it for an in-flight [_sendVoice].
  bool _recordingStartupPending = false;

  /// Client vs pro viewer — drives bubble mirroring & sender identity.
  bool get _viewerIsCustomer =>
      widget.isCustomer ?? !(UserStore.user.value?.isProfessional ?? false);

  /// Sender identity carried by EVERY outbound message (CodeRabbit).
  ///
  /// AUTHENTICATED ID FIRST: `messages.sender_id` — and the RLS insert policy
  /// behind it — belongs to the Supabase Auth UUID, and
  /// [ChatStore.applyRemoteMessage]'s self-echo suppression compares the
  /// incoming `senderId` against the local session id, so the legacy
  /// 'customer' / 'pro' placeholder failed both checks.
  ///
  /// FALLBACK CHAIN (never invents an identity):
  ///   1. the authenticated Supabase UUID;
  ///   2. the local session id (offline / local-only builds);
  ///   3. the legacy role token — ONLY when no id exists at all, so a
  ///      still-roleless offline session keeps working exactly as before.
  String _senderId({required bool isCustomer}) {
    final remote = SupabaseAuthService.currentUserId;
    if (remote != null) return remote;
    final local = UserStore.user.value?.id.trim();
    if (local != null && local.isNotEmpty) return local;
    return isCustomer ? 'customer' : 'pro';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VoiceNotePlayer.warmUp();
    // Housekeeping: drop media files orphaned by older conversations.
    ChatMediaService.cleanupOrphans();
    // Live minute-tick so the "closes in Xh Ym" banner stays accurate even
    // when no messages arrive (previously it froze until a rebuild).
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {}); // re-reads ChatSession time getters on rebuild
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _recTimer?.cancel();
    // Release the mic if the user leaves mid-recording; without this the
    // recorder keeps capturing in the background and the UI gets stuck.
    //
    // DEFERRED TEARDOWN (CodeRabbit): while `_sendVoice` OWNS the recorder the
    // teardown is skipped entirely — cancelling would delete the take being
    // uploaded, and disposing the recorder would abort the in-flight stop.
    // `_sendVoice`'s `finally` runs it as soon as the send settles (the State
    // is unmounted by then, which is exactly the case it checks for).
    //
    // Same deferral applies to a recorder handshake still starting up: the
    // `_startRecording` continuation owns the teardown (cancel + release) the
    // moment it observes [_disposed], so a native `start()` resolving AFTER
    // this method can never arm an orphaned background recording.
    if (!_isStoppingOrSendingVoice && !_recordingStartupPending) {
      if (ChatMediaService.isRecording.value) {
        unawaited(_releaseMedia());
      } else {
        unawaited(VoiceNotePlayer.stop());
        unawaited(ChatMediaService.dispose());
        unawaited(VoiceNotePlayer.dispose());
      }
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _releaseMedia() async {
    await ChatMediaService.cancelVoiceRecording();
    await VoiceNotePlayer.stop();
    await ChatMediaService.dispose();
    await VoiceNotePlayer.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(VoiceNotePlayer.pause());
    }
  }

  void _send({required bool isCustomer}) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    ChatStore.send(
      requestId: widget.requestId,
      senderId: _senderId(isCustomer: isCustomer),
      senderName: isCustomer ? request.customerName : request.professionalName,
      text: text,
      isCustomer: isCustomer,
    );
    _controller.clear();
  }

  /// Stops the recorder, uploads the take and appends the note.
  ///
  /// SERIALIZED (CodeRabbit): the whole sequence runs under
  /// [_isStoppingOrSendingVoice], so `_cancelRecording` (and `dispose`) can no
  /// longer call `recorder.stop()` / delete the pending file while the note is
  /// being stopped and sent. The flag is released in `finally`, and the deferred
  /// media teardown runs there when the screen was closed mid-send.
  Future<void> _sendVoice() async {
    if (_isStoppingOrSendingVoice) return; // double-tap: one send only
    final isCustomer = _viewerIsCustomer;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;
    _isStoppingOrSendingVoice = true;
    try {
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
      // SUPABASE STORAGE MIRROR: upload BEFORE appending so the message row
      // carries the shared public URL (renderable by the counterpart through
      // Realtime). Offline / failure → the local path flows through unchanged
      // (graceful fallback — the note still plays on this device, and ChatStore
      // refuses to push a device-local path to the shared `messages` table).
      final remotePath =
          await ChatMediaService.uploadVoiceNote(widget.requestId, path);
      ChatStore.sendVoice(
        requestId: widget.requestId,
        senderId: _senderId(isCustomer: isCustomer),
        senderName:
            isCustomer ? request.customerName : request.professionalName,
        filePath: remotePath,
        durationSec: seconds,
        isCustomer: isCustomer,
      );
    } finally {
      _isStoppingOrSendingVoice = false;
      if (!mounted) {
        // The screen was closed while the note was in flight: the teardown
        // [dispose] deliberately deferred now runs, with the recorder free.
        unawaited(VoiceNotePlayer.stop());
        unawaited(ChatMediaService.dispose());
        unawaited(VoiceNotePlayer.dispose());
      }
    }
  }

  Future<void> _startRecording() async {
    // A take that is still being stopped / sent still owns the recorder: a new
    // session would race the pending `stop()`. A STARTUP already pending owns
    // it too (CodeRabbit): a second tap while the handshake is in flight must
    // be IGNORED, not stacked — two concurrent `startVoiceRecording()` calls
    // would race the shared static recorder.
    if (_isStoppingOrSendingVoice ||
        _recordingStartupPending ||
        _disposed ||
        !mounted) {
      return;
    }
    _recordingStartupPending = true;
    try {
      final result = await ChatMediaService.startVoiceRecording();
      // DISPOSED DURING STARTUP (CodeRabbit): the screen may have been closed
      // while the handshake was in flight. The startup sequence is cancelled
      // right here — the just-started take (if any) is cancelled and ALL audio
      // hardware / stream resources are released, so no background recording
      // outlives the screen. `_releaseMedia` is the same teardown [dispose]
      // deferred; it is idempotent (static singletons, guarded disposal).
      if (_disposed || !mounted) {
        await _releaseMedia();
        return;
      }
      if (result != VoiceRecordingStartResult.started) {
        final permissionDenied =
            result == VoiceRecordingStartResult.permissionDenied;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              fr: permissionDenied
                  ? 'Autorisez l\'accès au microphone pour enregistrer une note vocale.'
                  : 'Microphone indisponible',
              ar: permissionDenied
                  ? 'اسمح بالوصول إلى الميكروفون لتسجيل رسالة صوتية.'
                  : 'الميكروفون غير متاح')),
        ));
        return;
      }
      setState(() {
        _isRecording = true;
        _recSeconds = 0;
        _recTimer?.cancel();
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _recSeconds++);
        });
      });
    } finally {
      _recordingStartupPending = false;
    }
  }

  Future<void> _cancelRecording() async {
    // CANCEL vs SEND (CodeRabbit): once `_sendVoice` owns the recorder the take
    // is already being stopped, uploaded and sent — cancelling here would call
    // `recorder.stop()` again and DELETE the very file being sent. The guard
    // turns the cancel into an explicit no-op instead of losing the note.
    if (_isStoppingOrSendingVoice) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              fr: 'Envoi en cours — annulation impossible.',
              ar: 'جارٍ الإرسال — لا يمكن الإلغاء.')),
        ));
      }
      return;
    }
    _recTimer?.cancel();
    await ChatMediaService.cancelVoiceRecording();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recSeconds = 0;
      });
    }
  }

  /// Fetches the current GPS position and sends a location pin. Available
  /// to BOTH client and pro roles — the recipient can tap the bubble to
  /// open Google Maps.
  Future<void> _sendLocation() async {
    final isCustomer = _viewerIsCustomer;
    final request = RequestStore.byId(widget.requestId);
    if (request == null) return;

    try {
      // Reuse the permission flow from LocationService — keep this call
      // self-contained so the chat works even when the user skipped the
      // startup location prompt.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(context,
                fr: 'Permission de localisation refusée',
                ar: 'تم رفض إذن الموقع')),
          ));
        }
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(context,
                fr: 'Activez la localisation pour partager votre position',
                ar: 'فعّل خدمة الموقع لمشاركة موقعك')),
          ));
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      ChatStore.sendLocation(
        requestId: widget.requestId,
        senderId: _senderId(isCustomer: isCustomer),
        senderName:
            isCustomer ? request.customerName : request.professionalName,
        latitude: position.latitude,
        longitude: position.longitude,
        isCustomer: isCustomer,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context,
              fr: 'Impossible d\'obtenir la position',
              ar: 'تعذّر الحصول على الموقع')),
        ));
      }
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
    // Bind the pick to THIS chat room so the Storage upload lands in the
    // request-scoped folder (`chat-media/<requestId>/…`).
    ChatMediaService.currentRequestId = widget.requestId;
    final path = await ChatMediaService.pickPhoto(fromCamera: fromCamera);
    if (path == null) {
      // USER-FACING ERROR STATE (Qodo): a null result means the pick was
      // denied / failed / cancelled — never fail silently.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context,
            fr: 'Sélection impossible — autorisez la caméra/galerie.',
            ar: 'تعذّر الاختيار — يُرجى منح إذن الكاميرا/المعرض.')),
      ));
      return;
    }
    ChatStore.sendPhoto(
      requestId: widget.requestId,
      senderId: _senderId(isCustomer: isCustomer),
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
        resizeToAvoidBottomInset: true,
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
      resizeToAvoidBottomInset: true,
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
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                          fr: "Cette conversation s'est fermée automatiquement après 4 jours.",
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
                          child: Text(tr(context, fr: 'Annuler', ar: 'إلغاء')),
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
                          onTap: _sendLocation,
                          customBorder: const CircleBorder(),
                          child: const CircleAvatar(
                            radius: 19,
                            backgroundColor: AppColors.primarySurface,
                            child: Icon(Icons.location_on_rounded,
                                size: 20, color: AppColors.secondary),
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
