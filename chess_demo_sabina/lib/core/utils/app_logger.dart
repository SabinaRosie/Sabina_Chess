import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Central logger for the Chess app.
///
/// Usage:
///   import 'package:chess_demo_sabina/core/utils/app_logger.dart';
///
///   AppLogger.d("Debug info");
///   AppLogger.i("FCM token registered");
///   AppLogger.w("No tokens found for user");
///   AppLogger.e("Critical failure", error: e, feature: "auth");
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

  /// A failure that needs attention. Supports feature categorization.
  static void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? feature,
    bool isFatal = false,
  }) {
    _logger.e(
      "[${feature ?? 'Global'}] $message",
      error: error,
      stackTrace: stackTrace,
    );

    // Save fatal errors and errors with features locally for backend sync
    _saveLogToLocalFile(
      level: isFatal ? 'FATAL' : 'ERROR',
      feature: feature,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static Future<File> get _logFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/offline_logs.json');
  }

  /// Retrieve all offline logs.
  static Future<List<Map<String, dynamic>>> getOfflineLogs() async {
    try {
      final file = await _logFile;
      if (!await file.exists()) return [];
      
      final content = await file.readAsString();
      if (content.isEmpty) return [];

      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint("Error reading offline logs: $e");
    }
    return [];
  }

  /// Clear the offline logs file.
  static Future<void> clearOfflineLogs() async {
    try {
      final file = await _logFile;
      if (await file.exists()) {
        await file.writeAsString(jsonEncode([]));
      }
    } catch (e) {
      debugPrint("Error clearing offline logs: $e");
    }
  }

  /// Saves the log locally as a JSON object
  static Future<void> _saveLogToLocalFile({
    required String level,
    required String? feature,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    try {
      final file = await _logFile;
      
      final newLog = {
        'level': level,
        'feature': feature,
        'message': '$message${error != null ? "\nError: $error" : ""}',
        'stack_trace': stackTrace?.toString(),
        'device_info': {
          'platform': defaultTargetPlatform.toString(),
          'isRelease': kReleaseMode,
        }
      };

      List<dynamic> existingLogs = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          try {
            existingLogs = jsonDecode(content);
          } catch (_) {
            existingLogs = [];
          }
        }
      }

      existingLogs.add(newLog);
      
      // Limit local buffer to prevent runaway disk usage (e.g. 200 items max)
      if (existingLogs.length > 200) {
        existingLogs.removeAt(0);
      }

      await file.writeAsString(jsonEncode(existingLogs));
    } catch (e) {
      debugPrint("Failed to write log to file: $e");
    }
  }
}

