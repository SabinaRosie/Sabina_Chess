import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chess_demo_sabina/core/utils/const.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

class VoiceService {
  // Use Render base URL for AI Voice endpoints
  String get _baseUrl => AppConstants.baseUrl;

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    return {'Authorization': 'Bearer $token'};
  }

  /// Check if the user has a trained voice clone
  Future<Map<String, dynamic>> getVoiceStatus() async {
    try {
      final headers = await _headers();
      final response = await http.get(
        Uri.parse('$_baseUrl/media/voice/status/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('DEBUG: [VOICE] Error getting status: $e');
    }
    return {"is_trained": false};
  }

  /// Upload multiple voice samples to train the clone
  Future<bool> uploadVoiceSamples(List<String> filePaths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      final uri = Uri.parse('$_baseUrl/media/voice/upload/');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      for (var path in filePaths) {
        final file = await http.MultipartFile.fromPath(
          'samples',
          path,
          filename: basename(path),
        );
        request.files.add(file);
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      print('DEBUG: [VOICE] Upload Status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } on TimeoutException {
      print('DEBUG: [VOICE] Upload timed out');
      return false;
    } catch (e) {
      print('DEBUG: [VOICE] Error uploading samples: $e');
      return false;
    }
  }

  /// Send message to AI and receive text + audio reference
  Future<Map<String, dynamic>?> chatWithSelf(
    String message, {
    bool skipCache = false,
    List<Map<String, dynamic>>? conversationHistory,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final body = {
        "message": message,
        "skip_cache": skipCache,
      };
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        // Send only last 10 messages to keep payload small
        final recent = conversationHistory.length > 10
            ? conversationHistory.sublist(conversationHistory.length - 10)
            : conversationHistory;
        body["conversation_history"] = recent
            .map((m) => {"text": m["text"], "is_me": m["is_me"]})
            .toList();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/media/voice/chat_with_self/'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final body = jsonDecode(response.body);
        return {"error": body['error'] ?? "Server returned ${response.statusCode}"};
      }
    } catch (e) {
      print('DEBUG: [VOICE] Error in chat: $e');
    }
    return null;
  }

  /// Delete voice profile and all recorded samples
  Future<bool> deleteVoiceProfile() async {
    try {
      final headers = await _headers();
      final response = await http.delete(
        Uri.parse('$_baseUrl/media/voice/delete/'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('DEBUG: [VOICE] Error deleting profile: $e');
      return false;
    }
  }
}
