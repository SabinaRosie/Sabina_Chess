import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/routing/route_const.dart';
import '../../../core/routing/route_generator.dart';
import 'package:intl/intl.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _conversations = [];
  List<dynamic> _filteredConversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _searchController.addListener(_filterConversations);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final result = await _chatService.listConversations();
    if (result['success']) {
      if (mounted) {
        setState(() {
          _conversations = result['data'];
          _filteredConversations = _conversations;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterConversations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredConversations = _conversations.where((conv) {
        final username = conv['other_user']['username'].toString().toLowerCase();
        return username.contains(query);
      }).toList();
    });
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Messages", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        centerTitle: false,
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
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.secondaryColor))
                  : _filteredConversations.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadConversations,
                          color: AppColors.secondaryColor,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 10, bottom: 100), // ── 🔹 Extra space for scrolling past the button ──
                            itemCount: _filteredConversations.length,
                            itemBuilder: (context, index) {
                              final conv = _filteredConversations[index];
                              final otherUser = conv['other_user'];
                              final lastMsg = conv['last_message'] ?? "No messages yet";
                              final unreadCount = conv['unread_count'] ?? 0;

                              return _buildConversationTile(conv, otherUser, lastMsg, unreadCount);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60), // ── 🔹 Lift button above Nav Bar ──
        child: FloatingActionButton(
          backgroundColor: AppColors.secondaryColor,
          elevation: 4,
          onPressed: () {
            RouteGenerator.navigateToPage(context, Routes.usersListRoute);
          },
          child: const Icon(Icons.add_comment_rounded, color: AppColors.backgroundColor),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search or start new chat",
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 15),
            prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
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
          const Text("No conversations found", style: TextStyle(color: AppColors.textSecondary, fontSize: 18)),
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
        }).then((_) => _loadConversations());
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.primaryColor, AppColors.secondaryColor.withOpacity(0.8)],
          ),
          border: Border.all(color: AppColors.secondaryColor.withOpacity(0.2), width: 1.5),
        ),
        child: Center(
          child: Text(
            otherUser['username'][0].toUpperCase(),
            style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      title: Text(
        otherUser['username'],
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          lastMsg,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: unreadCount > 0 ? Colors.white : AppColors.textSecondary,
            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(conv['last_message_time']),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.secondaryColor, borderRadius: BorderRadius.circular(10)),
              constraints: const BoxConstraints(minWidth: 20),
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
