import 'dart:async';
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
  bool isLoading = true;
  String? error;
  String? _accessToken;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
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
          "An invitation will be sent immediately. They will have 60 seconds to respond.",
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
    int timeLeft = 60;
    Timer? timer;
    bool invitationCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (timeLeft > 0) {
              setDialogState(() => timeLeft--);
            } else {
              t.cancel();
              if (Navigator.canPop(context)) Navigator.pop(context);
              _showTimeoutMessage(user['username']);
            }
          });

          return AlertDialog(
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
                Text(
                  "Closing in ${timeLeft}s",
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      invitationCancelled = true;
                      timer?.cancel();
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
          );
        },
      ),
    ).then((_) {
      timer?.cancel();
    });
  }

  void _showTimeoutMessage(String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("No Response", style: TextStyle(color: AppColors.secondaryColor)),
        content: Text("$username did not respond in time.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: AppColors.secondaryColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("Select a Friend", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.secondaryColor),
          onPressed: () => Navigator.pop(context),
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
                : users.isEmpty
                    ? const Center(child: Text("No other users found", style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: users.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _buildUserCard(users[index]),
                      ),
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
