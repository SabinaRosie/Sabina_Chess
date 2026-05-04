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
        _showWaitingDialog(user, result['data']['invitation_id']);
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
      length: 2,
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
              Tab(text: "Select User", icon: Icon(Icons.person_search_rounded)),
              Tab(text: "Pending", icon: Icon(Icons.hourglass_empty_rounded)),
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
            Icon(Icons.inbox_rounded, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text("No pending invitations.", style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: pendingInvitations.length,
      itemBuilder: (context, index) => _buildPendingInvitationCard(pendingInvitations[index]),
    );
  }

  Widget _buildPendingInvitationCard(dynamic inv) {
    final sender = inv['sender'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.secondaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondaryColor.withOpacity(0.3)),
      ),
      child: ListTile(
        onTap: () {
          Navigator.pushNamed(
            context,
            Routes.gameInvitationRoute,
            arguments: {
              'invitationId': inv['id'],
              'senderId': sender['id'],
              'senderUsername': sender['username'],
            },
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.secondaryColor.withOpacity(0.5), width: 1.5),
          ),
          child: Center(
            child: Text(
              sender['username'][0].toUpperCase(),
              style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        title: Text(
          sender['username'],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Sent ${DateTime.now().difference(DateTime.parse(inv['created_at'].toString())).inMinutes}m ago",
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.secondaryColor, size: 16),
      ),
    );
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
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.secondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.secondaryColor.withOpacity(0.2)),
          ),
          child: const Text(
            "Invite",
            style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
