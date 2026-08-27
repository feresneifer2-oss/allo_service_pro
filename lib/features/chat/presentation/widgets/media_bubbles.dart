import 'dart:io';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import '../../models/chat_message.dart';
import 'voice_note_player.dart';

/// Rich-media chat bubbles — identical for both roles, only the side
/// mirrors. Voice notes use the shared [VoiceNotePlayer]; photos open a
/// full-screen preview. Palette: blue / orange / white / slate only.
class ChatMediaBubble extends StatelessWidget {
  const ChatMediaBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: message.isVoice
          ? _VoiceBody(message: message, isMine: isMine)
          : _PhotoBody(message: message, isMine: isMine),
    );
  }
}

class _VoiceBody extends StatelessWidget {
  const _VoiceBody({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceNotePlayer.playingPath,
      builder: (_, current, __) {
        final isActive = current == message.mediaPath;
        return ValueListenableBuilder<bool>(
          valueListenable: VoiceNotePlayer.isPlaying,
          builder: (_, playing, __) => ValueListenableBuilder<double>(
            valueListenable: VoiceNotePlayer.progress,
            builder: (_, progress, ___) {
              final elapsed = isActive ? VoiceNotePlayer.elapsedSec.value : 0;
              final total = message.voiceDurationSec;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => VoiceNotePlayer.toggle(message.mediaPath!),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isMine ? Colors.white : AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive && playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: isMine ? AppColors.primary : Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: isActive ? progress : 0,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          backgroundColor: isMine
                              ? Colors.white.withValues(alpha: .3)
                              : AppColors.primarySurface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              isMine ? Colors.white : AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isActive
                              ? '${_fmt(elapsed)} / ${_fmt(total)}'
                              : _fmt(total),
                          style: TextStyle(
                            fontSize: 11,
                            color: isMine
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PhotoBody extends StatelessWidget {
  const _PhotoBody({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final path = message.mediaPath ?? '';
    return GestureDetector(
      onTap: () => showChatPhotoPreview(context, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 200,
            color: isMine
                ? Colors.white.withValues(alpha: .15)
                : AppColors.slate800,
            child: const Icon(
              Icons.broken_image_rounded,
              color: Colors.white70,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen pinch-to-zoom photo preview shared by both roles.
void showChatPhotoPreview(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    barrierColor: AppColors.slate900.withValues(alpha: .96),
    builder: (_) => Dialog.fullscreen(
      backgroundColor: AppColors.slate900,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.file(
                  File(path),
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white70,
                    size: 64,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: tr(context, fr: 'Fermer', ar: 'إغلاق'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}