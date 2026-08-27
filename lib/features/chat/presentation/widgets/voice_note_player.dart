import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Single shared audio player for voice-note bubbles. Guarantees that only
/// one note plays at a time and exposes reactive playback state consumed
/// identically by sender and receiver bubbles.
class VoiceNotePlayer {
  VoiceNotePlayer._();

  static final AudioPlayer _player = AudioPlayer();

  /// Path of the note currently loaded (null = idle).
  static final playingPath = ValueNotifier<String?>(null);

  /// True while the active note is audibly playing (false = paused).
  static final isPlaying = ValueNotifier<bool>(false);

  /// 0.0 → 1.0 playback progress of the active note.
  static final progress = ValueNotifier<double>(0);

  /// Elapsed whole seconds of the active note.
  static final elapsedSec = ValueNotifier<int>(0);

  static bool _inited = false;
  static int _durationMs = 0;

  /// Prepares stream listeners. Called lazily (first toggle / screen init).
  static void warmUp() => _ensureInit();

  static void _ensureInit() {
    if (_inited) return;
    _inited = true;
    _player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0) _durationMs = d.inMilliseconds;
    });
    _player.onPositionChanged.listen((p) {
      elapsedSec.value = p.inSeconds;
      if (_durationMs > 0) {
        progress.value = (p.inMilliseconds / _durationMs).clamp(0.0, 1.0);
      }
    });
    _player.onPlayerComplete.listen((_) => _reset());
  }

  /// Play / pause / switch note — the single entry point used by bubbles.
  static Future<void> toggle(String path) async {
    if (path.isEmpty) return;
    _ensureInit();
    try {
      if (playingPath.value == path) {
        if (isPlaying.value) {
          await _player.pause();
          isPlaying.value = false;
        } else {
          await _player.resume();
          isPlaying.value = true;
        }
        return;
      }
      await _player.stop();
      _durationMs = 0;
      progress.value = 0;
      elapsedSec.value = 0;
      playingPath.value = path;
      await _player.play(DeviceFileSource(path));
      isPlaying.value = true;
    } catch (_) {
      _reset();
    }
  }

  static void _reset() {
    isPlaying.value = false;
    playingPath.value = null;
    progress.value = 0;
    elapsedSec.value = 0;
    _durationMs = 0;
  }
}
