import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/core/services/onesignal_service.dart';

/// Regression tests for the OneSignal initialization SINGLE-FLIGHT lock
/// (CodeRabbit polish round).
///
/// `initialize()` is check-then-act on the `isInitialized` flag, so without
/// the lock two callers landing in the same turn (startup + a login-triggered
/// retry, or two screens restoring a session at once) would both start the
/// SDK and race the native layer. With the lock, the first caller owns the
/// attempt and every concurrent caller simply awaits its future.
///
/// The test environment has no native plugin, so the attempt itself is the
/// documented no-op skip — which is exactly what lets the lock be observed:
/// the delay seam (`debugInitDelay`) keeps the lock held while the extra
/// callers join it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    OneSignalService.debugInitDelay = Duration.zero;
    OneSignalService.debugReset();
  });

  test('concurrent initialize() calls collapse into a single attempt',
      () async {
    OneSignalService.debugReset();
    OneSignalService.debugInitDelay = const Duration(milliseconds: 50);

    final first = OneSignalService.initialize();
    final second = OneSignalService.initialize();
    final third = OneSignalService.initialize();

    expect(OneSignalService.debugInitInFlight, isTrue,
        reason: 'the first caller holds the lock until its attempt ends');
    expect(OneSignalService.debugInitAttempts, 1,
        reason: 'the other two joined the in-flight attempt');

    await Future.wait(<Future<void>>[first, second, third]);

    expect(OneSignalService.debugInitAttempts, 1,
        reason: 'no second initialization may ever start');
    expect(OneSignalService.isInitialized, isTrue);
    expect(OneSignalService.debugInitInFlight, isFalse,
        reason: 'the lock is released once the attempt completes');
  });

  test('initialize() after completion is a no-op (idempotent)', () async {
    OneSignalService.debugReset();

    await OneSignalService.initialize();
    expect(OneSignalService.debugInitAttempts, 1);
    expect(OneSignalService.isInitialized, isTrue);

    await OneSignalService.initialize();
    expect(OneSignalService.debugInitAttempts, 1,
        reason: 'an already-initialized service must not re-initialize');
  });

  test('a reset allows a clean re-initialization', () async {
    OneSignalService.debugReset();
    await OneSignalService.initialize();

    OneSignalService.debugReset();
    expect(OneSignalService.isInitialized, isFalse);
    expect(OneSignalService.debugInitInFlight, isFalse);

    await OneSignalService.initialize();
    expect(OneSignalService.isInitialized, isTrue);
    expect(OneSignalService.debugInitAttempts, 1,
        reason: 'debugReset restarts the attempt accounting too');
  });

  test('initialize() never throws in a test environment', () async {
    OneSignalService.debugReset();
    // The skip path resolves normally; awaiting must never rethrow.
    await expectLater(OneSignalService.initialize(), completes);
    expect(OneSignalService.isInitialized, isTrue);
  });
}
