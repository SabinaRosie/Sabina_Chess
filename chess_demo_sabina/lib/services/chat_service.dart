import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/const.dart';
import 'api_service.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  WebSocketChannel? _chatChannel;
  StreamSubscription? _wsSubscription;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  String? _activeConversationId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // --- API Methods ---

  Future<Map<String, dynamic>> listConversations() async {
    return _request((headers) => http.get(
      Uri.parse('${AppConstants.baseUrl}/chat/conversations'),
      headers: headers,
    ));
  }

  Future<Map<String, dynamic>> getMessages(String conversationId, {String? before}) async {
    String url = '${AppConstants.baseUrl}/chat/messages/$conversationId?limit=20';
    if (before != null) url += '&before=$before';
    
    return _request((headers) => http.get(
      Uri.parse(url),
      headers: headers,
    ));
  }

  Future<Map<String, dynamic>> startConversation(int userId) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/chat/start'),
      headers: headers,
      body: jsonEncode({'user_id': userId}),
    ));
  }

  Future<Map<String, dynamic>> markAsSeen(String conversationId) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/chat/seen/$conversationId'),
      headers: headers,
    ));
  }

  // --- WebSocket Methods ---

  Future<void> connectToChat(String conversationId) async {
    if (_activeConversationId == conversationId && _chatChannel != null) return;
    
    _activeConversationId = conversationId;
    _reconnectAttempts = 0;
    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (_activeConversationId == null) return;
    
    try {
      _wsSubscription?.cancel();
      _chatChannel?.sink.close();
      
      final token = await ApiService.getValidToken();
      if (token == null) return;

      final wsUrl = AppConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://')
          .replaceFirst('/api', '/ws/chat/$_activeConversationId/');

      _chatChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _wsSubscription = _chatChannel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          final decoded = jsonDecode(data);
          _messageController.add(decoded);
        },
        onDone: () => _handleReconnect(),
        onError: (e) => _handleReconnect(),
      );
    } catch (e) {
      _handleReconnect();
    }
  }

  void _handleReconnect() {
    if (_activeConversationId == null) return;
    
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    
    // Exponential backoff: 2s, 4s, 8s... up to 30s
    int delay = (_reconnectAttempts * 2).clamp(2, 30);
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _establishConnection();
    });
  }

  void sendMessage(String content, {String type = 'text'}) {
    if (_chatChannel != null) {
      _chatChannel!.sink.add(jsonEncode({
        'type': 'message',
        'content': content,
        'message_type': type,
      }));
    }
  }

  void sendTyping(bool isTyping) {
    if (_chatChannel != null) {
      _chatChannel!.sink.add(jsonEncode({
        'type': 'typing',
        'is_typing': isTyping,
      }));
    }
  }

  void sendReadReceipt() {
    if (_chatChannel != null) {
      _chatChannel!.sink.add(jsonEncode({
        'type': 'read',
      }));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _chatChannel?.sink.close();
    _chatChannel = null;
    _activeConversationId = null;
  }

  // --- Helpers ---

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function(Map<String, String> headers) action,
  ) async {
    try {
      final token = await ApiService.getValidToken();
      var headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${token ?? ""}',
      };
      
      var response = await action(headers);
      if (response.statusCode == 401) {
        final newToken = await ApiService.forceRefreshToken();
        if (newToken != null) {
          headers['Authorization'] = 'Bearer $newToken';
          response = await action(headers);
        }
      }

      final data = jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': data};
      }
      return {
        'success': false, 
        'error': data is Map ? (data['error'] ?? data['detail'] ?? 'Request failed') : 'Request failed'
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
