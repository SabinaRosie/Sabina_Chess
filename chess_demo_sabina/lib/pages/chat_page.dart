import 'dart:async';
import 'dart:ui';
import 'dart:convert';
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
import 'package:flutter/services.dart';

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
  final Map<int, String> _userNames = {}; // Cache for user names
  bool _isHistorySyncing = false; // For showing a blurred indicator during server sync
  dynamic _replyingToMessage; // Message being replied to

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
    await _loadFromCache(); // Load instantly from cache
    _loadHistory(); // Then sync with server
    _chatService.connectToChat(_currentConversationId!);
    _messageSubscription?.cancel();
    _messageSubscription = _chatService.messageStream.listen(_handleWsMessage);

    // Cache names for reaction details
    _userNames[_currentUserId] = "You";
    final otherId = int.tryParse(widget.otherUser['id'].toString());
    if (otherId != null) {
      _userNames[otherId] = widget.otherUser['username'];
    }
  }

  Future<void> _loadFromCache() async {
    if (_currentConversationId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('chat_cache_$_currentConversationId');
    if (cached != null) {
      setState(() {
        _messages = jsonDecode(cached);
        _isHistoryLoading = false;
      });
    }
  }

  Future<void> _saveToCache() async {
    if (_currentConversationId == null || _messages.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    // Save only latest 30 messages
    final toCache = _messages.length > 30 ? _messages.sublist(_messages.length - 30) : _messages;
    await prefs.setString('chat_cache_$_currentConversationId', jsonEncode(toCache));
  }

  Future<void> _loadHistory() async {
    if (_currentConversationId == null) {
      setState(() => _isHistoryLoading = false);
      return;
    }
    
    // If we already have messages from cache, show a syncing indicator instead of a full blank loader
    if (_messages.isNotEmpty) {
      setState(() => _isHistorySyncing = true);
    }

    final result = await _chatService.getMessages(_currentConversationId!);
    if (mounted) {
      if (result['success']) {
        setState(() {
          _messages = result['data']['messages'];
          _hasMore = result['data']['has_more'];
          _isHistoryLoading = false;
          _isHistorySyncing = false;
        });
        _saveToCache();
        _scrollToBottom(immediate: true);
        _chatService.markAsSeen(_currentConversationId!);
        _chatService.sendReadReceipt();
      } else {
        setState(() {
          _isHistoryLoading = false;
          _isHistorySyncing = false;
        });
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
    } else if (data['type'] == 'message_deleted') {
      final messageId = data['data']['messageId'];
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == messageId);
        if (index != -1) {
          _messages[index]['is_deleted'] = true;
          _messages[index]['content'] = "This message was deleted";
        }
      });
      _saveToCache();
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
      'replied_to': _replyingToMessage != null ? {
        'id': _replyingToMessage['id'],
        'content': _replyingToMessage['content'],
        'sender_id': _replyingToMessage['sender_id'],
      } : null,
    };

    final repliedToId = _replyingToMessage?['id'];
    setState(() {
      _messages.add(optimisticMsg);
      _replyingToMessage = null;
    });
    _scrollToBottom();
    _messageController.clear();
    _chatService.sendMessage(content, repliedToId: repliedToId);
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Calculate if it should be above or below
    final isTopHalf = position.dy < screenHeight / 2;
    final topPos = isTopHalf ? position.dy + 20 : position.dy - 80;
    
    OverlayEntry? entry;

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => entry?.remove(),
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            left: (position.dx - 125).clamp(16.0, screenWidth - 266.0), // Center picker on tap but stay in bounds
            top: topPos,
            child: Material(
              color: Colors.transparent,
              child: ReactionPicker(
                onEmojiSelected: (emoji) {
                  _toggleReaction(msg['id'], emoji);
                  entry?.remove();
                },
                onMorePressed: () {
                  entry?.remove();
                },
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
    
    // Also show long press menu (Action Sheet)
    _showLongPressMenu(msg);
  }

  void _showLongPressMenu(dynamic msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            _buildMenuOption(Icons.reply, "Reply", () {
              Navigator.pop(context);
              setState(() => _replyingToMessage = msg);
            }),
            _buildMenuOption(Icons.copy, "Copy Text", () {
              Clipboard.setData(ClipboardData(text: msg['content']));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard")));
            }),
            _buildMenuOption(Icons.forward, "Forward", () {
              Navigator.pop(context);
              _showForwardList(msg);
            }),
            _buildMenuOption(Icons.delete, "Delete", () {
              Navigator.pop(context);
              _showDeleteConfirmation(msg);
            }, isDestructive: true),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(dynamic msg) {
    bool isOwner = msg['sender_id'].toString() == _currentUserId.toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        title: Text(isOwner ? "Delete for everyone?" : "Delete message?", style: const TextStyle(color: Colors.white)),
        content: Text(
          isOwner 
            ? "Are you sure you want to delete this message? This will remove it for both users."
            : "You can only delete your own messages for everyone. Do you want to remove this message for yourself?",
          style: const TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await _chatService.deleteMessage(msg['id']);
              if (res['success']) {
                setState(() {
                  final index = _messages.indexWhere((m) => m['id'] == msg['id']);
                  if (index != -1) {
                    _messages[index]['is_deleted'] = true;
                    _messages[index]['content'] = "This message was deleted";
                  }
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete failed: ${res['error']}")));
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showForwardList(dynamic msg) {
    // Show a dialog with users list to forward
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Forward Message", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _chatService.listConversations(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.secondaryColor));
                  final conversations = snapshot.data!['data'] as List;
                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      final otherUser = conv['other_user'];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.secondaryColor.withOpacity(0.2),
                          child: Text(otherUser['username'][0].toUpperCase(), style: const TextStyle(color: AppColors.secondaryColor)),
                        ),
                        title: Text(otherUser['username'], style: const TextStyle(color: Colors.white)),
                        onTap: () async {
                          Navigator.pop(context);
                          final res = await _chatService.forwardMessage(msg['id'], conv['id']);
                          if (res['success']) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Forwarded to ${otherUser['username']}"),
                                backgroundColor: AppColors.secondaryColor,
                              )
                            );
                            // If we are currently in that conversation, the message will appear via WS
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Forward failed: ${res['error']}"))
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : AppColors.secondaryColor),
      title: Text(title, style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white)),
      onTap: onTap,
    );
  }

  void _showReactionDetails(dynamic msg) {
    final List<dynamic> reactions = msg['reactions'] ?? [];
    if (reactions.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: DefaultTabController(
          length: reactions.length + 1,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 20),
                    child: Text("Reactions", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              TabBar(
                isScrollable: true,
                indicatorColor: AppColors.secondaryColor,
                labelColor: AppColors.secondaryColor,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  const Tab(text: "ALL"),
                  ...reactions.map((r) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r['emoji']),
                        const SizedBox(width: 4),
                        Text(r['count'].toString()),
                      ],
                    ),
                  )),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // ALL tab
                    _buildReactorList(msg, null),
                    // Per-emoji tabs
                    ...reactions.map((r) => _buildReactorList(msg, r['emoji'])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactorList(dynamic msg, String? filterEmoji) {
    final List<dynamic> allReactions = msg['reactions'] ?? [];
    List<Map<String, dynamic>> reactors = [];

    for (var r in allReactions) {
      if (filterEmoji == null || r['emoji'] == filterEmoji) {
        for (var userId in r['userIds']) {
          reactors.add({
            'id': userId,
            'name': _userNames[userId] ?? "User $userId",
            'emoji': r['emoji'],
          });
        }
      }
    }

    return ListView.builder(
      itemCount: reactors.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final reactor = reactors[index];
        final bool isMe = reactor['id'] == _currentUserId;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.secondaryColor.withOpacity(0.2),
            child: Text(reactor['name'][0].toUpperCase(), style: const TextStyle(color: AppColors.secondaryColor)),
          ),
          title: Text(reactor['name'], style: const TextStyle(color: Colors.white)),
          subtitle: isMe ? const Text("Tap to remove", style: TextStyle(color: Colors.white38, fontSize: 12)) : null,
          trailing: Text(reactor['emoji'], style: const TextStyle(fontSize: 20)),
          onTap: isMe ? () {
            Navigator.pop(context);
            _toggleReaction(msg['id'], reactor['emoji']);
          } : null,
        );
      },
    );
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
                    ? _buildSkeletonLoader()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: AppColors.secondaryColor)));
                          final msg = _messages[_messages.length - 1 - index];
                          final senderId = msg['sender_id'];
                          // Logic: It's me if the sender ID matches my ID, 
                          // OR if the sender ID is NOT the other user's ID.
                          final bool isOther = senderId.toString() == widget.otherUser['id'].toString();
                          final bool isMe = !isOther;
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
                ),
                _buildInputArea(),
              ],
            ),
          ),
          // 🎥 Premium Call/Sync Loading Overlay
          if (_isCallInitiating || _isHistoryLoading || _isHistorySyncing)
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
                        if (_isCallInitiating) ...[
                          const SizedBox(height: 24),
                          Text(
                            "Connecting Call...",
                            style: TextStyle(
                              color: Colors.white, 
                              fontSize: 18, 
                              fontWeight: FontWeight.bold, 
                              shadows: [Shadow(color: Colors.black, blurRadius: 10)]
                            ),
                          ),
                        ],
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
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPressStart: msg['is_deleted'] == true ? null : (details) => _showReactionPicker(context, msg, details.globalPosition),
                onDoubleTapDown: msg['is_deleted'] == true ? null : (details) => _showReactionPicker(context, msg, details.globalPosition),
                onTap: msg['is_deleted'] == true ? null : () => _showLongPressMenu(msg),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
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
                      if (msg['is_forwarded'] == true) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forward, size: 12, color: (isMe ? AppColors.backgroundColor : Colors.white).withOpacity(0.6)),
                            const SizedBox(width: 4),
                            Text(
                              "Forwarded",
                              style: TextStyle(
                                color: (isMe ? AppColors.backgroundColor : Colors.white).withOpacity(0.6),
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (msg['replied_to'] != null) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                            border: const Border(left: BorderSide(color: AppColors.secondaryColor, width: 4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userNames[msg['replied_to']['sender_id']] ?? "User",
                                style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                msg['replied_to']['content'] ?? "Original message was deleted",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Text(
                        msg['is_deleted'] == true ? "This message was deleted" : msg['content'],
                        style: TextStyle(
                          color: isMe ? AppColors.backgroundColor : AppColors.textPrimary,
                          fontSize: 15,
                          fontStyle: msg['is_deleted'] == true ? FontStyle.italic : FontStyle.normal,
                        )
                      ),
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
                Positioned(
                  bottom: 2,
                  right: isMe ? 12 : null,
                  left: isMe ? null : 12,
                  child: GestureDetector(
                    onTap: () => _showReactionDetails(msg),
                    child: Wrap(
                      children: reactions.take(3).map((r) { // Show up to 3 emojis in a group
                        final bool hasReacted = (r['userIds'] as List<dynamic>).contains(_currentUserId);
                        return ReactionBadge(
                          emoji: r['emoji'],
                          count: r['count'],
                          isMe: hasReacted,
                          onTap: () => _showReactionDetails(msg),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) {
        final isMe = index % 2 == 0;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
            width: 150 + (index * 10.0),
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(color: AppColors.surfaceColor, border: Border(bottom: BorderSide(color: Colors.white12))),
            child: Row(
              children: [
                const Icon(Icons.reply, color: AppColors.secondaryColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userNames[_replyingToMessage['sender_id']] ?? "User",
                        style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        _replyingToMessage['content'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => setState(() => _replyingToMessage = null),
                ),
              ],
            ),
          ),
        Container(
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
        ),
      ],
    );
  }
}
