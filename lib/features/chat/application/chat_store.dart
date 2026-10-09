import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/messages_repository.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../../../core/error/app_error_handler.dart';
import '../../../core/services/supabase_storage_service.dart';
import '../../notifications/application/notification_store.dart';
import '../../auth/application/user_store.dart';
import '../../requests/application/request_store.dart';

class ChatStore {
  ChatStore._();

  static final messages = ValueNotifier<Map<String, List<ChatMessage>>>({});

  /// Lifecycle state of every request-bound chat room (admin-manageable).
  static final sessions = ValueNotifier<Map<String, ChatSession>>({});

  /// Persistence gateway (mocktail seam, CodeRabbit): production binds the
  /// real [MessagesRepository.insertMessage]; tests swap it to simulate
  /// transport outcomes (success / backend refusal / network failure) without
  /// ever initializing a Supabase client. Never leave a test stub installed:
  /// reset it in the test's `setUp`/`tearDown`.
  @visibleForTesting
  static Future<bool> Function(ChatMessage message) insertMessageGateway =
      MessagesRepository.insertMessage;

  /// Ids of messages whose backend INSERT never landed — a transport error or
  /// a backend refusal (CodeRabbit). The UI renders a retry affordance for
  /// exactly these bubbles; [retryDelivery] re-runs the mirror without
  /// duplicating the bubble (it already exists in [messages]).
  static final ValueNotifier<Set<String>> undelivered =
      ValueNotifier<Set<String>>(<String>{});

  /// True when the message's backend INSERT did not land yet.
  static bool isDeliveryFailed(String messageId) =>
      undelivered.value.contains(messageId);

  static void _markUndelivered(String messageId) {
    if (undelivered.value.contains(messageId)) return;
    undelivered.value = <String>{...undelivered.value, messageId};
  }

  static void _clearUndelivered(String messageId) {
    if (!undelivered.value.contains(messageId)) return;
    undelivered.value = <String>{...undelivered.value}..remove(messageId);
  }

  /// Test-only hook to simulate the failure/echo race deterministically:
  /// flags [messageId] as undelivered without performing any I/O, so a test
  /// can then deliver the realtime echo and assert the stale flag is cleared.
  @visibleForTesting
  static void debugMarkUndeliveredForTest(String messageId) =>
      _markUndelivered(messageId);

  /// Media-upload gateway (mocktail seam, like [insertMessageGateway]):
  /// production binds [SupabaseStorageService.uploadChatMedia]; tests swap it
  /// to simulate upload outcomes (success / failure) without touching the
  /// network. Signature: `(requestId, localFile, kind)` → public URL or null.
  /// Never leave a test stub installed: reset it in `setUp`/`tearDown`.
  @visibleForTesting
  static Future<String?> Function(String requestId, File file, String kind)
      uploadMediaGateway = (
    String requestId,
    File file,
    String kind,
  ) =>
          SupabaseStorageService.uploadChatMedia(requestId, file, kind: kind);

  /// Re-runs the backend mirror for an undelivered message (CodeRabbit): the
  /// bubble already exists locally, so a retry never duplicates it. Returns
  /// `true` when the row landed (the failed flag is cleared).
  ///
  /// GUARD (CodeRabbit): a message that already cleared the `undelivered` flag
  /// is by definition delivered/sent and must NEVER be re-sent. This makes the
  /// retry path idempotent and serializes retries against any in-flight mirror
  /// without double delivery (e.g. a stale retry button after a realtime echo
  /// lands). Re-mirrored messages simply re-enter the same single-flight.
  static Future<bool> retryDelivery(String messageId) async {
    if (!undelivered.value.contains(messageId)) return true;
    for (final entry in messages.value.entries) {
      for (final m in entry.value) {
        // Retry the FRESHEST in-memory copy (not a stale reference): a local
        // media bubble may have been reconciled to its remote URL since the
        // caller captured it (echo path / re-upload), and mirroring the stale
        // local path would re-trigger the upload branch needlessly.
        if (m.id == messageId) {
          final fresh = forRequest(m.requestId).firstWhere(
            (x) => x.id == messageId,
            orElse: () => m,
          );
          return _mirrorToBackend(fresh);
        }
      }
    }
    return false;
  }

  /// Auto-expiry window applied to newly opened chats. Admin-configurable,
  /// business range: 48–72 hours (default 48h).
  static int _expiryHours = 96;
  static int get expiryHours => _expiryHours;

  static void setExpiryHours(int hours) {
    if (hours < 48 || hours > 96) return;
    _expiryHours = hours;
  }

  static ChatSession? sessionOf(String requestId) => sessions.value[requestId];

  static List<ChatMessage> forRequest(String requestId) =>
      messages.value[requestId] ?? [];

  /// Opens (or refreshes) an active chat window once an order is confirmed.
  /// Called by [RequestStore] right after the 10-token deduction succeeds.
  static void activate(String requestId) {
    final map = Map<String, ChatSession>.from(sessions.value);
    map[requestId] = ChatSession(
      requestId: requestId,
      activatedAt: DateTime.now(),
      expiryHours: _expiryHours,
    );
    sessions.value = map;
  }

  /// Restores a session VERBATIM — same [ChatSession.activatedAt],
  /// [ChatSession.expiryHours], active flag and close stamp.
  ///
  /// ROLLBACK PATH ONLY (CodeRabbit): when an optimistic order transition is
  /// reverted because its Supabase write was genuinely refused, the chat
  /// window must go back to EXACTLY how it was. Re-opening it through
  /// [activate] would be wrong twice over — it starts a brand-new window
  /// (`activatedAt = now`) and therefore silently EXTENDS the chat expiry for
  /// an order the server never accepted. Passing `null` removes the session
  /// entirely (the pre-transition state when no room existed yet).
  static void restoreSession(String requestId, ChatSession? session) {
    final map = Map<String, ChatSession>.from(sessions.value);
    if (session == null) {
      if (!map.containsKey(requestId)) return;
      map.remove(requestId);
    } else {
      map[requestId] = session;
    }
    sessions.value = map;
  }

  /// Silently marks a session inactive (order reset / cancelled / completed).
  static void deactivate(String requestId) {
    final current = sessions.value[requestId];
    if (current == null || !current.active) return;

    final map = Map<String, ChatSession>.from(sessions.value);
    map[requestId] = ChatSession(
      requestId: requestId,
      active: false,
      activatedAt: current.activatedAt,
      closedAt: DateTime.now(),
      expiryHours: current.expiryHours,
    );
    sessions.value = map;
  }

  /// Admin manually closes a chat: neither party can send until the order is
  /// confirmed again (which charges another 10 tokens). Notifies both sides.
  static void closeByAdmin(String requestId) {
    final current = sessions.value[requestId];
    if (current == null || !current.active) return;

    deactivate(requestId);

    final request = RequestStore.byId(requestId);
    if (request != null) {
      if (request.customerId.isNotEmpty) {
        NotificationStore.notifyChatClosed(
          requestId,
          request.customerId,
          targetRole: 'client',
        );
      }
      NotificationStore.notifyChatClosed(
        requestId,
        request.professionalId,
        targetRole: 'professional',
      );
    }
  }

  /// Why a chat room is unavailable right now (drives UI messaging).
  static ChatClosureReason closureStateOf(String requestId) {
    final s = sessions.value[requestId];
    if (s == null) return ChatClosureReason.none;
    if (!s.active) return ChatClosureReason.adminClosed;
    if (s.isExpired) return ChatClosureReason.expired;
    return ChatClosureReason.none;
  }

  /// A chat can carry messages only while its session is active & unexpired.
  static bool isActive(String requestId) {
    final s = sessions.value[requestId];
    return s != null && s.active && !s.isExpired;
  }

  static void send({
    required String requestId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isCustomer,
  }) {
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      isCustomer: isCustomer,
    );
  }

  /// Sends a recorded voice note. Available to BOTH roles (client & pro) —
  /// the stored structure is identical, only the bubble side differs.
  static void sendVoice({
    required String requestId,
    required String senderId,
    required String senderName,
    required String filePath,
    required int durationSec,
    required bool isCustomer,
  }) {
    final path = filePath.trim();
    if (path.isEmpty) return;
    final seconds =
        durationSec < 1 ? 1 : (durationSec > 600 ? 600 : durationSec);
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.voice,
      mediaPath: path,
      voiceDurationSec: seconds,
    );
  }

  /// Sends an attached photo. Available to BOTH roles as well.
  static void sendPhoto({
    required String requestId,
    required String senderId,
    required String senderName,
    required String filePath,
    required bool isCustomer,
  }) {
    final path = filePath.trim();
    if (path.isEmpty) return;
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.photo,
      mediaPath: path,
    );
  }

  /// Sends a GPS location pin. Available to BOTH roles.
  /// The recipient can tap the bubble to open Google Maps.
  static void sendLocation({
    required String requestId,
    required String senderId,
    required String senderName,
    required double latitude,
    required double longitude,
    required bool isCustomer,
  }) {
    _append(
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: '',
      isCustomer: isCustomer,
      type: ChatMessageType.location,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static int _seq = 0;

  /// Single persistence pipeline shared by text / voice / photo messages.
  /// Defense-in-depth: never persist messages into locked rooms (admin
  /// closure, expiry, or unconfirmed order).
  static void _append({
    required String requestId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isCustomer,
    ChatMessageType type = ChatMessageType.text,
    String? mediaPath,
    int voiceDurationSec = 0,
    double? latitude,
    double? longitude,
  }) {
    if (!RequestStore.isChatAllowed(requestId)) return;

    final msg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
      requestId: requestId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      isCustomer: isCustomer,
      type: type,
      mediaPath: mediaPath,
      voiceDurationSec: voiceDurationSec,
      latitude: latitude,
      longitude: longitude,
    );

    final map = Map<String, List<ChatMessage>>.from(messages.value);
    map[requestId] = [...(map[requestId] ?? []), msg];
    messages.value = map;

    // LIVE BACKEND MIRROR (Supabase `messages`): the local append stays
    // synchronous; the row is pushed asynchronously so the OTHER device
    // receives it through the Realtime `messages` channel. No-op / logged
    // when offline or Supabase is not initialized.
    //
    // DEVICE-LOCAL MEDIA (design contract verified by chat_store_test.dart):
    // a captured media URI (`/data/user/0/...`, `file://...`, `C:\...`) must
    // NEVER be handed to [insertMessageGateway] — the counterpart could never
    // render it. Such a bubble is flagged `undelivered` IN PLACE so the UI can
    // offer a retry/upload affordance, and it is left for the realtime
    // ingress (applyRemoteMessage → _clearUndelivered) to clear once the
    // upload actually lands. Remote media (`http(s)://`) mirrors normally.
    final media = mediaPath;
    if (media != null && media.isNotEmpty && _isLocalMediaPath(media)) {
      _markUndelivered(msg.id);
    } else {
      unawaited(_mirrorToBackend(msg));
    }

    // Send notification about new message, routed to the RECEIVING side:
    // a customer's message alerts the pro, and vice-versa.
    final request = RequestStore.byId(requestId);
    final recipientId =
        isCustomer ? request?.professionalId : request?.customerId;
    if (recipientId != null && recipientId.isNotEmpty) {
      NotificationStore.notifyChatMessage(
        requestId,
        senderName,
        recipientId,
        targetRole: isCustomer ? 'professional' : 'client',
      );
    }
  }

  /// Pushes [msg] to the shared `messages` table, guaranteeing that only
  /// REMOTE-READABLE media references are persisted (CodeRabbit).
  ///
  /// WHY: `mediaPath` is device-local (`/data/user/0/…`, `file://…`, `C:\…`)
  /// whenever the capture upload failed or the device was offline. Persisting
  /// that string remotely produced a message the OTHER party could never
  /// render — an unreadable bubble everywhere but the sender's phone.
  ///
  /// CONTRACT:
  ///   • no media, or already remote (`http(s)://`) → insert as-is;
  ///   • local media → upload to the public `chat-media` bucket FIRST, then
  ///     insert the row carrying the returned PUBLIC URL (and upgrade the
  ///     local bubble in place, so both sides show the very same URL);
  ///   • upload impossible (offline / failure) → the row is NOT inserted: the
  ///     message stays local-only rather than becoming a broken remote row.
  ///
  /// DELIVERY STATE (CodeRabbit): every non-landing path — backend refusal,
  /// upload failure, transport error — flags the message in [undelivered] so
  /// the UI can offer a retry; a landed row clears the flag. Returns `true`
  /// only when the row is durably owned by the backend. NEVER throws.
  static Future<bool> _mirrorToBackend(ChatMessage msg) async {
    try {
      final media = msg.mediaPath;
      if (media == null || media.isEmpty || !_isLocalMediaPath(media)) {
        final ok = await insertMessageGateway(msg);
        if (!ok) {
          debugPrint('ChatStore: INSERT for "${msg.id}" was refused by the '
              'backend — flagged undelivered (retry affordance).');
          _markUndelivered(msg.id);
          return false;
        }
        _clearUndelivered(msg.id);
        return true;
      }

      // LOCAL MEDIA: the capture path is uploaded through the testable
      // [uploadMediaGateway] (production: Supabase Storage `chat-media`
      // bucket → public URL). The upload is re-attempted on EVERY mirror run
      // — first send and each [retryDelivery] — until a public URL comes back,
      // so no bubble is ever stranded local-only: failure keeps the
      // `undelivered` flag and the UI retry affordance instead of silently
      // dropping the media.
      final remoteUrl = await uploadMediaGateway(
        msg.requestId,
        File(media),
        msg.type == ChatMessageType.voice ? 'voice' : 'photo',
      );
      if (remoteUrl == null || remoteUrl.isEmpty) {
        debugPrint('ChatStore: media for "${msg.id}" stayed local — the row is '
            'not mirrored (a device path must never reach the shared table).');
        _markUndelivered(msg.id);
        return false;
      }

      _replaceMediaPath(msg.id, remoteUrl);
      final ok = await insertMessageGateway(msg.copyWith(mediaPath: remoteUrl));
      if (!ok) {
        _markUndelivered(msg.id);
        return false;
      }
      _clearUndelivered(msg.id);
      return true;
    } catch (e, st) {
      // TRANSPORT FAILURE (CodeRabbit): a network error while sending must
      // never crash the fire-and-forget caller. The bubble stays local-first
      // and is flagged for retry instead.
      debugPrint('ChatStore: mirror for "${msg.id}" failed (transport): $e');
      AppErrorHandler.report(e, st, context: 'ChatStore._mirrorToBackend');
      _markUndelivered(msg.id);
      return false;
    }
  }

  /// True when [path] is a DEVICE-LOCAL reference rather than a remote URL.
  ///
  /// Deliberately conservative: anything that is not an `http(s)` URL is
  /// treated as local, because persisting it remotely can only ever produce an
  /// unreadable row.
  static bool _isLocalMediaPath(String path) {
    final lower = path.toLowerCase();
    return !lower.startsWith('http://') && !lower.startsWith('https://');
  }

  /// Upgrades the in-memory bubble's [ChatMessage.mediaPath] to the uploaded
  /// URL so the sender's own view and the counterpart's realtime copy agree.
  /// No notifier emission when nothing actually changed.
  static void _replaceMediaPath(String messageId, String remoteUrl) {
    var changed = false;
    final map = <String, List<ChatMessage>>{};
    for (final entry in messages.value.entries) {
      final updated = <ChatMessage>[];
      for (final m in entry.value) {
        if (m.id == messageId && m.mediaPath != remoteUrl) {
          updated.add(m.copyWith(mediaPath: remoteUrl));
          changed = true;
        } else {
          updated.add(m);
        }
      }
      map[entry.key] = updated;
    }
    if (changed) messages.value = map;
  }

  /// REALTIME INGRESS (Supabase `messages` channel): applies a message that
  /// was persisted by the OTHER device.
  ///
  /// ECHO-SAFETY: the sender's own device ALSO receives its INSERT through
  /// the channel (the row was already appended locally by [_append]) — the
  /// id-based dedupe below makes that a no-op instead of a double bubble.
  ///
  /// The local notification fires ONLY for genuinely incoming messages
  /// (sender is the other party), never for the local echo.
  static void applyRemoteMessage(ChatMessage msg) {
    // DELIVERY CONFIRMATION — FIRST, before any dedupe/early-return: once the
    // backend owns the row (it just landed on the shared `messages` channel),
    // the temporary "undelivered" flag set by the local optimistic append is
    // stale and MUST be cleared. The retry affordance in the UI must disappear
    // the moment a realtime echo confirms persistence — including the echo of
    // our own send, which hits the id-dedupe early return below.
    _clearUndelivered(msg.id);

    final existing = messages.value[msg.requestId] ?? const <ChatMessage>[];
    final duplicateIndex = existing.indexWhere((m) => m.id == msg.id);
    if (duplicateIndex != -1) {
      // Echo / duplicate: same id already appended locally — no second bubble.
      // MEDIA RECONCILIATION: the realtime row carries the canonical remote
      // URL, while our optimistic bubble may still point at the device-local
      // file (upload finished after the row landed, or the echo arrived
      // before `_replaceMediaPath` ran). Upgrade the stored bubble so the
      // sender's view and the counterpart's copy agree, without re-notifying.
      final local = existing[duplicateIndex];
      if (msg.mediaPath != null &&
          msg.mediaPath!.isNotEmpty &&
          local.mediaPath != msg.mediaPath) {
        final map = Map<String, List<ChatMessage>>.from(messages.value);
        final updated = List<ChatMessage>.from(existing);
        updated[duplicateIndex] = local.copyWith(mediaPath: msg.mediaPath);
        map[msg.requestId] = updated;
        messages.value = map;
      }
      return;
    }

    final map = Map<String, List<ChatMessage>>.from(messages.value);
    map[msg.requestId] = [...existing, msg];
    messages.value = map;

    // Self-echo suppression: the LOCAL session user id is authoritative —
    // a message authored by this very identity (from another device or the
    // realtime echo of a local send) must never notify itself.
    final me = UserStore.user.value?.id;
    if (me != null && me.isNotEmpty && msg.senderId == me) return;

    final request = RequestStore.byId(msg.requestId);
    final recipientId =
        msg.isCustomer ? request?.professionalId : request?.customerId;
    if (recipientId != null && recipientId.isNotEmpty) {
      NotificationStore.notifyChatMessage(
        msg.requestId,
        msg.senderName,
        recipientId,
        targetRole: msg.isCustomer ? 'professional' : 'client',
      );
    }
  }

  static void seedDemo(String requestId) {
    if (forRequest(requestId).isNotEmpty) return;
    send(
      requestId: requestId,
      senderId: 'customer',
      senderName: 'Feres',
      text: 'السلام عليكم، نحب نعرف قداش تقريبًا تاخو وقت الخدمة؟',
      isCustomer: true,
    );
    send(
      requestId: requestId,
      senderId: 'pro',
      senderName: 'Ahmed',
      text: 'وعليكم السلام، تقريبًا نهار.',
      isCustomer: false,
    );
  }

  /// Clears every in-memory chat room and session (used on logout).
  ///
  /// TEST-SEAM HYGIENE: both gateways are restored to their production
  /// bindings so a stub installed by one test file can never leak into the
  /// next suite (the full `flutter test` run executes all files in one
  /// process). Prefer this over resetting seams individually in each test.
  static void reset() {
    messages.value = {};
    sessions.value = {};
    undelivered.value = <String>{};
    insertMessageGateway = MessagesRepository.insertMessage;
    uploadMediaGateway = (
      String requestId,
      File file,
      String kind,
    ) =>
        SupabaseStorageService.uploadChatMedia(requestId, file, kind: kind);
  }
}
