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

  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  String? _activeConversationId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  final List<Map<String, dynamic>> _messageQueue = [];

  bool get isConnected => _isConnected;

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

  Future<int> getTotalUnreadCount() async {
    final result = await listConversations();
    if (result['success']) {
      final List conversations = result['data'];
      int total = 0;
      for (var conv in conversations) {
        total += (conv['unread_count'] as int? ?? 0);
      }
      return total;
    }
    return 0;
  }

  Future<Map<String, dynamic>> markAsSeen(String conversationId) async {
    return _request((headers) => http.post(
      Uri.parse('${AppConstants.baseUrl}/chat/seen/$conversationId'),
      headers: headers,
    ));
  }

  // --- WebSocket Methods ---

  Future<void> connectToChat(String conversationId) async {
    if (_activeConversationId == conversationId && _chatChannel != null && _isConnected) return;
    
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

      print("Connecting to Chat WS: $wsUrl");

      _chatChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _wsSubscription = _chatChannel!.stream.listen(
        (data) {
          if (!_isConnected) _setConnected(true);
          _reconnectAttempts = 0;
          final decoded = jsonDecode(data);
          _messageController.add(decoded);
        },
        onDone: () {
          _setConnected(false);
          _handleReconnect();
        },
        onError: (e) {
          _setConnected(false);
          _handleReconnect();
        },
      );
      
      // Send ping immediately
      _chatChannel!.sink.add(jsonEncode({'type': 'ping'}));
      
      // Fallback: Assume connected after 500ms if no error
      Timer(const Duration(milliseconds: 500), () {
        if (_chatChannel != null && !_isConnected) {
          _setConnected(true);
        }
      });
      
    } catch (e) {
      _setConnected(false);
      _handleReconnect();
    }
  }

  void _setConnected(bool status) {
    _isConnected = status;
    _connectionStatusController.add(status);
    if (status) {
      _flushQueue();
    }
  }

  void _handleReconnect() {
    if (_activeConversationId == null) return;
    
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    
    int delay = (_reconnectAttempts * 2).clamp(2, 20);
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _establishConnection();
    });
  }

  Future<void> sendMessage(String content, {String type = 'text'}) async {
    final msg = {
      'type': 'message',
      'content': content,
      'message_type': type,
    };

    if (!_isConnected || _chatChannel == null) {
      _messageQueue.add(msg);
      await _establishConnection();
      // Wait a bit for connection to stabilize
      int retry = 0;
      while (!_isConnected && retry < 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        retry++;
      }
    } else {
      _chatChannel!.sink.add(jsonEncode(msg));
    }
  }

  void _flushQueue() {
    if (!_isConnected || _chatChannel == null) return;
    while (_messageQueue.isNotEmpty) {
      final msg = _messageQueue.removeAt(0);
      _chatChannel!.sink.add(jsonEncode(msg));
    }
  }

  void sendTyping(bool isTyping) {
    if (_isConnected && _chatChannel != null) {
      _chatChannel!.sink.add(jsonEncode({
        'type': 'typing',
        'is_typing': isTyping,
      }));
    }
  }

  void sendReadReceipt() {
    if (_isConnected && _chatChannel != null) {
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
    _setConnected(false);
    _messageQueue.clear();
  }

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
