import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import 'package:intl/intl.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> otherUser;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

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
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _chatService.connectToChat(widget.conversationId);
    _chatService.messageStream.listen(_handleWsMessage);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getInt('userId') ?? 0;

    final result = await _chatService.getMessages(widget.conversationId);
    if (result['success']) {
      setState(() {
        _messages = result['data']['messages'];
        _hasMore = result['data']['has_more'];
      });
      _chatService.markAsSeen(widget.conversationId);
      _chatService.sendReadReceipt();
    }
  }

  void _handleWsMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    
    if (data['type'] == 'message') {
      setState(() {
        _messages.add(data['message']);
      });
      _scrollToBottom();
      _chatService.sendReadReceipt();
    } else if (data['type'] == 'typing') {
      if (data['user_id'] != _currentUserId) {
        setState(() => _isOtherUserTyping = data['is_typing']);
        
        // Auto-clear typing indicator after 3 seconds of no new typing events
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
            if (msg['sender_id'] == _currentUserId) {
              msg['status'] = 'seen';
            }
          }
        });
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (_hasMore && !_isLoadingMore) {
        _loadMoreMessages();
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty) return;
    
    setState(() => _isLoadingMore = true);
    final before = _messages.first['created_at'];
    final result = await _chatService.getMessages(widget.conversationId, before: before);
    
    if (result['success']) {
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
    
    _messageController.clear();
    _chatService.sendMessage(content);
    _chatService.sendTyping(false);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
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
                  if (_isOtherUserTyping)
                    const Text("typing...", style: TextStyle(color: AppColors.secondaryColor, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.secondaryColor),
            onPressed: () {
              // Implementation placeholder for calling integration
            },
          ),
        ],
      ),
      body: Container(
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
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(color: AppColors.secondaryColor),
                    ));
                  }
                  
                  // Messages are displayed in reverse order (newest at bottom)
                  final msg = _messages[_messages.length - 1 - index];
                  final bool isMe = msg['sender_id'] == _currentUserId;
                  return _buildMessageBubble(msg, isMe);
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(dynamic msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg['content'],
              style: TextStyle(color: isMe ? AppColors.backgroundColor : AppColors.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(DateTime.parse(msg['created_at']).toLocal()),
                  style: TextStyle(
                    color: (isMe ? AppColors.backgroundColor : AppColors.textSecondary).withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(msg['status']),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;
    switch (status) {
      case 'seen':
        icon = Icons.done_all;
        color = AppColors.backgroundColor;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = AppColors.backgroundColor.withOpacity(0.5);
        break;
      default:
        icon = Icons.done;
        color = AppColors.backgroundColor.withOpacity(0.5);
    }
    return Icon(icon, size: 14, color: color);
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) {
                    _chatService.sendTyping(val.isNotEmpty);
                  },
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
