import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Captures chat media (photos & voice notes) and stores the files inside
/// the app documents directory so message paths remain valid across app
/// restarts. All plugin calls are isolated here — [ChatStore] stays pure
/// Dart and fully unit-testable. Both roles (client & pro) use this service
/// identically.
class ChatMediaService {
  ChatMediaService._();

  static final ImagePicker _picker = ImagePicker();
  static final AudioRecorder _recorder = AudioRecorder();

  /// True while a voice-recording session is running.
  static final isRecording = ValueNotifier<bool>(false);

  static DateTime? _startedAt;
  static String? _pendingPath;

  /// Picks a photo from the gallery or camera and copies it into the
  /// persistent chat-media folder. Returns null when the user cancels or
  /// the picker fails.
  static Future<String?> pickPhoto({required bool fromCamera}) async {
    try {
      final xfile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 72,
        maxWidth: 1440,
      );
      if (xfile == null) return null;
      return _copyToChatDir(File(xfile.path), 'photo', '.jpg');
    } catch (_) {
      return null;
    }
  }

  /// Starts a voice recording. Returns false when the microphone permission
  /// is denied or the recorder fails to start.
  static Future<bool> startVoiceRecording() async {
    if (isRecording.value) return false;
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await _chatDir();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
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
      return true;
    } catch (_) {
      isRecording.value = false;
      return false;
    }
  }

  /// Stops the recording and returns `(path, durationSec)`. The path is null
  /// when the recording failed. Duration is clamped to 1–600 seconds.
  static Future<(String?, int)> stopVoiceRecording() async {
    String? path;
    var seconds = 0;
    try {
      path = await _recorder.stop();
      final started = _startedAt;
      seconds = started == null
          ? 0
          : DateTime.now().difference(started).inSeconds;
    } catch (_) {
      path = null;
    } finally {
      isRecording.value = false;
      _startedAt = null;
      _pendingPath = null;
    }
    if (seconds < 1) seconds = 1;
    if (seconds > 600) seconds = 600;
    return (path ?? _pendingPath, seconds);
  }

  /// Cancels the current recording without sending it (deletes the file).
  static Future<void> cancelVoiceRecording() async {
    String? recorded;
    try {
      recorded = await _recorder.stop();
    } catch (_) {
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
      } catch (_) {
        // Best-effort cleanup.
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
      return copied.path;
    } catch (_) {
      return source.path; // Fall back to the original picker location.
    }
  }

  static Future<void> dispose() => _recorder.dispose();
}
