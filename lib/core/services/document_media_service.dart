import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Real image picking for NEW-FEATURE surfaces: proof of work, service
/// documents (diploma / patent / license / card), the selfie-with-document,
/// the work gallery and — later — profile pictures.
///
/// Chat already has its own seam ([ChatMediaService]); this one exists so the
/// pro onboarding flow stops faking captures with
/// `setState(_docUploaded = true)` and starts producing REAL, durable files
/// ready to be uploaded to Supabase Storage (the stored absolute path is
/// exactly what an upload task will read).
///
/// All plugin calls are isolated here — screens stay declarative and
/// testable. Every method returns null (and never throws) when the user
/// cancels, a permission is denied, or the platform picker fails.
class DocumentMediaService {
  DocumentMediaService._();

  static final ImagePicker _picker = ImagePicker();

  /// Durable sub-folder of the app documents directory: unlike a cache dir,
  /// its content survives app updates (the registration flow stores these
  /// absolute paths and the admin review reads them later).
  static const String _dirName = 'pro_media';

  /// Captures/picks a document photo and copies it into the durable
  /// `pro_media` folder. Returns the ABSOLUTE local path, or null on
  /// cancel/failure.
  ///
  /// Documents must stay legible for the admin review: downscale the long
  /// edge to 2048 px at quality 85 — large enough to read a stamp, small
  /// enough for a future Storage upload.
  static Future<String?> pickDocument({required bool fromCamera}) =>
      _pickAndPersist(
        fromCamera: fromCamera,
        maxWidth: 2048,
        imageQuality: 85,
        prefix: 'doc',
      );

  /// Same contract for the selfie-with-document (kept separate so the flow
  /// can label the stored file and the future server-side validation can
  /// tell the two apart).
  static Future<String?> pickSelfieWithDocument({required bool fromCamera}) =>
      _pickAndPersist(
        fromCamera: fromCamera,
        maxWidth: 2048,
        imageQuality: 85,
        prefix: 'selfie',
      );

  /// Picks a work-gallery photo (lighter: preview tiles only, 1440 px / 72 —
  /// the same budget the chat uses).
  static Future<String?> pickWorkPhoto({required bool fromCamera}) =>
      _pickAndPersist(
        fromCamera: fromCamera,
        maxWidth: 1440,
        imageQuality: 72,
        prefix: 'work',
      );

  /// Shared pipeline: pick → copy to the durable folder → absolute path.
  static Future<String?> _pickAndPersist({
    required bool fromCamera,
    required int maxWidth,
    required int imageQuality,
    required String prefix,
  }) async {
    try {
      final xfile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxWidth.toDouble(),
        imageQuality: imageQuality,
      );
      if (xfile == null) return null;
      return await _persist(File(xfile.path), prefix);
    } catch (_) {
      return null;
    }
  }

  /// Copies [source] into `pro_media` and returns the new absolute path.
  ///
  /// FAILURE CONTRACT (CodeRabbit): when the durable copy fails (read-only
  /// storage, disk full, permission error) this returns NULL — it NEVER
  /// falls back to the picker's original volatile path. A temp/cache path
  /// vanishes on the next cleanup (and never survives app updates), so
  /// returning it would bind a "proof" that admin review — and the future
  /// Supabase Storage upload — cannot read later. Callers already treat
  /// null as "no capture" and surface actionable feedback.
  static Future<String?> _persist(File source, String prefix) async {
    try {
      final dir = await _mediaDir();
      final target =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final copied = await source.copy(target);
      return copied.path;
    } catch (e) {
      debugPrint('DocumentMediaService: persisting "$prefix" failed: $e');
      return null;
    }
  }

  static Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes a media file previously returned by this service — the cleanup
  /// hook for captures whose submission was REFUSED by the store.
  ///
  /// ORPHAN GUARD (CodeRabbit): every capture is copied into the durable
  /// `pro_media` folder (see [_persist]), so a capture that is never bound to
  /// a registry entry — e.g. the pro carries no matching dossier and the
  /// resubmission is rejected — would linger there forever, wasting storage
  /// and leaving a stale "proof" the admin might later reconcile by accident.
  ///
  /// SAFETY CONTRACT:
  ///  * only paths that resolve INSIDE the durable media folder are deleted
  ///    (a crafted/legacy path can never remove an unrelated user file);
  ///  * best-effort and never throws — a cleanup failure is logged and
  ///    returns `false` so the caller's flow is never broken by storage;
  ///  * returns `true` only when the file is confirmed gone.
  static Future<bool> discard(String? path) async {
    final raw = path?.trim();
    if (raw == null || raw.isEmpty) return false;
    try {
      final dir = await _mediaDir();
      // Containment check by CANONICALIZATION (never by string prefix): both
      // sides go through `resolveSymbolicLinks()`, which collapses `..`,
      // duplicated separators and symlinks. A crafted/legacy path such as
      // `<media>/../other.jpg` therefore resolves to its REAL parent and is
      // refused — a naive `startsWith` check would have accepted it and
      // deleted a file outside the folder.
      final mediaDir = (await dir.resolveSymbolicLinks()).replaceAll('\\', '/');
      final target = File(raw);
      final parentDir =
          (await target.parent.resolveSymbolicLinks()).replaceAll('\\', '/');
      // The capture must live DIRECTLY inside the media folder: anything
      // above it, beside it, or in a nested sub-folder is out of scope.
      if (parentDir != mediaDir) {
        debugPrint('DocumentMediaService: refusing to discard a path outside '
            'the $_dirName folder.');
        return false;
      }
      if (!await target.exists()) return true; // already gone: nothing to do
      await target.delete();
      return true;
    } catch (e) {
      debugPrint('DocumentMediaService: discarding "$raw" failed: $e');
      return false;
    }
  }

  /// Test hook: lets a test observe the durable folder location.
  @visibleForTesting
  static Future<Directory> debugMediaDir() => _mediaDir();
}
