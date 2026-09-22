import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/services/supabase_storage_service.dart';
import '../application/chat_store.dart';

/// Outcome of the recorder startup handshake.
enum VoiceRecordingStartResult { started, permissionDenied, recorderError }

/// Captures chat media (photos & voice notes) and stores the files inside
/// the app documents directory so message paths remain valid across app
/// restarts. All plugin calls are isolated here — [ChatStore] stays pure
/// Dart and fully unit-testable. Both roles (client & pro) use this service
/// identically.
class ChatMediaService {
  ChatMediaService._();

  static final ImagePicker _picker = ImagePicker();
  static AudioRecorder? _recorder;
  static AudioRecorder get _activeRecorder => _recorder ??= AudioRecorder();

  /// True while a voice-recording session is running.
  static final isRecording = ValueNotifier<bool>(false);

  /// True while [stopVoiceRecording] is finalizing a take (recorder stop +
  /// metadata flush).
  ///
  /// STOP-vs-CANCEL GUARD (CodeRabbit): [cancelVoiceRecording] DELETES the
  /// pending take, so running it while a stop is in flight would unlink the
  /// very file the caller is about to send — a data-loss race that the UI-level
  /// guard alone cannot fully prevent (two entry points, one shared recorder).
  /// The service therefore refuses to cancel during a stop, at the layer that
  /// actually performs the deletion.
  static bool get isStopping => _stoppingVoice;
  static bool _stoppingVoice = false;

  static DateTime? _startedAt;
  static String? _pendingPath;

  /// Picks a photo from the gallery or camera, copies it into the persistent
  /// chat-media folder AND — when online with Supabase configured — uploads
  /// it to the shared `chat-media` bucket.
  ///
  /// RETURN VALUE:
  ///   • upload success → the PUBLIC URL: the message row (and therefore the
  ///     counterpart's device through Realtime) renders the remote copy via
  ///     [AppImage] — no path translation needed on either side;
  ///   • upload failure / offline → the LOCAL absolute path (graceful
  ///     fallback: the message still works on this device; the remote copy
  ///     is simply deferred to a future re-send).
  static Future<String?> pickPhoto({required bool fromCamera}) async {
    try {
      final xfile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 72,
        maxWidth: 1440,
      );
      if (xfile == null) return null;
      final localPath = await _copyToChatDir(File(xfile.path), 'photo', '.jpg');
      if (localPath == null) return null;

      // SUPABASE STORAGE MIRROR: shared bucket copy so the other party can
      // render it. Failure → null → the local path is returned unchanged.
      final url = await SupabaseStorageService.uploadChatMedia(
        _currentRequestId ?? 'unbound',
        File(localPath),
      );
      return url ?? localPath;
    } catch (e) {
      debugPrint('ChatMediaService.pickPhoto failed: $e');
      return null;
    }
  }

  /// Uploads a voice note (called by the chat screen BEFORE the message is
  /// appended, so the message row carries the renderable URL when the
  /// upload succeeded — same contract as [pickPhoto]).
  ///
  /// NEVER returns null: an offline/failed upload falls back to [localPath]
  /// so the note always plays on the sending device.
  static Future<String> uploadVoiceNote(
    String requestId,
    String localPath,
  ) async {
    try {
      final url = await SupabaseStorageService.uploadChatMedia(
        requestId,
        File(localPath),
        kind: 'voice',
      );
      return url ?? localPath;
    } catch (e) {
      debugPrint('ChatMediaService.uploadVoiceNote failed: $e');
      return localPath;
    }
  }

  /// The chat room the CURRENT photo pick belongs to (set by the chat screen
  /// right before opening the picker; null outside an active chat).
  static String? _currentRequestId;
  static set currentRequestId(String? value) => _currentRequestId = value;

  /// Starts a voice recording.
  ///
  /// [AudioRecorder.hasPermission] is deliberately the only permission
  /// mechanism here. Its default `request: true` asks the native platform for
  /// permission when the status is undecided, so adding permission_handler
  /// would create a second, competing permission flow.
  static Future<VoiceRecordingStartResult> startVoiceRecording() async {
    if (isRecording.value) return VoiceRecordingStartResult.recorderError;
    try {
      // Keep this before start(): record owns the runtime microphone dialog.
      if (!await _activeRecorder.hasPermission()) {
        return VoiceRecordingStartResult.permissionDenied;
      }
      final dir = await _chatDir();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _activeRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _pendingPath = path;
      _startedAt = DateTime.now();
      isRecording.value = true;
      return VoiceRecordingStartResult.started;
    } catch (e) {
      debugPrint('ChatMediaService.startVoiceRecording failed: $e');
      isRecording.value = false;
      return VoiceRecordingStartResult.recorderError;
    }
  }

  /// Stops the recording and returns `(path, durationSec)`. The path is null
  /// when the recording failed. Duration is clamped to 1–600 seconds.
  ///
  /// The take is NOT deleted (unlike [cancelVoiceRecording]): its file is what
  /// the caller uploads and sends. While this runs, [isStopping] is true and
  /// [cancelVoiceRecording] is a no-op.
  static Future<(String?, int)> stopVoiceRecording() async {
    String? path;
    final pending = _pendingPath;
    var seconds = 0;
    _stoppingVoice = true;
    try {
      final recorder = _recorder;
      path = recorder == null ? null : await recorder.stop();
      final started = _startedAt;
      seconds =
          started == null ? 0 : DateTime.now().difference(started).inSeconds;
    } catch (e) {
      debugPrint('ChatMediaService.stopVoiceRecording failed: $e');
      path = null;
    } finally {
      isRecording.value = false;
      _stoppingVoice = false;
      _startedAt = null;
      _pendingPath = null;
    }
    if (seconds < 1) seconds = 1;
    if (seconds > 600) seconds = 600;
    return (path ?? pending, seconds);
  }

  /// Cancels the current recording without sending it (deletes the file).
  ///
  /// REFUSES to run while a stop is in flight (CodeRabbit): the take is then
  /// already being finalized for SENDING, and deleting it would silently lose
  /// the user's voice note. The caller's own guard (chat screen) reports this
  /// to the user; here the file is simply protected.
  static Future<void> cancelVoiceRecording() async {
    if (_stoppingVoice) {
      debugPrint('ChatMediaService.cancelVoiceRecording skipped: a stop/send '
          'is in flight for the current take.');
      return;
    }
    String? recorded;
    try {
      final recorder = _recorder;
      recorded = recorder == null ? null : await recorder.stop();
    } catch (e) {
      debugPrint('ChatMediaService.cancelVoiceRecording failed: $e');
      recorded = null;
    }
    isRecording.value = false;
    _startedAt = null;
    final discard = recorded ?? _pendingPath;
    _pendingPath = null;
    if (discard != null && discard.isNotEmpty) {
      try {
        final f = File(discard);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('ChatMediaService temporary recording cleanup failed: $e');
      }
    }
  }

  static Future<Directory> _chatDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/chat_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> _copyToChatDir(
      File source, String prefix, String ext) async {
    try {
      final dir = await _chatDir();
      final target =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final copied = await source.copy(target);
      if (source.path != copied.path) {
        // The durable copy ALREADY exists — a failure to remove the picker's
        // temporary source must never discard that work (CodeRabbit): log a
        // warning and return the durable instance, never throw and never
        // fall back to the ephemeral source path.
        try {
          if (await source.exists()) await source.delete();
        } catch (e) {
          debugPrint('ChatMediaService._copyToChatDir: durable copy created '
              'but temporary source "${source.path}" could not be removed: '
              '$e');
        }
      }
      return copied.path;
    } catch (e) {
      debugPrint('ChatMediaService._copyToChatDir failed: $e');
      return source.path; // Fall back to the original picker location.
    }
  }

  static Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) await recorder.dispose();
  }

  /// Housekeeping: deletes every media file older than [maxAge] from the
  /// chat-media folder. Since chat sessions/messages live only in memory,
  /// files orphaned by finished conversations would otherwise pile up
  /// forever. Fire-and-forget; called when a chat screen opens.
  static Future<void> cleanupOrphans({
    Duration maxAge = const Duration(days: 5),
  }) async {
    try {
      final dir = await _chatDir();
      final cutoff = DateTime.now().subtract(maxAge);
      final referenced = {
        for (final messages in ChatStore.messages.value.values)
          for (final message in messages)
            if (message.mediaPath != null && message.mediaPath!.isNotEmpty)
              message.mediaPath!,
      };
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff) &&
            !referenced.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint('ChatMediaService orphan delete failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('ChatMediaService.cleanupOrphans failed: $e');
    }
  }
}
