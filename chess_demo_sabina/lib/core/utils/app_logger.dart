import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Central logger for the Chess app.
///
/// Usage:
///   import 'package:chess_demo_sabina/core/utils/app_logger.dart';
///
///   AppLogger.d("Debug info");
///   AppLogger.i("FCM token registered");
///   AppLogger.w("No tokens found for user");
///   AppLogger.e("Critical failure", error: e);
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 1,        // Show 1 stack frame on errors
      errorMethodCount: 5,   // Show 5 frames on exceptions
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    // In release builds, only show warnings and above
    level: kReleaseMode ? Level.warning : Level.debug,
  );

  /// Verbose debug info — only visible in debug builds.
  static void d(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// General informational message.
  static void i(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Something unexpected but non-fatal.
  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// A failure that needs attention.
  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
