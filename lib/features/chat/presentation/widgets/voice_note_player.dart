import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:allo_service_pro/shared/app_locale.dart';

/// Single shared audio player for voice-note bubbles. Guarantees that only
/// one note plays at a time and exposes reactive playback state consumed
/// identically by sender and receiver bubbles.
class VoiceNotePlayer {
  VoiceNotePlayer._();

  static AudioPlayer _player = AudioPlayer();

  /// FIFO lifecycle chain: every player operation (toggle, pause, dispose)
  /// appends to this future, so teardown and reseed can never overlap.
  /// The chain self-heals on error (`onError` swallow keeps later operations
  /// flowing — each step still handles its own failure locally).
  static Future<void> _lifecycle = Future<void>.value();

  // Set `true` once [dispose] tears down the shared player. `audioplayers`
  // offers no `disposed` getter, so lifecycle ownership is tracked locally:
  // after dispose, [toggle]/[pause] must RE-SEED the player via [_ensureInit]
  // instead of touching a dead native handle.
  static bool _needsReseed = false;

  /// Path of the note currently loaded (null = idle).
  static ValueNotifier<String?> playingPath = ValueNotifier<String?>(null);

  /// True while the active note is audibly playing (false = paused).
  static ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  /// 0.0 → 1.0 playback progress of the active note.
  static ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Elapsed whole seconds of the active note.
  static ValueNotifier<int> elapsedSec = ValueNotifier<int>(0);

  static bool _inited = false;
  static int _durationMs = 0;
  static StreamSubscription<Duration>? _durationSubscription;
  static StreamSubscription<Duration>? _positionSubscription;
  static StreamSubscription<void>? _completeSubscription;

  /// Prepares stream listeners. Called lazily (first toggle / screen init).
  /// The four static ValueNotifiers (playingPath, isPlaying, progress,
  /// elapsedSec) are **immutable process-wide singletons** — they are created
  /// ONCE at class-load time and NEVER reassigned or disposed across player
  /// lifecycle teardowns. Reassigning them in _ensureInit (as the old code did
  /// when `_disposed` was true) orphaned ValueListenableBuilder references in
  /// already-built bubble widgets and triggered
  /// "A ValueNotifier was used after being disposed" / silent state-loss.
  /// They are intentionally left in-memory forever; only the AudioPlayer and
  /// its subscriptions are torn down/rebuilt in dispose/_ensureInit.
  static void warmUp() => _ensureInit();

  static void _ensureInit() {
    if (_needsReseed) {
      // The shared player was torn down by [dispose] (chat screen exit) but
      // the four notifiers intentionally survived — reseed a FRESH native
      // player and re-arm the subscriptions. The notifier INSTANCES never
      // change, so already-built bubble widgets keep working.
      _player = AudioPlayer();
      _needsReseed = false;
      _inited = false;
      _durationSubscription = null;
      _positionSubscription = null;
      _completeSubscription = null;
    }
    if (_inited) return;
    _inited = true;
    _durationSubscription ??= _player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0) _durationMs = d.inMilliseconds;
    });
    _positionSubscription ??= _player.onPositionChanged.listen((p) {
      elapsedSec.value = p.inSeconds;
      if (_durationMs > 0) {
        progress.value = (p.inMilliseconds / _durationMs).clamp(0.0, 1.0);
      }
    });
    _completeSubscription ??= _player.onPlayerComplete.listen((_) => _reset());
  }

  /// Play / pause / switch note — the single entry point used by bubbles.
  ///
  /// SERIALIZED LIFECYCLE (CodeRabbit): concurrent teardowns and reseeds
  /// (dispose while toggle is mid-flight, two toggles racing) used to touch
  /// the same native player from overlapping async gaps — a use-after-dispose
  /// crash. Every operation funnels through [_lifecycle], a FIFO chain, so
  /// teardown strictly serializes before any reseed that follows it.
  static Future<void> toggle(String path, {BuildContext? context}) {
    // CONTEXT CAPTURED SYNCHRONOUSLY (use_build_context_synchronously): the
    // messenger and the localized message are resolved HERE, before the FIFO
    // chain's async gap — no BuildContext ever crosses into [_toggle].
    final messenger = (context != null && context.mounted)
        ? ScaffoldMessenger.maybeOf(context)
        : null;
    final unavailableMsg = context == null
        ? null
        : tr(context,
            fr: 'Lecture audio indisponible', ar: 'تعذّر تشغيل الصوت');
    final next =
        _lifecycle.then((_) => _toggle(path, messenger, unavailableMsg));
    // FIFO CHAIN (CodeRabbit): the chain must be REASSIGNED — leaving
    // [_lifecycle] untouched meant concurrent teardowns and toggles were NOT
    // serialized (a use-after-dispose crash window). The trailing swallow
    // keeps later operations flowing when a step fails.
    _lifecycle = next.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return next;
  }

  static Future<void> _toggle(
    String path,
    ScaffoldMessengerState? messenger,
    String? unavailableMsg,
  ) async {
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
      // REMOTE-AWARE SOURCE (Supabase Storage migration): a note uploaded to
      // the shared `chat-media` bucket carries an https URL — audioplayers
      // needs a UrlSource for it. A local file keeps using DeviceFileSource,
      // so the offline fallback path works exactly as before.
      final isRemote =
          path.startsWith('http://') || path.startsWith('https://');
      await _player.play(
        isRemote ? UrlSource(path) : DeviceFileSource(path),
      );
      isPlaying.value = true;
    } catch (e) {
      debugPrint('VoiceNotePlayer.toggle failed for "$path": $e');
      _reset();
      // MOUNTED GUARD (CodeRabbit): the messenger was captured BEFORE the
      // awaits above — after the async gap its State may already be
      // unmounted, and showing a SnackBar on a dead tree would throw.
      if (messenger != null && messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(unavailableMsg ?? 'Lecture audio indisponible'),
          ),
        );
      }
    }
  }

  static Future<void> pause() {
    final next = _lifecycle.then((_) => _pause());
    _lifecycle = next.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return next;
  }

  static Future<void> stop() {
    final next = _lifecycle.then((_) => _stop());
    _lifecycle = next.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return next;
  }

  static Future<void> _stop() async {
    try {
      if (_inited && !_needsReseed) await _player.stop();
    } catch (e) {
      debugPrint('VoiceNotePlayer.stop failed: $e');
    } finally {
      _reset();
    }
  }

  static Future<void> _pause() async {
    if (!_inited || !isPlaying.value) return;
    try {
      await _player.pause();
      isPlaying.value = false;
    } catch (e) {
      debugPrint('VoiceNotePlayer.pause failed: $e');
      _reset();
    }
  }

  static Future<void> dispose() {
    final next = _lifecycle.then((_) => _dispose());
    _lifecycle = next.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return next;
  }

  static Future<void> _dispose() async {
    // DOUBLE-DISPOSE GUARD: a second teardown without an intervening
    // [_ensureInit] reseed would call `dispose()` on an already-dead native
    // player — return early, the subscriptions and notifiers are already in
    // their torn-down / stable state.
    if (_needsReseed) return;
    // NOTIFIER LIFETIME (CodeRabbit): the four static ValueNotifiers are
    // process-wide singletons — they are NEVER disposed or reassigned here.
    // They outlive every AudioPlayer teardown so already-built bubble widgets
    // keep listening to a stable notifier instance; disposing them would crash
    // later ValueListenableBuilder reads with "used after disposed".
    //
    // RESEED FLAG (CodeRabbit): because the notifiers survive, a later
    // [toggle]/[pause] after this teardown must NOT touch the dead native
    // player — [_needsReseed] forces [_ensureInit] to reseed a fresh one.
    // Only reset the visible state when a note was actually active: clearing
    // unconditionally would wipe a sibling screen's playback UI on exit.
    final wasActive =
        playingPath.value != null || isPlaying.value || progress.value != 0;
    // PROTECTIVE TEARDOWN (CodeRabbit): the WHOLE cleanup sequence lives in a
    // try/finally. Previously a throwing `cancel()` (or any exception raised
    // between the cancels and the native dispose) ABORTED the sequence — the
    // subscriptions stayed armed, the player was never released and the
    // lifecycle flags below were never restored, so the store kept believing
    // it owned a live player (the next [toggle] then touched a zombie
    // AudioPlayer). Now every step is individually guarded AND the final
    // flag/flush work is guaranteed by the `finally` block.
    try {
      await _cancelSubscription(_durationSubscription, 'onDurationChanged');
      await _cancelSubscription(_positionSubscription, 'onPositionChanged');
      await _cancelSubscription(_completeSubscription, 'onPlayerComplete');
    } finally {
      // Failures above must never leave a dangling handle behind.
      _durationSubscription = null;
      _positionSubscription = null;
      _completeSubscription = null;
      try {
        await _player.dispose();
      } catch (e) {
        debugPrint('VoiceNotePlayer.dispose failed: $e');
      } finally {
        // TEARDOWN-FAILURE SAFETY (CodeRabbit): the lifecycle flags are
        // restored EITHER WAY — a failed native dispose must never leave the
        // store believing it still owns a live player (a later [toggle] would
        // touch a zombie AudioPlayer instance). [_needsReseed] forces
        // [_ensureInit] to build a fresh player before any further playback.
        _inited = false;
        _needsReseed = true;
        if (wasActive) _reset();
      }
    }
  }

  /// Cancels ONE subscription inside its own guard, so a failure on a single
  /// stream can never abort the teardown of the remaining ones.
  static Future<void> _cancelSubscription(
    StreamSubscription<Object?>? subscription,
    String label,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } catch (e) {
      debugPrint('VoiceNotePlayer.dispose: $label cancel failed: $e');
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
