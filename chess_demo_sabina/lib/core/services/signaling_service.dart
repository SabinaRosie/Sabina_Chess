import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../utils/const.dart';
import './api_service.dart';

class SignalingService {
  // ── Static members for General Calling & Notifications ──
  static WebSocketChannel? _notificationChannel;
  static WebSocketChannel? _callChannel;

  // ── Static API Wrappers ──

  static Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    try {
      final data = jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': data['error'] ?? 'Request failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await ApiService.getValidToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ""}',
    };
  }

  static Future<void> registerFcmToken(String token) async {
    try {
      final headers = await _getHeaders();
      await http.post(
        Uri.parse('${AppConstants.baseUrl}/register-fcm-token'),
        headers: headers,
        body: jsonEncode({'token': token}),
      );
    } catch (e) {
      debugPrint("FCM Register Error: $e");
    }
  }

  static Future<Map<String, dynamic>> checkIncoming() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/check-incoming'),
        headers: headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> createCall(String calleeUsername, String callType) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/create'),
        headers: headers,
        body: jsonEncode({'callee_username': calleeUsername, 'call_type': callType}),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> answerCall(String roomId, String action) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/answer'),
        headers: headers,
        body: jsonEncode({'room_id': roomId, 'action': action}),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<Map<String, dynamic>>> getIceServers() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/turn-credentials'),
        headers: headers,
      ).timeout(const Duration(seconds: 5)); // 🔹 Fast timeout - fall back to hardcoded if server is slow
      final res = await _handleResponse(response);
      if (res['success']) {
        return List<Map<String, dynamic>>.from(res['data']['ice_servers']);
      }
    } catch (e) {
      debugPrint("ICE Servers Error (using fallback): $e");
    }
    // 🔹 Reliable fallback with TURN servers for cross-network calls
    return [
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:3478',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': [
          'turns:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:3478?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ];
  }

  // ── Static WebSocket Handlers ──

  static Future<Stream?> connectNotificationSocket() async {
    try {
      final token = await ApiService.getValidToken();
      if (token == null) return null;

      final url = Uri.parse('${AppConstants.webSocketUrl}/notifications/?token=$token');
      _notificationChannel = WebSocketChannel.connect(url);
      return _notificationChannel!.stream;
    } catch (e) {
      debugPrint("Notification WS Error: $e");
      return null;
    }
  }

  static void sendNotificationPing() {
    if (_notificationChannel != null) {
      _notificationChannel!.sink.add(jsonEncode({'type': 'ping'}));
    }
  }

  static Future<Stream?> connectWebSocket(String roomId) async {
    try {
      final token = await ApiService.getValidToken();
      if (token == null) return null;

      final url = Uri.parse('${AppConstants.webSocketUrl}/call/$roomId/?token=$token');
      _callChannel = WebSocketChannel.connect(url);
      return _callChannel!.stream;
    } catch (e) {
      debugPrint("Call WS Error: $e");
      return null;
    }
  }

  static void sendWsSignal(String type, Map<String, dynamic> data) {
    if (_callChannel != null) {
      _callChannel!.sink.add(jsonEncode({
        'type': type,
        'data': data,
      }));
    }
  }

  static void closeWebSocket() {
    _callChannel?.sink.close();
    _callChannel = null;
  }
}
