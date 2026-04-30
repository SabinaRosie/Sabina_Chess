import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import 'package:intl/intl.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final ChatService _chatService = ChatService();
  List<dynamic> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final result = await _chatService.listConversations();
    if (result['success']) {
      setState(() {
        _conversations = result['data'];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return "";
    try {
      final DateTime dateTime = DateTime.parse(timeStr).toLocal();
      final now = DateTime.now();
      if (dateTime.day == now.day && dateTime.month == now.month && dateTime.year == now.year) {
        return DateFormat('HH:mm').format(dateTime);
      }
      return DateFormat('MMM d').format(dateTime);
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Messages", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.secondaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.woodGradient,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.secondaryColor))
            : _conversations.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadConversations,
                    color: AppColors.secondaryColor,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: _conversations.length,
                      itemBuilder: (context, index) {
                        final conv = _conversations[index];
                        final otherUser = conv['other_user'];
                        final lastMsg = conv['last_message'] ?? "No messages yet";
                        final unreadCount = conv['unread_count'] ?? 0;

                        return _buildConversationTile(conv, otherUser, lastMsg, unreadCount);
                      },
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.secondaryColor,
        onPressed: () => RouteGenerator.navigateToPage(context, Routes.usersListRoute),
        child: const Icon(Icons.message, color: AppColors.backgroundColor),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text("No conversations yet", style: TextStyle(color: AppColors.textSecondary, fontSize: 18)),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: AppColors.backgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => RouteGenerator.navigateToPage(context, Routes.usersListRoute),
            child: const Text("Start Chatting"),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(dynamic conv, dynamic otherUser, String lastMsg, int unreadCount) {
    return ListTile(
      onTap: () {
        RouteGenerator.navigateToPage(context, Routes.chatRoute, arguments: {
          'conversationId': conv['id'],
          'otherUser': otherUser,
        });
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.primaryColor, AppColors.secondaryColor.withOpacity(0.8)],
          ),
          border: Border.all(color: AppColors.secondaryColor.withOpacity(0.3), width: 2),
        ),
        child: Center(
          child: Text(
            otherUser['username'][0].toUpperCase(),
            style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      title: Text(
        otherUser['username'],
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              lastMsg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unreadCount > 0 ? Colors.white : AppColors.textSecondary,
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(conv['last_message_time']),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 5),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: AppColors.secondaryColor, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                unreadCount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.backgroundColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
