import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/const.dart';

class ApiService {
  static Map<String, dynamic> _handleResponse(
    http.Response response,
    String defaultError,
  ) {
    try {
      final data = jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': data};
      } else {
        String errorMsg = defaultError;
        if (data is Map) {
          errorMsg = data['error'] ?? data['detail'] ?? defaultError;
        }
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      if (response.statusCode == 503 || response.statusCode == 502) {
        return {
          'success': false,
          'error': 'Server is waking up. Please wait a moment and try again.',
        };
      }
      return {'success': false, 'error': 'Unexpected response from server.'};
    }
  }

  static String _formatError(dynamic e) {
    String err = e.toString();
    if (err.contains('SocketException') ||
        err.contains('Connection timed out')) {
      return 'Connection timed out. The server might be waking up or your internet is unstable. Please try again.';
    }
    if (err.contains('ClientException')) {
      return 'Network error. Please check your connection.';
    }
    return err;
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/login');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Login failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> signup(
    String username,
    String email,
    String password,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/signup');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Signup failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final url = Uri.parse('${AppConstants.baseUrl}/forgot-password');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Request failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String email,
    String otp,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/verify-otp');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Verification failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
    String email,
    String newPassword,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/reset-password');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'new_password': newPassword}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Reset failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final url = Uri.parse('${AppConstants.baseUrl}/token/refresh');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refreshToken}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Token refresh failed');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> getProfile(String accessToken) async {
    final url = Uri.parse('${AppConstants.baseUrl}/profile');
    try {
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Failed to fetch profile');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> logout(
    String accessToken,
    String refreshToken,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/logout');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final token = await getValidToken();
    if (token == null) return {'success': false, 'error': 'No access token'};

    final url = Uri.parse('${AppConstants.baseUrl}/profile');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
      return _handleResponse(response, 'Failed to fetch profile');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> initiatePayment(
    num amount,
    String productId,
  ) async {
    final token = await getValidToken();
    if (token == null) return {'success': false, 'error': 'No access token'};

    final url = Uri.parse('${AppConstants.baseUrl}/payments/initiate');
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'amount': amount.toString(),
              'product_id': productId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, 'Failed to initiate payment');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> verifyPayment(String encodedData) async {
    final token = await getValidToken();
    if (token == null) return {'success': false, 'error': 'No access token'};

    final url = Uri.parse('${AppConstants.baseUrl}/payments/verify');
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': encodedData}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, 'Failed to verify payment');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> getUsers(String accessToken) async {
    final url = Uri.parse('${AppConstants.baseUrl}/users');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
      return _handleResponse(response, 'Failed to fetch users');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 🔹 Helper to get a valid access token, refreshing it if needed
  static Future<String?> getValidToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? accessToken = prefs.getString('accessToken');

    if (accessToken == null) return null;

    // Check if token is expired (JWT is base64 encoded JSON)
    try {
      final parts = accessToken.split('.');
      if (parts.length == 3) {
        final payload = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        final exp = payload['exp'] as int?;
        if (exp != null) {
          final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          // If expires in less than 30 seconds, refresh now
          if (expiryDate.isBefore(
            DateTime.now().add(const Duration(seconds: 30)),
          )) {
            return await forceRefreshToken();
          }
        }
      }
    } catch (e) {
      debugPrint('Token parse error: $e');
    }

    return accessToken;
  }

  /// 🔹 Force refresh the token and save it
  static Future<String?> forceRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refreshToken');
    if (refresh == null) return null;

    final result = await refreshToken(refresh);
    if (result['success']) {
      final newAccess = result['data']['access'];
      await prefs.setString('accessToken', newAccess);
      return newAccess;
    }
    return null;
  }

  // ── Game API Methods ──

  static Future<Map<String, dynamic>> getGameUsers(String accessToken) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/users');
    try {
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Failed to fetch game users');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> sendInvitation(
    String accessToken,
    int receiverId,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/invite');
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'receiver_id': receiverId}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Failed to send invitation');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> respondInvitation(
    String accessToken,
    dynamic invitationId,
    String status,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/respond');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'invitation_id': invitationId, 'status': status}),
      );
      return _handleResponse(response, 'Failed to respond to invitation');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> cancelInvitation(
    String accessToken,
    dynamic invitationId,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/cancel');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'invitation_id': invitationId}),
      );
      return _handleResponse(response, 'Failed to cancel invitation');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getPendingInvitations(
    String accessToken,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/invitations/pending');
    try {
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Failed to fetch pending invitations');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }

  static Future<Map<String, dynamic>> getSentInvitations(
    String accessToken,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/game/invitations/sent');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
      return _handleResponse(response, 'Failed to fetch sent invitations');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getInvitationStatus(
    String accessToken,
    dynamic invitationId,
  ) async {
    final url =
        Uri.parse('${AppConstants.baseUrl}/game/invitation/$invitationId/status');
    try {
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response, 'Failed to fetch invitation status');
    } catch (e) {
      return {'success': false, 'error': _formatError(e)};
    }
  }
}
