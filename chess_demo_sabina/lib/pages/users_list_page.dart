import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../services/signaling_service.dart';
import '../utils/color_utils.dart';
import 'call_page.dart';

class UsersListPage extends StatefulWidget {
  const UsersListPage({super.key});

  @override
  State<UsersListPage> createState() => _UsersListPageState();
}

class _UsersListPageState extends State<UsersListPage> {
  List<dynamic> users = [];
  bool isLoading = true;
  String? error;
  String? _accessToken;
  Timer? _incomingCallTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken');
    await _fetchUsers();
    _startIncomingCallPolling();
  }

  @override
  void dispose() {
    _incomingCallTimer?.cancel();
    super.dispose();
  }

  void _startIncomingCallPolling() {
    _incomingCallTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkIncomingCalls(),
    );
  }

  Future<void> _checkIncomingCalls() async {
    if (!mounted) return;

    final result = await SignalingService.checkIncoming();
    if (!result['success'] || !mounted) return;

    final data = result['data'];
    if (data['has_incoming'] == true) {
      _incomingCallTimer?.cancel(); // Stop polling while dialog is shown
      _showIncomingCallDialog(
        roomId: data['room_id'],
        callerName: data['caller'],
        callType: data['call_type'],
      );
    }
  }

  void _showIncomingCallDialog({
    required String roomId,
    required String callerName,
    required String callType,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.4)),
        ),
        title: Column(
          children: [
            // Animated call icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primaryColor, AppColors.secondaryColor],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondaryColor.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  callerName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              callerName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Incoming ${callType == 'video' ? 'Video' : 'Audio'} Call',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actionsPadding: const EdgeInsets.only(bottom: 20),
        actions: [
          // Reject
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await SignalingService.answerCall(
                roomId,
                'reject',
              );
              _startIncomingCallPolling(); // Resume polling
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_end,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),

          // Accept
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await SignalingService.answerCall(
                roomId,
                'accept',
              );
              if (mounted) {
                _navigateToCall(
                  roomId: roomId,
                  remoteUsername: callerName,
                  callType: callType,
                  isCaller: false,
                );
              }
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                callType == 'video' ? Icons.videocam : Icons.call,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchUsers() async {
    if (_accessToken != null) {
      final result = await ApiService.getUsers(_accessToken!);
      if (result['success']) {
        setState(() {
          users = result['data'];
          isLoading = false;
        });
      } else {
        setState(() {
          error = result['error'];
          isLoading = false;
        });
      }
    } else {
      setState(() {
        error = "Not authenticated";
        isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions(String callType) async {
    await Permission.microphone.request();
    if (callType == 'video') {
      await Permission.camera.request();
    }
  }

  Future<void> _initiateCall(String username, String callType) async {
    if (_accessToken == null) return;

    // Request permissions
    await _requestPermissions(callType);

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      if (mounted) {
        _showErrorDialog(context, "Microphone permission is required for calls.");
      }
      return;
    }

    if (callType == 'video') {
      final camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        if (mounted) {
          _showErrorDialog(context, "Camera permission is required for video calls.");
        }
        return;
      }
    }

    // Create call on server
    final result = await SignalingService.createCall(
      username,
      callType,
    );

    if (result['success'] && mounted) {
      final data = result['data'];
      _navigateToCall(
        roomId: data['room_id'],
        remoteUsername: username,
        callType: callType,
        isCaller: true,
      );
    } else if (mounted) {
      _showErrorDialog(context, result['error'] ?? 'Failed to create call');
    }
  }

  void _navigateToCall({
    required String roomId,
    required String remoteUsername,
    required String callType,
    required bool isCaller,
  }) {
    _incomingCallTimer?.cancel(); // Stop polling during call
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(
          roomId: roomId,
          remoteUsername: remoteUsername,
          callType: callType,
          isCaller: isCaller,
        ),
      ),
    ).then((_) {
      // Resume polling when returning from call
      _startIncomingCallPolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Community Users",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.backgroundColor,
        elevation: 0,
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
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.secondaryColor,
                ),
              )
            : error != null
            ? Center(
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              )
            : users.isEmpty
            ? const Center(
                child: Text(
                  "No users found",
                  style: TextStyle(color: Colors.white54),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return _buildUserCard(user);
                },
              ),
      ),
    );
  }

  Widget _buildUserCard(dynamic user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.secondaryColor.withOpacity(0.2),
          child: Text(
            user['username'][0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user['username'],
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Audio call button
            Container(
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.call, color: Colors.greenAccent, size: 20),
                onPressed: () => _initiateCall(user['username'], 'audio'),
                tooltip: 'Audio Call',
              ),
            ),
            const SizedBox(width: 8),
            // Video call button
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.videocam, color: Colors.lightBlueAccent, size: 20),
                onPressed: () => _initiateCall(user['username'], 'video'),
                tooltip: 'Video Call',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Error", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
