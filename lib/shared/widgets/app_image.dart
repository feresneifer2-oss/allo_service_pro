import 'dart:io';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';

/// Overflow-proof image renderer for every user-supplied visual: proof of
/// work, service documents, work-gallery tiles, profile pictures — and later
/// Supabase Storage URLs.
///
/// WHY A CENTRAL WIDGET
/// ----------------------------------------------------------------
/// A raw `Image.file` with an unbounded source (a 8000×6000 document photo)
/// inside an unconstrained row/column blows the layout past its parent's
/// bounds — the classic RenderFlex-overflow crash of review screens. This
/// widget makes overflow STRUCTURALLY impossible:
///
///  * [bounded] first proves the incoming constraints are finite and
///    non-degenerate, else falls back to [fallbackSize] — so `Image` never
///    receives unbounded constraints;
///  * the image is ALWAYS wrapped in a clip ([ClipRRect], or [ClipOval] when
///    [circle] is set) sized to those exact bounds, so even a decoding
///    artifact cannot paint outside;
///  * [fit] defaults to [BoxFit.cover] (fill the tile, crop the excess) — the
///    safe choice for fixed-size tiles; pass `BoxFit.contain` for full-viewer
///    surfaces.
///
/// SOURCE SEPARATION (Supabase-ready): [AppImage.source] normalizes the three
/// runtime shapes — asset bundle path (`assets/…`), local file path (picked
/// by [image_picker] / copied into app documents), and a remote URL (http(s),
/// the future Supabase Storage public URL) — so call sites never branch on
/// the shape themselves.
///
/// LIFECYCLE CALLBACKS (CodeRabbit): [onLoaded] / [onLoadError] are deferred
/// past the build phase and deduplicated per image source — the underlying
/// `frameBuilder` / `errorBuilder` can fire MULTIPLE times for one image
/// (synchronous cache hits, retries, rebuilds, every failed decode attempt),
/// and invoking the caller's `setState` synchronously DURING the parent's
/// build throws. The stateful dispatcher below posts each notification ONCE
/// per distinct path via a post-frame callback, so the review-guard flags in
/// `admin_dashboard_screen` fire exactly once.
///
/// DECODE BOUNDING (CodeRabbit): the bitmap is decoded at the tile size
/// instead of the raw resolution (an 8000×6000 document photo decoded at full
/// size OOMs the app) — and that bound is applied through an EXPLICIT
/// `ResizeImagePolicy.fit` resize, because `Image(..., cacheWidth:, cacheHeight:)`
/// defaults to `ResizeImagePolicy.exact` ("similar to BoxFit.fill"), which
/// would STRETCH a non-matching aspect ratio. `fit` scales the source
/// proportionally inside the box: bounded memory AND undistorted geometry.
class AppImage extends StatefulWidget {
  const AppImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.circle = false,
    this.errorIcon = Icons.broken_image_rounded,
    this.placeholderColor = AppColors.primarySurface,
    this.fallbackSize = const Size(120, 120),
    this.onLoaded,
    this.onLoadError,
  });

  /// Asset path, local file path, or remote URL (see [source]).
  final String? path;

  /// How the image fills the resolved bounds. Defaults to [BoxFit.cover] so
  /// a photo of ANY aspect ratio stays inside the tile.
  final BoxFit fit;

  /// Corner radius of the clip (ignored when [circle] is true).
  final BorderRadius borderRadius;

  /// Clips to a circle (avatars / round gallery tiles).
  final bool circle;

  /// Shown centered when decoding fails (missing file, bad URL).
  final IconData errorIcon;

  /// Background while loading / on error.
  final Color placeholderColor;

  /// Square bounds used when the incoming constraints are unbounded or
  /// degenerate (raw lists, unconstrained dialogs).
  final Size fallbackSize;

  /// Fired once the first frame is DECODED (file / asset / network). The
  /// "unreadable proof" review guard relies on it: only a decoded image may
  /// count as reviewed.
  final void Function()? onLoaded;

  /// Fired when decoding FAILS (corrupted file, bad URL, missing asset).
  final void Function()? onLoadError;

  /// Which of the three supported sources the CURRENT [path] denotes.
  AppImageSource get source => AppImageSource.of(path);

  @override
  State<AppImage> createState() => _AppImageState();
}

/// Dispatches [AppImage]'s lifecycle callbacks exactly ONCE per distinct
/// image source: every notification is deduplicated on (path, outcome) and
/// posted via [WidgetsBinding.addPostFrameCallback] so the caller's
/// `setState` never runs synchronously inside the image builders.
class _AppImageState extends State<AppImage> {
  /// Paths already notified as successfully decoded.
  final Set<String> _notifiedLoaded = <String>{};

  /// Paths already notified as failed.
  final Set<String> _notifiedError = <String>{};

  /// STALE-MARKER CLEANUP (CodeRabbit): when the widget is rebound to a
  /// DIFFERENT image, the markers recorded for the previous path are dropped.
  /// They describe an asset that is no longer displayed — keeping them would
  /// (a) grow the sets without bound in a recycled list, and (b) silence a
  /// LEGITIMATE re-notification if the same asset is ever shown again (a
  /// re-upload revisits path A → B → A). Clearing per path change keeps every
  /// marker meaningful for exactly the image currently on screen.
  @override
  void didUpdateWidget(AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _notifiedLoaded.clear();
      _notifiedError.clear();
    }
  }

  /// Fires [callback] once per [path]: skips repeat notifications for a path
  /// that already reported this outcome, and defers the first one past the
  /// current build frame. The mounted guard covers callbacks landing after
  /// dispose.
  ///
  /// STALE-PATH GUARD (CodeRabbit): the widget's CURRENT path is captured at
  /// schedule time; when the post-frame callback executes, it is compared
  /// against the widget's LIVE path. A mismatch means the widget was rebound
  /// to a different image while this notification was pending (recycled list
  /// card, proof re-upload) — the stale callback is discarded immediately so
  /// an outdated asset can never fire lifecycle events into the new image's
  /// review state.
  void _notifyOnce({
    required String path,
    required Set<String> seen,
    required void Function()? callback,
  }) {
    if (callback == null || seen.contains(path)) return;
    seen.add(path);
    final scheduledWidgetPath = widget.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.path != scheduledWidgetPath) return;
      callback();
    });
  }

  void _fireLoaded(String imagePath) => _notifyOnce(
        path: imagePath,
        seen: _notifiedLoaded,
        callback: widget.onLoaded,
      );

  void _fireLoadError(String imagePath) => _notifyOnce(
        path: imagePath,
        seen: _notifiedError,
        callback: widget.onLoadError,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // BOUNDED GUARD: the one invariant everything else relies on.
        final wide = constraints.maxWidth;
        final high = constraints.maxHeight;
        final bool unbounded =
            !wide.isFinite || !high.isFinite || wide <= 0 || high <= 0;
        final size = unbounded ? widget.fallbackSize : Size(wide, high);

        // MEMORY + GEOMETRY GUARD (CodeRabbit): the DECODED bitmap is bounded
        // on BOTH axes to the box size in DEVICE pixels (max 1024), so an
        // 8000x6000 camera document or a 200x8000 banner scan decodes at
        // display resolution instead of raw resolution - without this, every
        // Image.file decodes the full bitmap and a handful of proof tiles can
        // OOM-crash the app. The bound is applied through an explicit
        // `ResizeImagePolicy.fit` resize (see below) so the source keeps its
        // natural width/height ratio while it scales: never squashed into the
        // box, never upscaled past the source (`allowUpscaling: false`).

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;

        int cacheW = (size.width * dpr).round().clamp(1, 1024).toInt();
        int cacheH = (size.height * dpr).round().clamp(1, 1024).toInt();
        if (widget.circle) {
          // SQUARE DECODE FOR CIRCULAR CLIPS (CodeRabbit): a circular surface
          // is inscribed in the box, so a non-square decode can only ever be
          // cropped by the `ClipOval` — an asymmetric resize (e.g. 300×100
          // inside a round avatar) makes the visible slice drift off the
          // geometric centre and softens the rim. Both axes are therefore
          // forced to the SAME value (the smaller side) before the resize, so
          // the decoded bitmap exactly matches the 1:1 circle geometry.
          final int square = cacheW < cacheH ? cacheW : cacheH;
          cacheW = square;
          cacheH = square;
        }

        final imagePath = widget.path;
        Widget content;
        if (imagePath == null || imagePath.isEmpty) {
          // EMPTY path: no image to decode — notify exactly once via the
          // post-frame dispatcher (never synchronously during this build).
          _fireLoadError('');
          content = _placeholder();
        } else {
          // ASPECT-RATIO-PRESERVING DECODE (CodeRabbit): a plain
          // `Image.asset/file/network(..., cacheWidth: w, cacheHeight: h)`
          // routes through `ResizeImage.resizeIfNeeded`, which builds the
          // resize with the DEFAULT policy `ResizeImagePolicy.exact` — the
          // Flutter docs describe that policy as "similar to BoxFit.fill":
          // the bitmap is scaled to EXACTLY w x h *regardless of the source
          // image's intrinsic aspect ratio* (a 300x200 photo lands in a
          // square, visibly stretched). The provider is therefore wrapped
          // EXPLICITLY with [ResizeImagePolicy.fit], which scales the source
          // PROPORTIONALLY to fit inside the w x h box (BoxFit.contain
          // semantics): `fit` derives the second dimension from the first
          // using the source's own natural width/height ratio, so the memory
          // bound on BOTH axes is preserved AND the geometry is never
          // distorted.
          final provider = ResizeImage(
            _providerFor(context, imagePath),
            width: cacheW,
            height: cacheH,
            policy: ResizeImagePolicy.fit,
            // Never upscale a small source past its native resolution.
            allowUpscaling: false,
          );
          content = Image(
            image: provider,
            fit: widget.fit,
            frameBuilder: (c, child, frame, sync) {
              if (frame != null) _fireLoaded(imagePath);
              return _frameBuilder(c, child, frame, sync);
            },
            // Never crash the frame on a failed/hostile fetch
            // (Supabase Storage, signed URLs, offline...).
            errorBuilder: (_, __, ___) {
              _fireLoadError(imagePath);
              return _placeholder(icon: widget.errorIcon);
            },
            // Progress placeholder ONLY for the remote source — the only one
            // that can stall between build and the first decoded frame.
            loadingBuilder: AppImageSource.of(imagePath) ==
                    AppImageSource.network
                ? (context, child, progress) {
                    // Placeholder during EVERY incomplete load —
                    // INCLUDING when the total size is UNKNOWN (streaming
                    // / chunked responses): `expectedTotalBytes == null`
                    // means completion cannot be known, so the
                    // placeholder stays until the first decodable frame
                    // arrives (the builder then stops firing and the real
                    // child renders).
                    if (progress == null) return child;
                    final total = progress.expectedTotalBytes;
                    final stillLoading =
                        total == null || progress.cumulativeBytesLoaded < total;
                    return stillLoading
                        ? _placeholder(
                            child:
                                const CircularProgressIndicator(strokeWidth: 2),
                          )
                        : child;
                  }
                : null,
          );
        }

        return SizedBox(
          width: size.width,
          height: size.height,
          child: widget.circle
              ? ClipOval(child: content)
              : ClipRRect(borderRadius: widget.borderRadius, child: content),
        );
      },
    );
  }

  /// Builds the EXACT provider the matching `Image.asset` / `Image.file` /
  /// `Image.network` constructor would have built — asset bundle included (so
  /// packaged assets keep resolving through [DefaultAssetBundle]) — which lets
  /// [build] wrap it in an explicit [ResizeImage] without changing any other
  /// resolution behavior.
  ImageProvider _providerFor(BuildContext context, String imagePath) {
    switch (AppImageSource.of(imagePath)) {
      case AppImageSource.asset:
        return AssetImage(imagePath, bundle: DefaultAssetBundle.of(context));
      case AppImageSource.file:
        return FileImage(File(imagePath));
      case AppImageSource.network:
        return NetworkImage(imagePath);
    }
  }

  /// Passthrough child renderer — lifecycle dispatch now happens in the
  /// per-source `frameBuilder` closures above (which capture their exact
  /// decoded path); this helper only returns the decoded child.
  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    return child;
  }

  Widget _placeholder({IconData? icon, Widget? child}) => Container(
        color: widget.placeholderColor,
        alignment: Alignment.center,
        child: child ??
            Icon(icon ?? Icons.image_outlined,
                color: AppColors.primary, size: 32),
      );
}

/// The three runtime image sources [AppImage] understands.
enum AppImageSource {
  asset,
  file,
  network;

  /// Normalizes a stored path/URL to a source. Remote URLs win over local
  /// files so a Supabase Storage URL (https://…) is fetched, never probed on
  /// disk; `assets/…` is the bundle; everything else is a local file.
  static AppImageSource of(String? path) {
    if (path == null) return AppImageSource.asset;
    final p = path.trim();
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return AppImageSource.network;
    }
    if (p.startsWith('assets/')) return AppImageSource.asset;
    return AppImageSource.file;
  }
}
