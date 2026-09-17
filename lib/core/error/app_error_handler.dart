import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:allo_service_pro/core/logging/app_logger.dart';
import 'package:allo_service_pro/shared/widgets/error_fallback_view.dart';

/// Global error boundary for the whole app.
///
/// WHAT IT GUARANTEES:
///  1. An unhandled exception (framework, platform/isolate, or a guarded async
///     task) is logged exactly once through [AppLogger] and retained in
///     [lastError] instead of tearing the app down.
///  2. A failing WIDGET renders the clean [AppErrorFallback] — never the red
///     "exception caught by widgets library" screen.
///  3. Asynchronous work in stores/services goes through [runGuarded], which
///     converts a crash into a logged no-op so the flow keeps working.
///
/// INSTALLATION: [install] is idempotent and must run before `runApp`
/// (see `main.dart`, which additionally wraps the boot sequence in
/// `runZonedGuarded`). The previous `FlutterError.onError` is always chained,
/// so the test framework still records every error.
class AppErrorHandler {
  AppErrorHandler._();

  /// Last reported error (null = healthy). Drives the fallback UI and is the
  /// single flag a "Retry" action clears.
  static final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);

  static bool _installed = false;

  /// Handlers captured the FIRST time the boundary was installed. They are
  /// restored verbatim by [debugReset] so no test can leak the boundary (or a
  /// test-runner reporter) into the next one.
  static FlutterExceptionHandler? _previousOnError;
  static bool Function(Object, StackTrace)? _previousPlatformOnError;
  static ErrorWidgetBuilder? _previousErrorWidgetBuilder;

  /// Whether the boundary is active (asserted by tests / diagnostics).
  static bool get isInstalled => _installed;

  /// Installs the boundary. Idempotent unless [force] is set (tests).
  static void install({bool force = false}) {
    if (_installed && !force) return;
    // Snapshot the environment once: a forced re-install must not capture our
    // own wrappers as the "previous" handlers.
    final wasInstalled = _installed;
    _installed = true;

    if (!wasInstalled) {
      _previousOnError = FlutterError.onError;
      _previousPlatformOnError = PlatformDispatcher.instance.onError;
      _previousErrorWidgetBuilder = ErrorWidget.builder;
    }

    // 1. Flutter framework errors (build/layout/paint + async framework jobs).
    final previousOnError = _previousOnError;
    FlutterError.onError = (FlutterErrorDetails details) {
      report(
        details.exception,
        details.stack,
        context: details.library ?? 'flutter',
      );
      // Kept so widget tests still see the exception and can assert on it.
      previousOnError?.call(details);
    };

    // 2. Platform / root-isolate errors outside the Flutter zone. Returning
    // true marks the error as handled → no process termination.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      report(error, stack, context: 'platform');
      return true;
    };

    // 3. Widget-build failures: swap the red screen for the branded fallback.
    ErrorWidget.builder = (FlutterErrorDetails details) => AppErrorFallback(
          error: details.exception,
        );
  }

  /// Records [error] without throwing. Safe from any context, including
  /// inside an `ErrorWidget.builder` or a `FlutterError.onError` callback.
  static void report(Object error, StackTrace? stackTrace, {String? context}) {
    AppLogger.error(
      'AppError',
      context == null || context.isEmpty ? 'unhandled error' : context,
      error,
      stackTrace,
    );
    lastError.value = error;
  }

  /// Runs [body] with the boundary applied: a thrown/rejected task is logged
  /// and yields `null` instead of propagating into a screen's build.
  static Future<T?> runGuarded<T>(
    String context,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } catch (error, stackTrace) {
      report(error, stackTrace, context: context);
      return null;
    }
  }

  /// Synchronous twin of [runGuarded] for store mutations.
  static T? runGuardedSync<T>(String context, T Function() body) {
    try {
      return body();
    } catch (error, stackTrace) {
      report(error, stackTrace, context: context);
      return null;
    }
  }

  /// Clears the failure flag (fallback "Retry" action / test setup).
  static void clear() => lastError.value = null;

  /// Test hook: clears the flag and restores the handlers captured on first
  /// install so one test can never leak the boundary into another.
  ///
  /// Restoring is explicit for all three hooks:
  ///  * `FlutterError.onError` — put back the test runner's reporter (only when
  ///    one was captured, so a `debugReset()` without `install()` stays a no-op
  ///    instead of clobbering the environment).
  ///  * `PlatformDispatcher.instance.onError` — put back the previous platform
  ///    handler (usually null).
  ///  * `ErrorWidget.builder` — put back the previous builder, or the framework
  ///    default when none was captured.
  @visibleForTesting
  static void debugReset() {
    _installed = false;
    lastError.value = null;

    final previousOnError = _previousOnError;
    if (previousOnError != null) {
      FlutterError.onError = previousOnError;
    }
    PlatformDispatcher.instance.onError = _previousPlatformOnError;
    ErrorWidget.builder = _previousErrorWidgetBuilder ??
        (FlutterErrorDetails details) => ErrorWidget(details.exception);

    _previousOnError = null;
    _previousPlatformOnError = null;
    _previousErrorWidgetBuilder = null;
  }
}