import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/const.dart';

/// REST-based signaling service for WebRTC call management.
/// Uses HTTP polling to exchange SDP offers/answers and ICE candidates
/// through the Django backend.
class SignalingService {
  static Map<String, String> _authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Create a new call room
  static Future<Map<String, dynamic>> createCall(
    String token,
    String calleeUsername,
    String callType,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/create'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'callee_username': calleeUsername,
          'call_type': callType,
        }),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check for incoming calls
  static Future<Map<String, dynamic>> checkIncoming(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/check-incoming'),
        headers: _authHeaders(token),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Answer (accept/reject) an incoming call
  static Future<Map<String, dynamic>> answerCall(
    String token,
    String roomId,
    String action,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/answer'),
        headers: _authHeaders(token),
        body: jsonEncode({'room_id': roomId, 'action': action}),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send an SDP offer/answer or ICE candidate
  static Future<Map<String, dynamic>> sendSignal(
    String token,
    String roomId,
    String signalType,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/signal'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'room_id': roomId,
          'signal_type': signalType,
          'data': data,
        }),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get pending signals for a room
  static Future<Map<String, dynamic>> getSignals(
    String token,
    String roomId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/call/signals?room_id=$roomId'),
        headers: _authHeaders(token),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// End a call
  static Future<Map<String, dynamic>> endCall(
    String token,
    String roomId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/call/end'),
        headers: _authHeaders(token),
        body: jsonEncode({'room_id': roomId}),
      );
      return _handle(response);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
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
            ? (data['error'] ?? data['detail'] ?? 'Request failed')
            : 'Request failed',
      };
    } catch (e) {
      return {'success': false, 'error': 'Unexpected response from server.'};
    }
  }
}
