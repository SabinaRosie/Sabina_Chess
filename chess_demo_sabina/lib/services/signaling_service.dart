import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/const.dart';
import 'api_service.dart';

class SignalingService {
  static WebSocketChannel? _channel;
  static WebSocketChannel? _notificationChannel;
  static StreamController<dynamic>? _controller;
  static StreamController<dynamic>? _notificationController;
  static StreamSubscription? _subscription;
  static StreamSubscription? _notificationSubscription;

  // --- API Methods ---

  static Future<Map<String, dynamic>> createCall(String calleeUsername, String callType) async {
    try {
      final token = await ApiService.getValidToken();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'callee_username': calleeUsername,
          'call_type': callType,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      }
      return {'success': false, 'error': data['error']};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> answerCall(String roomId, String action) async {
    try {
      final token = await ApiService.getValidToken();
      await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/answer'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'room_id': roomId,
          'action': action,
        }),
      );
    } catch (e) {
      debugPrint("Error answering call: $e");
    }
  }

  static Future<void> endCall(String roomId) async {
    try {
      final token = await ApiService.getValidToken();
      await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/end'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'room_id': roomId}),
      );
    } catch (e) {
      debugPrint("Error ending call API: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> getIceServers() async {
    try {
      final token = await ApiService.getValidToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/turn-credentials'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> servers = data['ice_servers'];
        return servers.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error fetching ICE servers: $e");
    }
    // Fallback to robust STUN servers if TURN fails
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
    ];
  }

  static Future<bool> registerFcmToken(String token, {String? deviceId}) async {
    try {
      final authToken = await ApiService.getValidToken();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/register-fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'token': token,
          'device_id': deviceId,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Error registering FCM token: $e");
      return false;
    }
  }

  // --- WebSocket Methods ---

  static Future<Stream<dynamic>?> connectWebSocket(String roomId) async {
    try {
      await closeWebSocket();

      final token = await ApiService.getValidToken();
      final wsUrl = AppConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://')
          .replaceFirst('/api', '/ws/call/$roomId/');

      debugPrint("Connecting to Call WebSocket: $wsUrl");

      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _controller = StreamController<dynamic>.broadcast();
      _subscription = _channel!.stream.listen(
        (data) => _controller?.add(data),
        onDone: () => closeWebSocket(),
        onError: (e) => closeWebSocket(),
      );

      return _controller!.stream;
    } catch (e) {
      debugPrint("WS Connection Error: $e");
      return null;
    }
  }

  static void sendNotificationPing() {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'type': 'ping_notification'}));
    }
  }

  static Future<Map<String, dynamic>> checkIncoming() async {
    try {
      final token = await ApiService.getValidToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/check-incoming'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
    } catch (e) {
      debugPrint("Check Incoming Error: $e");
    }
    return {'success': false};
  }

  static void sendWsSignal(String type, Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': type,
        'data': data,
      }));
    }
  }

  static Future<Stream<dynamic>?> connectNotificationSocket() async {
    try {
      final token = await ApiService.getValidToken();
      final wsUrl = AppConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://')
          .replaceFirst('/api', '/ws/notifications/');

      debugPrint("Connecting to Notification WebSocket: $wsUrl");

      _notificationChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _notificationController = StreamController<dynamic>.broadcast();
      _notificationSubscription = _notificationChannel!.stream.listen(
        (data) => _notificationController?.add(data),
        onDone: () => _notificationChannel = null,
        onError: (e) => _notificationChannel = null,
      );

      return _notificationController!.stream;
    } catch (e) {
      debugPrint("Notification WS Error: $e");
      return null;
    }
  }

  static Future<void> closeWebSocket() async {
    await _subscription?.cancel();
    await _controller?.close();
    await _channel?.sink.close();
    await _notificationSubscription?.cancel();
    await _notificationController?.close();
    await _notificationChannel?.sink.close();
    _subscription = null;
    _controller = null;
    _channel = null;
    _notificationSubscription = null;
    _notificationController = null;
    _notificationChannel = null;
  }
}
