import 'package:flutter/foundation.dart';

/// Severity of a [LogRecord], from least to most severe.
enum LogLevel { debug, info, warning, error }

/// One immutable, structured log entry.
///
/// Records are kept in memory (bounded) so tests and the in-app diagnostics
/// view can assert on what actually happened, without a console.
@immutable
class LogRecord {
  const LogRecord({
    required this.level,
    required this.tag,
    required this.message,
    required this.at,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;

  /// Short subsystem label, e.g. `Proximity`, `OfflineQueue`, `AntiAbuse`.
  final String tag;
  final String message;
  final DateTime at;
  final Object? error;
  final StackTrace? stackTrace;

  /// Single-line rendering (the only shape ever printed).
  String get line {
    final detail = error == null ? '' : ' | $error';
    return '${level.name.toUpperCase()} $tag: $message$detail';
  }

  @override
  String toString() => line;
}

/// Optional external destination for log records.
///
/// Production target: a crash-reporting / analytics backend. The app NEVER
/// depends on a sink being installed — [AppLogger] works fully offline, and a
/// broken sink can never break a caller.
abstract class LogSink {
  /// Whether this build has a usable sink (credentials/backend wired).
  bool get isConfigured;

  /// Must never throw.
  Future<void> write(LogRecord record);
}

/// Centralized, dependency-free logger for stores and services.
///
/// WHY: the app is a mesh of process-wide static stores. Without one funnel,
/// failures disappear into `debugPrint` noise (or vanish entirely in release)
/// and every subsystem invents its own error handling. Everything logs through
/// here instead:
///  * [history] keeps the last [maxHistory] records in memory — usable by
///    tests and by a future in-app diagnostics screen;
///  * [sink] is the single seam for remote reporting;
///  * volume is controlled by [minLevel]; nothing is ever `print`ed.
///
/// Never throws: logging must not be able to fail a caller.
class AppLogger {
  AppLogger._();

  /// Hard cap on retained records (oldest dropped first).
  static const int maxHistory = 200;

  /// Most recent records, newest first. Bounded and observable.
  static final ValueNotifier<List<LogRecord>> history =
      ValueNotifier<List<LogRecord>>(<LogRecord>[]);

  /// Registered remote sink (production crash reporting). Null = local only.
  static LogSink? _sink;

  /// Lowest severity that is actually recorded.
  static LogLevel minLevel = LogLevel.debug;

  /// Test hook: silences the console mirror without affecting [history].
  @visibleForTesting
  static bool muteConsole = false;

  /// Production wiring point for the remote sink.
  static void setSink(LogSink sink) => _sink = sink;

  /// Test hook: installs (or clears, with `null`) the remote sink.
  @visibleForTesting
  static void debugSetSink(LogSink? sink) => _sink = sink;

  /// Records at [LogLevel.debug] (dev-only details).
  static void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  /// Records at [LogLevel.info] (normal lifecycle events).
  static void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  /// Records at [LogLevel.warning] (recovered / degraded behaviour).
  static void warn(String tag, String message, [Object? error]) =>
      _log(LogLevel.warning, tag, message, error);

  /// Records at [LogLevel.error] (a real failure the user may feel).
  static void error(String tag, String message,
          [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, tag, message, error, stackTrace);

  // ─── PII / SECRET REDACTION (audit remediation) ────────────────────────────

  /// E-mail addresses → `[email]` (identity, never needed in a log line).
  static final RegExp _emailPattern = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+');

  /// Long digit runs (phones, OTP codes) → `[phone]`. A run of ≥ 6 digits is
  /// never meaningful in a diagnostic message but frequently IS an OTP or a
  /// subscriber number. Small counts (timestamps, ids) are left untouched.
  static final RegExp _digitRunPattern = RegExp(r'\d{6,}');

  /// Bearer / API-key tokens → `[redacted]` (whole secret removed).
  static final RegExp _bearerPattern =
      RegExp(r'(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}');
  static final RegExp _secretKeyValuePattern = RegExp(
    r'(?i)((?:password|passwd|secret|api[_-]?key|token|anon[_-]?key)'
    r'["\']?\s*[:=]\s*["\']?)[^\s"\',;&]+',
  );

  /// Scrubs credentials and personal identifiers from [input] so no log
  /// destination (console mirror, in-memory history, remote sink) ever
  /// receives them. Idempotent and never throws.
  static String redact(String input) {
    var out = input;
    out = out.replaceAllMapped(
        _bearerPattern, (m) => '${m.group(1)}[redacted]');
    out = out.replaceAllMapped(_secretKeyValuePattern, (m) => '${m.group(1)}[redacted]');
    out = out.replaceAll(_emailPattern, '[email]');
    out = out.replaceAll(_digitRunPattern, '[phone]');
    return out;
  }

  /// Only the error records (assertions in tests / diagnostics filters).
  static List<LogRecord> get errors =>
      history.value.where((r) => r.level == LogLevel.error).toList();

  /// Drops every retained record (test isolation / diagnostics reset).
  static void clear() => history.value = <LogRecord>[];

  static void _log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLevel.index) return;

    // PII / SECRET REDACTION (audit remediation): every message and error is
    // scrubbed BEFORE it can reach the ring buffer, the debug console or a
    // remote sink. Logs must never become a side channel for credentials or
    // personal data (contract: "No implementation may persist or log
    // plaintext credentials").
    final record = LogRecord(
      level: level,
      tag: tag,
      message: redact(message),
      at: DateTime.now(),
      error: error == null ? null : redact(error.toString()),
      stackTrace: stackTrace,
    );

    // Bounded ring buffer: newest first, oldest evicted.
    final next = <LogRecord>[record, ...history.value];
    history.value =
        next.length > maxHistory ? next.sublist(0, maxHistory) : next;

    // Debug console mirror (never in release, never when muted by a test).
    if (kDebugMode && !muteConsole) {
      debugPrint('[${record.tag}] ${record.level.name.toUpperCase()}: '
          '${record.message}${record.error == null ? '' : ' | ${record.error}'}');
    }

    _forward(record);
  }

  /// Best-effort remote forwarding: a sink may never break a caller.
  static void _forward(LogRecord record) {
    final sink = _sink;
    if (sink == null || !sink.isConfigured) return;
    try {
      sink.write(record).then<void>((_) {}, onError: (Object _) {});
    } catch (_) {
      // Deliberately swallowed: logging is never allowed to fail.
    }
  }
}
