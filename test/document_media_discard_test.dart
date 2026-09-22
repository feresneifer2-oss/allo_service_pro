import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/services/document_media_service.dart';

/// Regression guard for the CodeRabbit "orphaned proof files" feedback.
///
/// Every capture is copied into the durable `pro_media` folder, so a
/// resubmission the store REFUSED would leave an unreferenced file behind
/// unless it is explicitly discarded. These tests pin the cleanup contract:
/// it really deletes files inside `pro_media`, refuses anything outside it,
/// and never throws.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('allo_media_test');
    // path_provider's default platform implementation is the method channel
    // one in tests (no plugin registrant runs), so mocking it here routes
    // `getApplicationDocumentsDirectory()` to a real temporary directory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return root.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> seedMediaFile(String name) async {
    final dir = Directory('${root.path}/pro_media');
    await dir.create(recursive: true);
    return File('${dir.path}/$name')..writeAsStringSync('proof');
  }

  test('discard() deletes a capture inside pro_media', () async {
    final file = await seedMediaFile('doc_1.jpg');
    expect(await file.exists(), isTrue);

    expect(await DocumentMediaService.discard(file.path), isTrue);
    expect(await file.exists(), isFalse);
  });

  test('discard() refuses any path outside pro_media', () async {
    // Build the REAL directory structure FIRST: the traversal path below
    // carries `pro_media` as an intermediate segment, so without that folder
    // on disk the write could fail (or resolve differently) and the test
    // would pass for the WRONG reason — a missing directory rather than a
    // genuinely refused path.
    final mediaDir = Directory('${root.path}/pro_media')
      ..createSync(recursive: true);
    expect(mediaDir.existsSync(), isTrue,
        reason: 'the media folder must exist to simulate a real device');

    final outsider = File('${root.path}/unrelated.jpg')
      ..writeAsStringSync('keep me');
    final traversal = File('${mediaDir.path}/../escape.jpg')
      ..writeAsStringSync('keep me too');

    // Sanity: the crafted path REALLY resolves outside the media folder, so
    // the refusal below is a security assertion, not an accident of layout.
    final canonicalMedia =
        (await mediaDir.resolveSymbolicLinks()).replaceAll('\\', '/');
    final canonicalTraversalParent =
        (await traversal.parent.resolveSymbolicLinks()).replaceAll('\\', '/');
    expect(canonicalTraversalParent, isNot(canonicalMedia));

    expect(await DocumentMediaService.discard(outsider.path), isFalse);
    expect(await outsider.exists(), isTrue,
        reason: 'a capture never owns files outside the media folder');
    expect(await DocumentMediaService.discard(traversal.path), isFalse);
    expect(await traversal.exists(), isTrue);
  });

  test('discard() is a safe no-op for null/blank and missing files', () async {
    expect(await DocumentMediaService.discard(null), isFalse);
    expect(await DocumentMediaService.discard('   '), isFalse);
    // A path inside the folder that was already removed reports success.
    final missing = '${root.path}/pro_media/gone.jpg';
    expect(await DocumentMediaService.discard(missing), isTrue);
  });
}
