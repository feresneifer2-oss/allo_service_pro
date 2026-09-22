import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/shared/widgets/app_image.dart';

/// Regression guard for the CodeRabbit "aspect-ratio" feedback.
///
/// `Image.asset/file/network(..., cacheWidth: w, cacheHeight: h)` builds its
/// resize through `ResizeImage.resizeIfNeeded`, which uses the DEFAULT policy
/// `ResizeImagePolicy.exact` — documented as "similar to BoxFit.fill", i.e. the
/// decoded bitmap is squashed to EXACTLY w×h whatever the source ratio is.
/// [AppImage] therefore has to wrap its provider EXPLICITLY with
/// [ResizeImagePolicy.fit] so the decode stays proportional.
void main() {
  Future<ResizeImage> resizeOf(WidgetTester tester, String path) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, height: 100, child: AppImage(path)),
          ),
        ),
      ),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image;
    expect(provider, isA<ResizeImage>(),
        reason: 'the decode must be explicitly bounded');
    return provider as ResizeImage;
  }

  testWidgets('remote source decodes with the proportional (fit) policy',
      (tester) async {
    final resize = await resizeOf(tester, 'https://example.com/proof.png');

    expect(resize.policy, ResizeImagePolicy.fit,
        reason: 'exact (= BoxFit.fill) would STRETCH the proof');
    expect(resize.imageProvider, isA<NetworkImage>());
    expect(resize.allowUpscaling, isFalse);
    // Both axes are bounded to the tile in device pixels (max 1024).
    expect(resize.width, isNotNull);
    expect(resize.height, isNotNull);
    expect(resize.width! <= 1024, isTrue);
    expect(resize.height! <= 1024, isTrue);
  });

  testWidgets('local file source keeps the proportional (fit) policy',
      (tester) async {
    final resize = await resizeOf(tester, '/tmp/does-not-exist.jpg');
    expect(resize.policy, ResizeImagePolicy.fit);
    expect(resize.imageProvider, isA<FileImage>());
  });

  testWidgets('bundled asset source keeps the proportional (fit) policy',
      (tester) async {
    final resize = await resizeOf(tester, 'assets/images/logo.png');
    expect(resize.policy, ResizeImagePolicy.fit);
    expect(resize.imageProvider, isA<AssetImage>());
  });

  testWidgets('a circle forces SQUARE cache dimensions (no rim artifacts)',
      (tester) async {
    // A deliberately RECTANGULAR box: the rectangular decode a square clip
    // would otherwise inherit is exactly what must be normalized away.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 100,
              child: AppImage('/tmp/circle.jpg', circle: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final resize =
        tester.widget<Image>(find.byType(Image).first).image as ResizeImage;
    expect(resize.width, resize.height,
        reason: 'a circular clip must decode from a 1:1 bitmap');
    expect(resize.policy, ResizeImagePolicy.fit);
  });

  testWidgets('a non-circle keeps the rectangle bounds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 100,
              child: AppImage('/tmp/rect.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final resize =
        tester.widget<Image>(find.byType(Image).first).image as ResizeImage;
    expect(resize.width, isNot(resize.height));
  });

  testWidgets('switching path clears the stale notification markers',
      (tester) async {
    // An absent/empty path notifies SYNCHRONOUSLY (no decode needed), which
    // makes the per-path markers directly observable through the counters:
    // `null` and `''` are two DIFFERENT path values hitting the same branch,
    // so the second one is a genuine "path changed" rebind.
    var errorsNull = 0;
    var errorsEmpty = 0;

    Widget build(String? path) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              height: 80,
              child: AppImage(
                path,
                onLoadError:
                    path == null ? () => errorsNull++ : () => errorsEmpty++,
              ),
            ),
          ),
        );

    await tester.pumpWidget(build(null));
    await tester.pump();
    expect(errorsNull, 1);

    // Same path again: the marker DEDUPLICATES (one notification per image).
    await tester.pumpWidget(build(null));
    await tester.pump();
    expect(errorsNull, 1, reason: 'duplicate notifications must stay deduped');

    // Rebind to a different path: the stale marker is dropped, so this load
    // is reported — the assertion that fails if cleanup is skipped.
    await tester.pumpWidget(build(''));
    await tester.pump();
    expect(errorsEmpty, 1,
        reason: 'a stale marker must never silence a legitimate re-notify');
  });

  testWidgets('an empty path never builds an image (placeholder only)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 80, height: 80, child: AppImage('')),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
  });
}
