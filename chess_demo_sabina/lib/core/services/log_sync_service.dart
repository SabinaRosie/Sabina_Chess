import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/const.dart';
import '../utils/app_logger.dart';
import 'api_service.dart';

/// Service responsible for syncing cached offline/feature crash logs to the Django server.
class LogSyncService {
  LogSyncService._();

  static bool _isSyncing = false;

  /// Syncs cached client logs to the backend.
  static Future<void> syncLogs() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final logs = await AppLogger.getOfflineLogs();
      if (logs.isEmpty) {
        _isSyncing = false;
        return;
      }

      final url = Uri.parse('${AppConstants.baseUrl}/logs/submit');
      final headers = {
        'Content-Type': 'application/json',
      };

      // Try to attach authorization token if user is logged in
      final token = await ApiService.getValidToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(logs),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        debugPrint('[LOG_SYNC] Successfully uploaded ${logs.length} client logs.');
        await AppLogger.clearOfflineLogs();
      } else {
        debugPrint('[LOG_SYNC] Failed to upload logs. Status code: ${response.statusCode}');
      }
    } catch (e) {
      // Print to debug console instead of AppLogger.e to avoid potential infinite loops
      debugPrint('[LOG_SYNC] Error during log sync: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
