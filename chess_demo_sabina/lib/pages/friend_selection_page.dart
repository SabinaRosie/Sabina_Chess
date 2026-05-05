import 'dart:async';
import 'package:chess_demo_sabina/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_generator.dart';
import '../utils/route_const.dart';

class FriendSelectionPage extends StatefulWidget {
  const FriendSelectionPage({super.key});

  @override
  State<FriendSelectionPage> createState() => _FriendSelectionPageState();
}

class _FriendSelectionPageState extends State<FriendSelectionPage> {
  List<dynamic> users = [];
  List<dynamic> pendingInvitations = [];
  List<dynamic> sentInvitations = [];
  bool isLoading = true;
  String? error;
  String? _accessToken;
  StreamSubscription? _invitationSub;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _invitationSub = NotificationService().invitationCountStream.listen((_) {
      _fetchPendingInvitations();
      _fetchSentInvitations();
    });
  }

  @override
  void dispose() {
    _invitationSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    await _fetchUsers();
    await _fetchPendingInvitations();
    await _fetchSentInvitations();
  }

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken');

    if (_accessToken != null) {
      final result = await ApiService.getGameUsers(_accessToken!);
      if (mounted) {
        if (result['success']) {
          setState(() {
            users = result['data'];
            isLoading = false;
            error = null;
          });
        } else {
          setState(() {
            error = result['error'];
            isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        error = "Not authenticated";
        isLoading = false;
      });
    }
  }

  Future<void> _fetchPendingInvitations() async {
    if (_accessToken == null) return;
    final result = await ApiService.getPendingInvitations(_accessToken!);
    if (mounted && result['success']) {
      setState(() {
        pendingInvitations = result['data'];
      });
    }
  }

  Future<void> _fetchSentInvitations() async {
    if (_accessToken == null) return;
    final result = await ApiService.getSentInvitations(_accessToken!);
    if (mounted && result['success']) {
      setState(() {
        sentInvitations = result['data'];
      });
    }
  }

  void _showInviteDialog(dynamic user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Play with ${user['username']}?",
          style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "An invitation will be sent immediately.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendInvite(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Invite"),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvite(dynamic user) async {
    if (_accessToken == null) return;

    final result = await ApiService.sendInvitation(_accessToken!, user['id']);
    if (mounted) {
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invitation sent!")),
        );
        _fetchSentInvitations();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? "Failed to send invitation")),
        );
      }
    }
  }

  void _showWaitingDialog(dynamic user, dynamic invitationId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const CircularProgressIndicator(color: AppColors.secondaryColor),
            const SizedBox(height: 24),
            Text(
              "Waiting for ${user['username']}...",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              "Invitation sent",
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await ApiService.cancelInvitation(_accessToken!, invitationId);
                  if (context.mounted) Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Cancel Invitation", style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Chess Challenges", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.surfaceColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.secondaryColor),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.secondaryColor,
            labelColor: AppColors.secondaryColor,
            unselectedLabelColor: Colors.white38,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            tabs: [
              Tab(text: "Users", icon: Icon(Icons.person_search_rounded)),
              Tab(text: "Pending", icon: Icon(Icons.inbox_rounded)),
              Tab(text: "Sent", icon: Icon(Icons.send_rounded)),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.woodGradient,
            ),
          ),
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.secondaryColor))
              : error != null
                  ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                  : TabBarView(
                      children: [
                        _buildUserList(),
                        _buildPendingList(),
                        _buildSentList(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildUserList() {
    if (users.isEmpty) {
      return const Center(child: Text("No other users found", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: users.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildUserCard(users[index]),
      ),
    );
  }

  Widget _buildPendingList() {
    if (pendingInvitations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, color: Colors.white12, size: 80),
            SizedBox(height: 16),
            Text(
              "No pending invitations.",
              style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: pendingInvitations.length,
      itemBuilder: (context, index) => _buildPendingInvitationCard(pendingInvitations[index]),
    );
  }

  Widget _buildSentList() {
    if (sentInvitations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_rounded, color: Colors.white12, size: 80),
            SizedBox(height: 16),
            Text(
              "No sent invitations.",
              style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: sentInvitations.length,
      itemBuilder: (context, index) => _buildSentInvitationCard(sentInvitations[index]),
    );
  }

  Widget _buildPendingInvitationCard(dynamic inv) {
    final sender = inv['sender'];
    final timeStr = _formatTime(inv['created_at']);
    final photoUrl = sender['photo_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.secondaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondaryColor.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: _buildProfilePhoto(sender['username'], photoUrl),
        title: Text(
          sender['username'],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "Received $timeStr",
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              icon: Icons.check_rounded,
              color: Colors.greenAccent,
              onPressed: () => _handleResponse(inv['id'], 'accepted', sender),
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              icon: Icons.close_rounded,
              color: Colors.redAccent,
              onPressed: () => _handleResponse(inv['id'], 'declined', sender),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSentInvitationCard(dynamic inv) {
    final receiver = inv['receiver'];
    final timeStr = _formatTime(inv['created_at']);
    final photoUrl = receiver['photo_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildProfilePhoto(receiver['username'], photoUrl),
        title: Text(
          receiver['username'],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Sent $timeStr",
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: TextButton(
          onPressed: () async {
            final res = await ApiService.cancelInvitation(_accessToken!, inv['id']);
            if (res['success']) _fetchSentInvitations();
          },
          child: const Text("Cancel", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildProfilePhoto(String username, String? photoUrl) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.secondaryColor.withOpacity(0.4), width: 1.5),
      ),
      child: ClipOval(
        child: photoUrl != null
            ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildInitial(username))
            : _buildInitial(username),
      ),
    );
  }

  Widget _buildInitial(String username) {
    return Center(
      child: Text(
        username[0].toUpperCase(),
        style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }

  String _formatTime(String createdAt) {
    final diff = DateTime.now().difference(DateTime.parse(createdAt));
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  Future<void> _handleResponse(dynamic invId, String status, dynamic sender) async {
    final result = await ApiService.respondInvitation(_accessToken!, invId, status);
    if (mounted && result['success']) {
      if (status == 'accepted') {
        Navigator.pushReplacementNamed(
          context,
          Routes.liveGameRoute,
          arguments: {
            'gameId': result['data']['game_id'],
            'opponentId': sender['id'],
            'opponentUsername': sender['username'],
            'color': 'black',
          },
        );
      } else {
        _fetchPendingInvitations();
      }
    }
  }

  Widget _buildUserCard(dynamic user) {
    bool isOnline = user['is_online'] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: () => _showInviteDialog(user),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.secondaryColor.withOpacity(0.4),
                    AppColors.primaryColor.withOpacity(0.2),
                  ],
                ),
                border: Border.all(color: AppColors.secondaryColor.withOpacity(0.3), width: 1.5),
              ),
              child: Center(
                child: Text(
                  user['username'][0].toUpperCase(),
                  style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceColor, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          user['username'],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: Text(
          isOnline ? "Online" : "Offline",
          style: TextStyle(color: isOnline ? Colors.green.withOpacity(0.8) : Colors.white38, fontSize: 13),
        ),
        trailing: ChessInviteButton(
          onInvite: () => _sendInvite(user),
          isAlreadyPending: false, // For now, we only handle the immediate feedback
        ),
      ),
    );
  }
}

class ChessInviteButton extends StatefulWidget {
  final VoidCallback onInvite;
  final bool isAlreadyPending;

  const ChessInviteButton({
    super.key,
    required this.onInvite,
    this.isAlreadyPending = false,
  });

  @override
  State<ChessInviteButton> createState() => _ChessInviteButtonState();
}

class _ChessInviteButtonState extends State<ChessInviteButton> {
  bool _isSuccess = false;
  bool _isPending = false;

  @override
  void initState() {
    super.initState();
    _isPending = widget.isAlreadyPending;
  }

  void _handleInvite() {
    if (_isPending || _isSuccess) return;

    widget.onInvite();

    setState(() {
      _isSuccess = true;
    });

    // Show tick for exactly 1 second
    Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isSuccess = false;
          _isPending = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleInvite,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isSuccess 
              ? Colors.green.withOpacity(0.2) 
              : (_isPending ? Colors.white.withOpacity(0.05) : AppColors.secondaryColor.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isSuccess 
                ? Colors.green.withOpacity(0.5) 
                : (_isPending ? Colors.white24 : AppColors.secondaryColor.withOpacity(0.2)),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isSuccess
              ? const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18, key: ValueKey('tick'))
              : Text(
                  _isPending ? "Pending" : "Invite",
                  key: ValueKey(_isPending ? 'pending' : 'invite'),
                  style: TextStyle(
                    color: _isPending ? Colors.white38 : AppColors.secondaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
