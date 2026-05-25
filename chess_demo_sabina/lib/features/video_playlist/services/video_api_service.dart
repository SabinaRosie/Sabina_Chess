import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/video_model.dart';

import '../../../core/utils/const.dart';

class VideoApiService {
  // Use your Django backend URL (from environment or constants)
  static final String baseUrl = '${AppConstants.baseUrl}/media';

  // Helper method to handle JSON responses
  static Future<dynamic> _handleResponse(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isNotEmpty) {
        return jsonDecode(response.body);
      }
      return null;
    } else {
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<VideoModel>> getVideos() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/videos/')).timeout(const Duration(seconds: 15));
      final data = await _handleResponse(response);
      
      if (data is List) {
        return data.map((json) => VideoModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("VideoApiService Error fetching videos: $e");
      return [];
    }
  }

  Future<VideoModel?> getVideoDetail(int videoId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/videos/$videoId/')).timeout(const Duration(seconds: 15));
      final data = await _handleResponse(response);
      
      if (data != null) {
        return VideoModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("VideoApiService Error fetching video detail: $e");
      return null;
    }
  }

  Future<List<VideoCommentModel>> getVideoComments(int videoId, {String? token}) async {
    try {
      final headers = <String, String>{};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/videos/$videoId/comments/'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      
      final data = await _handleResponse(response);
      
      if (data is List) {
        return data.map((json) => VideoCommentModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("VideoApiService Error fetching comments: $e");
      return [];
    }
  }

  Future<VideoCommentModel?> addComment(int videoId, String text, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/videos/$videoId/comments/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 15));
      
      final data = await _handleResponse(response);
      if (data != null) {
        return VideoCommentModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("VideoApiService Error adding comment: $e");
      return null;
    }
  }

  Future<VideoModel?> toggleReaction(int videoId, String reactionType, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/videos/$videoId/reaction/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reaction_type': reactionType}),
      ).timeout(const Duration(seconds: 15));
      
      final data = await _handleResponse(response);
      if (data != null && data['status'] == 'success') {
        return VideoModel.fromJson(data['video']);
      }
      return null;
    } catch (e) {
      debugPrint("VideoApiService Error toggling reaction: $e");
      return null;
    }
  }

  Future<void> updateVideoDuration(int videoId, int durationSeconds) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/videos/$videoId/update-duration/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'duration': durationSeconds}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint("VideoApiService Error updating duration: $e");
    }
  }
}
