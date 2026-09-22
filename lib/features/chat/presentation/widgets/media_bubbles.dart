import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/app_image.dart';

import '../../models/chat_message.dart';
import 'voice_note_player.dart';

/// True when [path] is a remote media URL (a Supabase Storage public URL)
/// rather than a device file path or a bundled asset.
bool isRemoteMediaPath(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// Normalizes a media path for EQUALITY checks (CodeRabbit): strips the
/// `file://` scheme and any trailing slashes so a device URI
/// (`file:///data/.../note.m4a`) compares equal to the plain path
/// (`/data/.../note.m4a`) recorded by the recorder / the remote row.
String normalizeMediaPath(String raw) {
  var p = raw.trim();
  if (p.startsWith('file://')) p = p.substring('file://'.length);
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

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
          : message.isPhoto
              ? _PhotoBody(message: message, isMine: isMine)
              : message.isLocation
                  ? _LocationBody(message: message, isMine: isMine)
                  : const SizedBox.shrink(),
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
    final path = message.mediaPath?.trim() ?? '';
    // REMOTE-AWARE AVAILABILITY (Supabase Storage): an uploaded note carries
    // an https URL and has NO local file — `File(url).existsSync()` is
    // therefore false and would wrongly disable the play button on every
    // received note.
    // LOCAL-URI NORMALIZATION (CodeRabbit): a `file:///…` URI must be
    // stripped to an absolute path BEFORE the availability check, or
    // `File(...).existsSync()` is always false for device-local notes.
    final available = path.isNotEmpty &&
        (isRemoteMediaPath(path) ||
            File(normalizeMediaPath(path)).existsSync());
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceNotePlayer.playingPath,
      builder: (_, current, __) {
        final isActive = normalizeMediaPath(current ?? '') ==
            normalizeMediaPath(message.mediaPath ?? '');
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
                    onTap: available
                        ? () => VoiceNotePlayer.toggle(path, context: context)
                        : null,
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
                  if (!available) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.broken_image_rounded,
                        size: 18, color: Colors.white70),
                  ],
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
                            color:
                                isMine ? Colors.white : AppColors.textSecondary,
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
    final path = message.mediaPath?.trim() ?? '';
    if (path.isEmpty) {
      return _missingPhoto(isMine);
    }
    return GestureDetector(
      onTap: () => showChatPhotoPreview(context, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // REMOTE-AWARE RENDERING (Supabase Storage): [AppImage] resolves a
        // local file OR an https Storage URL with the same bounded,
        // overflow-proof pipeline the rest of the app uses.
        child: SizedBox(
          width: 200,
          height: 200,
          child: AppImage(
            path,
            fit: BoxFit.cover,
            errorIcon: Icons.broken_image_rounded,
            placeholderColor: isMine
                ? Colors.white.withValues(alpha: .15)
                : AppColors.slate800,
          ),
        ),
      ),
    );
  }

  Widget _missingPhoto(bool isMine) => Container(
        width: 200,
        height: 200,
        color:
            isMine ? Colors.white.withValues(alpha: .15) : AppColors.slate800,
        child: const Icon(Icons.broken_image_rounded,
            color: Colors.white70, size: 40),
      );
}

class _LocationBody extends StatelessWidget {
  const _LocationBody({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final lat = message.latitude;
    final lng = message.longitude;
    final hasCoords = lat != null && lng != null;

    return GestureDetector(
      onTap: hasCoords ? () => openInGoogleMaps(context, lat, lng) : null,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: .15)
              : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMine ? Colors.white : AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: isMine ? AppColors.primary : Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(context, fr: 'Position GPS', ar: 'الموقع الجغرافي'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isMine ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasCoords
                        ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                        : '—',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMine ? Colors.white70 : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.map_rounded,
                        size: 12,
                        color: isMine ? Colors.white : AppColors.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr(context,
                            fr: 'Ouvrir Google Maps', ar: 'فتح خرائط جوجل'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isMine ? Colors.white : AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Launches Google Maps with the given coordinates. Falls back to the
/// `geo:` URI on Android and the Google Maps web URL on other platforms.
Future<void> openInGoogleMaps(
  BuildContext context,
  double latitude,
  double longitude,
) async {
  // Universal Google Maps URL (works on web and mobile).
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context,
            fr: 'Impossible d\'ouvrir Google Maps',
            ar: 'تعذّر فتح خرائط جوجل')),
      ));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context,
            fr: 'Impossible d\'ouvrir Google Maps',
            ar: 'تعذّر فتح خرائط جوجل')),
      ));
    }
  }
}

/// Full-screen pinch-to-zoom photo preview shared by both roles.
///
/// REMOTE-AWARE (Supabase Storage): renders a local file AND an https
/// Storage URL through [AppImage] — the previous `Image.file` threw on a URL.
void showChatPhotoPreview(BuildContext context, String path) {
  final media = MediaQuery.of(context);
  showDialog<void>(
    context: context,
    barrierColor: AppColors.slate900.withValues(alpha: .96),
    builder: (_) => Dialog.fullscreen(
      backgroundColor: AppColors.slate900,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SizedBox(
                width: media.size.width,
                height: media.size.height * .8,
                child: InteractiveViewer(
                  maxScale: 4,
                  child: AppImage(
                    path,
                    fit: BoxFit.contain,
                    errorIcon: Icons.broken_image_rounded,
                    placeholderColor: Colors.transparent,
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
