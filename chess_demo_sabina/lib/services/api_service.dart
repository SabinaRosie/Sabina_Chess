import 'dart:convert';
import 'package:http/http.dart' as http;
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
        return {
          'success': false,
          'error': data is Map
              ? (data['error'] ?? data['detail'] ?? defaultError)
              : defaultError,
        };
      }
    } catch (e) {
      if (response.statusCode >= 500) {
        return {
          'success': false,
          'error': 'Server error (500). Please try again later.',
        };
      } else if (response.statusCode == 404) {
        return {'success': false, 'error': 'Endpoint not found (404).'};
      }
      return {'success': false, 'error': 'Unexpected response from server.'};
    }
  }

  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      return _handleResponse(response, 'Login failed');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> signup(
    String username,
    String email,
    String password,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/signup');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );
      return _handleResponse(response, 'Signup failed');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final url = Uri.parse('${AppConstants.baseUrl}/forgot-password');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      return _handleResponse(response, 'Request failed');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String email,
    String otp,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/verify-otp');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      return _handleResponse(response, 'Verification failed');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
    String email,
    String newPassword,
  ) async {
    final url = Uri.parse('${AppConstants.baseUrl}/reset-password');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'new_password': newPassword}),
      );
      return _handleResponse(response, 'Reset failed');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getProfile(String accessToken) async {
    final url = Uri.parse('${AppConstants.baseUrl}/profile');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
      return _handleResponse(response, 'Failed to fetch profile');
    } catch (e) {
      return {'success': false, 'error': e.toString()};
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
}
