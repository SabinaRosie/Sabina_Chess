import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../services/signaling_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import 'package:intl/intl.dart';
import '../widgets/reaction_badge.dart';
import '../widgets/reaction_picker.dart';

class ChatPage extends StatefulWidget {
  final String? conversationId;
  final Map<String, dynamic> otherUser;

  const ChatPage({super.key, this.conversationId, required this.otherUser});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentUserId = 0;
  bool _isOtherUserTyping = false;
  bool _isConnected = false;
  bool _isHistoryLoading = true; // 🕒 New state for initial history load
  bool _isCallInitiating = false; // 🎥 New state for call loading
  Timer? _typingTimer;
  String? _currentConversationId;
  
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _currentConversationId = widget.conversationId;
    _isConnected = _chatService.isConnected;
    _init();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getInt('userId') ?? 0;
    
    _statusSubscription = _chatService.connectionStatusStream.listen((status) {
      if (mounted) setState(() => _isConnected = status);
    });

    if (_currentConversationId == null) {
      final otherUserId = widget.otherUser['id'];
      if (otherUserId == null) return;
      
      final startRes = await _chatService.startConversation(otherUserId);
      if (startRes['success']) {
        if (mounted) setState(() => _currentConversationId = startRes['data']['id']);
      }
    }

    setState(() => _isHistoryLoading = true);
    _loadHistory();
    _chatService.connectToChat(_currentConversationId!);
    _messageSubscription?.cancel();
    _messageSubscription = _chatService.messageStream.listen(_handleWsMessage);
  }

  Future<void> _loadHistory() async {
    if (_currentConversationId == null) {
      setState(() => _isHistoryLoading = false);
      return;
    }
    final result = await _chatService.getMessages(_currentConversationId!);
    if (mounted) {
      if (result['success']) {
        setState(() {
          _messages = result['data']['messages'];
          _hasMore = result['data']['has_more'];
          _isHistoryLoading = false;
        });
        _scrollToBottom(immediate: true);
        _chatService.markAsSeen(_currentConversationId!);
        _chatService.sendReadReceipt();
      } else {
        setState(() => _isHistoryLoading = false);
      }
    }
  }

  void _handleWsMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    if (data['type'] == 'message') {
      setState(() {
        _messages.removeWhere((m) => m['is_optimistic'] == true && m['content'] == data['message']['content']);
        bool alreadyExists = _messages.any((m) => m['id'] == data['message']['id']);
        if (!alreadyExists) _messages.add(data['message']);
      });
      _scrollToBottom();
      _chatService.sendReadReceipt();
    } else if (data['type'] == 'typing') {
      if (data['user_id'] != _currentUserId) {
        setState(() => _isOtherUserTyping = data['is_typing']);
        _typingTimer?.cancel();
        if (data['is_typing']) {
          _typingTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isOtherUserTyping = false);
          });
        }
      }
    } else if (data['type'] == 'seen') {
      if (data['user_id'] != _currentUserId) {
        setState(() {
          for (var msg in _messages) {
            if (msg['sender_id'] == _currentUserId) msg['status'] = 'seen';
          }
        });
      }
    } else if (data['type'] == 'reaction_updated') {
      final updatedData = data['data'];
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == updatedData['messageId']);
        if (index != -1) {
          _messages[index]['reactions'] = updatedData['reactions'];
        }
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (_hasMore && !_isLoadingMore && _currentConversationId != null) _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    setState(() => _isLoadingMore = true);
    final before = _messages.first['created_at'];
    final result = await _chatService.getMessages(_currentConversationId!, before: before);
    if (result['success'] && mounted) {
      setState(() {
        _messages.insertAll(0, result['data']['messages']);
        _hasMore = result['data']['has_more'];
        _isLoadingMore = false;
      });
    }
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    
    final optimisticMsg = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': _currentUserId,
      'content': content,
      'message_type': 'text',
      'status': 'sending',
      'created_at': DateTime.now().toIso8601String(),
      'is_optimistic': true,
    };

    setState(() => _messages.add(optimisticMsg));
    _scrollToBottom();
    _messageController.clear();
    _chatService.sendMessage(content);
    _chatService.sendTyping(false);
  }

  Future<void> _initiateCall(String callType) async {
    setState(() => _isCallInitiating = true); // Start blur
    
    final username = widget.otherUser['username'];
    final result = await SignalingService.createCall(username, callType);
    
    if (!mounted) return;
    
    if (result['success']) {
      final data = result['data'];
      await RouteGenerator.navigateToPage(context, Routes.callRoute, arguments: {
        'roomId': data['room_id'],
        'remoteUsername': username,
        'callType': callType,
        'isCaller': true,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Call failed: ${result['error']}"))
      );
    }
    
    if (mounted) setState(() => _isCallInitiating = false); // End blur
  }

  void _scrollToBottom({bool immediate = false}) {
    Future.delayed(Duration(milliseconds: immediate ? 0 : 100), () {
      if (_scrollController.hasClients) {
        if (immediate) _scrollController.jumpTo(0);
        else _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showReactionPicker(BuildContext context, dynamic msg, Offset position) {
    final overlay = Overlay.of(context);
    OverlayEntry? entry;

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => entry?.remove(),
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            left: position.dx.clamp(20.0, MediaQuery.of(context).size.width - 250.0),
            top: position.dy - 70,
            child: Material(
              color: Colors.transparent,
              child: ReactionPicker(
                onEmojiSelected: (emoji) {
                  _toggleReaction(msg['id'], emoji);
                  entry?.remove();
                },
                onMorePressed: () {
                  // TODO: Implement full emoji picker
                  entry?.remove();
                },
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  Future<void> _toggleReaction(int messageId, String emoji) async {
    // Find the message
    final msgIndex = _messages.indexWhere((m) => m['id'] == messageId);
    if (msgIndex == -1) return;

    final msg = _messages[msgIndex];
    final reactions = List<dynamic>.from(msg['reactions'] ?? []);
    
    // Check if user already reacted with this emoji
    final emojiIndex = reactions.indexWhere((r) => r['emoji'] == emoji);
    bool isRemoving = false;
    
    if (emojiIndex != -1) {
      final userIds = List<dynamic>.from(reactions[emojiIndex]['userIds']);
      if (userIds.contains(_currentUserId)) {
        isRemoving = true;
      }
    }

    // Optimistic Update
    setState(() {
      if (isRemoving) {
        final userIds = List<dynamic>.from(reactions[emojiIndex]['userIds']);
        userIds.remove(_currentUserId);
        if (userIds.isEmpty) {
          reactions.removeAt(emojiIndex);
        } else {
          reactions[emojiIndex]['userIds'] = userIds;
          reactions[emojiIndex]['count'] = userIds.length;
        }
      } else {
        if (emojiIndex != -1) {
          final userIds = List<dynamic>.from(reactions[emojiIndex]['userIds']);
          userIds.add(_currentUserId);
          reactions[emojiIndex]['userIds'] = userIds;
          reactions[emojiIndex]['count'] = userIds.length;
        } else {
          reactions.add({
            'emoji': emoji,
            'count': 1,
            'userIds': [_currentUserId],
          });
        }
      }
      _messages[msgIndex]['reactions'] = reactions;
    });

    // API Call
    final result = isRemoving 
        ? await _chatService.removeReaction(messageId, emoji)
        : await _chatService.addReaction(messageId, emoji);

    if (!result['success']) {
      // Revert optimistic update if failed
      _loadHistory(); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update reaction: ${result['error']}"))
      );
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _messageSubscription?.cancel();
    _chatService.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Colors.white10, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.secondaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.secondaryColor.withOpacity(0.2),
              radius: 18,
              child: Text(
                widget.otherUser['username'][0].toUpperCase(),
                style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherUser['username'], style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                  Text(
                    _isOtherUserTyping ? "typing..." : (_isConnected ? "online" : "connecting..."),
                    style: TextStyle(
                      color: _isOtherUserTyping || _isConnected ? AppColors.secondaryColor : Colors.white54,
                      fontSize: 11
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call, color: AppColors.secondaryColor), onPressed: () => _initiateCall('audio')),
          IconButton(icon: const Icon(Icons.videocam, color: AppColors.secondaryColor), onPressed: () => _initiateCall('video')),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: AppColors.woodGradient,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: _isHistoryLoading 
                    ? const Center(child: CircularProgressIndicator(color: AppColors.secondaryColor))
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: AppColors.secondaryColor)));
                          final msg = _messages[_messages.length - 1 - index];
                          final bool isMe = msg['sender_id'].toString() == _currentUserId.toString();
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
                ),
                _buildInputArea(),
              ],
            ),
          ),
          // 🎥 Premium Call Loading Overlay
          if (_isCallInitiating)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.secondaryColor, strokeWidth: 3),
                        const SizedBox(height: 24),
                        Text(
                          "Connecting Call...",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic msg, bool isMe) {
    final reactions = msg['reactions'] as List<dynamic>? ?? [];
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPressStart: (details) => _showReactionPicker(context, msg, details.globalPosition),
            onDoubleTapDown: (details) => _showReactionPicker(context, msg, details.globalPosition),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isMe ? AppColors.secondaryColor.withOpacity(0.9) : AppColors.surfaceColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 20),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(msg['content'], style: TextStyle(color: isMe ? AppColors.backgroundColor : AppColors.textPrimary, fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(DateTime.parse(msg['created_at']).toLocal()),
                        style: TextStyle(color: (isMe ? AppColors.backgroundColor : AppColors.textSecondary).withOpacity(0.7), fontSize: 10),
                      ),
                      if (isMe) ...[const SizedBox(width: 4), _buildStatusIcon(msg['status'])],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: isMe ? 0 : 12, right: isMe ? 12 : 0, bottom: 8),
              child: Wrap(
                children: reactions.map((r) {
                  final bool hasReacted = (r['userIds'] as List<dynamic>).contains(_currentUserId);
                  return ReactionBadge(
                    emoji: r['emoji'],
                    count: r['count'],
                    isMe: hasReacted,
                    onTap: () => _toggleReaction(msg['id'], r['emoji']),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;
    switch (status) {
      case 'seen': icon = Icons.done_all; color = AppColors.backgroundColor; break;
      case 'delivered': icon = Icons.done_all; color = AppColors.backgroundColor.withOpacity(0.5); break;
      case 'sending': icon = Icons.access_time; color = AppColors.backgroundColor.withOpacity(0.5); break;
      default: icon = Icons.done; color = AppColors.backgroundColor.withOpacity(0.5);
    }
    return Icon(icon, size: 14, color: color);
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceColor, border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(25)),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => _chatService.sendTyping(val.isNotEmpty),
                  decoration: const InputDecoration(
                    hintText: "Type a message...",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: AppColors.secondaryColor, shape: BoxShape.circle),
                child: const Icon(Icons.send, color: AppColors.backgroundColor, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
