import 'package:logger/logger.dart';

/// Thin wrapper around `package:logger` so call sites don't depend on
/// the third-party API directly, and so we can silence verbose logs
/// in release builds from one place.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 5,
      lineLength: 90,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: Level.debug,
  );

  static void debug(String message, [Object? data]) =>
      _logger.d(data != null ? '$message | $data' : message);

  static void info(String message, [Object? data]) =>
      _logger.i(data != null ? '$message | $data' : message);

  static void warning(String message, [Object? data]) =>
      _logger.w(data != null ? '$message | $data' : message);

  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}
