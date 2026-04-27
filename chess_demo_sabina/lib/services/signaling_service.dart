import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/const.dart';
import 'api_service.dart';

/// REST + WebSocket-based signaling service for WebRTC call management.
class SignalingService {
  static WebSocketChannel? _channel;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await ApiService.getValidToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ""}',
    };
  }

  /// 🔹 WebSocket: Connect to signaling server
  static Future<Stream<dynamic>?> connectWebSocket(String roomId) async {
    try {
      final token = await ApiService.getValidToken();
      if (token == null) return null;

      // Convert https://... to wss://...
      final wsUrl = AppConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://')
          .replaceFirst('/api', '/ws/call/$roomId/');

      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      return _channel!.stream;
    } catch (e) {
      print('WebSocket Connection Error: $e');
      return null;
    }
  }

  /// 🔹 WebSocket: Send signal
  static void sendWsSignal(String type, Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': type,
        'data': data,
      }));
    }
  }

  /// 🔹 WebSocket: Close connection
  static void closeWebSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  /// Wrapper to handle automatic token refresh and retry
  static Future<Map<String, dynamic>> _request(
    Future<http.Response> Function(Map<String, String> headers) action,
  ) async {
    try {
      var headers = await _authHeaders();
      var response = await action(headers);

      // If 401, try to refresh token and retry once
      if (response.statusCode == 401) {
        final newToken = await ApiService.forceRefreshToken();
        if (newToken != null) {
          headers['Authorization'] = 'Bearer $newToken';
          response = await action(headers);
        }
      }

      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Create a new call room
  static Future<Map<String, dynamic>> createCall(
    String calleeUsername,
    String callType,
  ) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/call/create'),
      headers: headers,
      body: jsonEncode({
        'callee_username': calleeUsername,
        'call_type': callType,
      }),
    ));
  }

  /// Check for incoming calls (used for non-WS fallback or initial check)
  static Future<Map<String, dynamic>> checkIncoming() async {
    return _request((headers) => http.get(
      Uri.parse('${AppConstants.baseUrl}/call/check-incoming'),
      headers: headers,
    ));
  }

  /// Answer (accept/reject) an incoming call
  static Future<Map<String, dynamic>> answerCall(
    String roomId,
    String action,
  ) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/call/answer'),
      headers: headers,
      body: jsonEncode({'room_id': roomId, 'action': action}),
    ));
  }

  /// End a call
  static Future<Map<String, dynamic>> endCall(
    String roomId,
  ) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/call/end'),
      headers: headers,
      body: jsonEncode({'room_id': roomId}),
    ));
  }

  static Map<String, dynamic> _handle(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'error': data is Map
            ? (data['error'] ?? data['detail'] ?? 'Request failed (${response.statusCode})')
            : 'Request failed (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false, 
        'error': 'Server error: ${response.statusCode}'
      };
    }
  }
}
