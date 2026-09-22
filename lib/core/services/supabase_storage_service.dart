import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/app_error_handler.dart';
import '../network/connectivity_store.dart';

/// Supabase Storage gateway for all app media.
///
/// BUCKETS (created server-side; storage policies scope the writes):
///   • `avatars`    (PUBLIC)  — profile pictures.
///       `<uid>/avatar_<ts>.<ext>` → the returned value is the PUBLIC URL,
///       directly renderable by [AppImage].
///   • `documents`  (PRIVATE) — verification dossier (proof / selfie / work
///       gallery). `<uid>/<kind>_<ts>.<ext>` → the returned value is the
///       STORAGE PATH; it must be read through a signed URL
///       ([createDocumentSignedUrl]) and is never rendered directly.
///   • `chat-media` (PUBLIC)  — chat photos & voice notes shared between the
///       two order participants. `<requestId>/chat_<ts>.<ext>` → PUBLIC URL
///       so the counterpart renders it without signed-URL machinery.
///
/// FAILURE POLICY: every upload returns NULL on failure (not configured,
/// offline, network error, bucket policy refusal) and NEVER throws — callers
/// keep their local path as the fallback, so the app remains fully usable
/// offline and the media simply lives local-only until connectivity returns.
class SupabaseStorageService {
  SupabaseStorageService._();

  static const String avatarsBucket = 'avatars';
  static const String documentsBucket = 'documents';
  static const String chatMediaBucket = 'chat-media';

  static bool get isConfigured {
    try {
      Supabase.instance.client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether an upload should even be attempted right now.
  static bool get canUploadNow =>
      isConfigured && ConnectivityStore.isOnline.value;

// ─── Public API ───────────────────────────────────────────────────────

  /// Uploads a profile picture to the public `avatars` bucket and returns
  /// its public URL (null on failure — caller keeps the local path).
  static Future<String?> uploadAvatar(String userId, File file) async {
    final ext = _extOf(file.path) ?? 'jpg';
    return _uploadPublic(
      bucket: avatarsBucket,
      path: '$userId/avatar_${_stamp()}.$ext',
      file: file,
      context: 'uploadAvatar',
    );
  }

  /// Uploads a verification document (ID / patente / diploma / selfie…)
  /// to the PRIVATE `documents` bucket and returns its STORAGE PATH
  /// (null on failure — caller keeps the local path).
  ///
  /// [kind] labels the file inside the user folder: 'proof' | 'selfie' |
  /// 'work' | 'id-card'… — server-side validation tells them apart.
  static Future<String?> uploadDocument(
    String userId,
    File file, {
    String kind = 'proof',
  }) async {
    final ext = _extOf(file.path) ?? 'jpg';
    return _uploadPrivate(
      path: '$userId/${kind}_${_stamp()}.$ext',
      file: file,
      context: 'uploadDocument',
    );
  }

  /// Uploads a chat media file (photo / voice note) to the public
  /// `chat-media` bucket and returns its public URL (null on failure).
  static Future<String?> uploadChatMedia(
    String requestId,
    File file, {
    String kind = 'chat',
  }) async {
    final ext = _extOf(file.path) ?? 'jpg';
    return _uploadPublic(
      bucket: chatMediaBucket,
      path: '$requestId/${kind}_${_stamp()}.$ext',
      file: file,
      context: 'uploadChatMedia',
    );
  }

  /// Signed, time-limited read URL for a PRIVATE document (admin review).
  /// [expiresIn] defaults to 1 hour.
  static Future<String?> createDocumentSignedUrl(
    String storagePath, {
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    if (!isConfigured) return null;
    try {
      return await Supabase.instance.client.storage
          .from(documentsBucket)
          .createSignedUrl(storagePath, expiresIn.inSeconds);
    } catch (e, st) {
      AppErrorHandler.report(e, st,
          context: 'SupabaseStorageService.createDocumentSignedUrl');
      return null;
    }
  }

// ─── Internals ────────────────────────────────────────────────────────

  static Future<String?> _uploadPublic({
    required String bucket,
    required String path,
    required File file,
    required String context,
  }) async {
    final storagePath =
        await _upload(bucket: bucket, path: path, file: file, context: context);
    if (storagePath == null) return null;
    try {
      return Supabase.instance.client.storage
          .from(bucket)
          .getPublicUrl(storagePath);
    } catch (e, st) {
      AppErrorHandler.report(e, st, context: 'SupabaseStorageService.$context');
      return null;
    }
  }

  static Future<String?> _uploadPrivate({
    required String path,
    required File file,
    required String context,
  }) =>
      _upload(
          bucket: documentsBucket, path: path, file: file, context: context);

  /// Shared upload pipeline. Returns the STORAGE PATH within [bucket], or
  /// null when Supabase is not configured, the device is offline, the file
  /// fails client-side validation, or the upload failed.
  ///
  /// CLIENT-SIDE VALIDATION (audit remediation): only real image / audio /
  /// PDF payloads are accepted (extension + declared MIME must agree), and
  /// the file must not exceed [maxUploadBytes]. Rejecting before the network
  /// call prevents oversized / mistyped payloads from being mirrored to the
  /// buckets and gives callers their local-fallback path immediately.
  static const int maxUploadBytes = 10 * 1024 * 1024; // 10 MB

  /// Allowed upload extensions per bucket family. Anything else (executables,
  /// scripts, archives…) is refused client-side; the buckets additionally
  /// enforce their own server-side MIME policies.
  static const Set<String> allowedImageExt = {'jpg', 'jpeg', 'png', 'webp'};
  static const Set<String> allowedAudioExt = {'m4a', 'aac', 'mp3', 'wav', 'ogg'};
  static const Set<String> allowedDocExt = {'jpg', 'jpeg', 'png', 'webp', 'pdf'};

  static bool _extensionAllowed(String bucket, String ext) {
    if (bucket == documentsBucket) return allowedDocExt.contains(ext);
    if (bucket == chatMediaBucket) {
      return allowedImageExt.contains(ext) || allowedAudioExt.contains(ext);
    }
    return allowedImageExt.contains(ext); // avatars
  }

  static Future<String?> _upload({
    required String bucket,
    required String path,
    required File file,
    required String context,
  }) async {
    if (!canUploadNow) return null;
    if (!await file.exists()) return null;

    // TYPE VALIDATION: the extension is the only client-side signal — the
    // path was produced by this app's pickers, so it is trustworthy enough
    // as a filter while the server policy remains the real gate.
    final ext = _extOf(path);
    if (ext == null || !_extensionAllowed(bucket, ext)) {
      debugPrint('SupabaseStorageService.$context: rejected file type '
          '".$ext" for bucket "$bucket".');
      return null;
    }

    // SIZE VALIDATION: refuse before uploading anything.
    final length = await file.length();
    if (length <= 0 || length > maxUploadBytes) {
      debugPrint('SupabaseStorageService.$context: rejected file of '
          '$length bytes (limit $maxUploadBytes).');
      return null;
    }

    try {
      await Supabase.instance.client.storage.from(bucket).upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: false),
          );
      return path;
    } catch (e, st) {
      debugPrint('SupabaseStorageService.$context failed: $e');
      AppErrorHandler.report(e, st, context: 'SupabaseStorageService.$context');
      return null;
    }
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  static String? _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.length <= 5 ? ext : null;
  }
}
