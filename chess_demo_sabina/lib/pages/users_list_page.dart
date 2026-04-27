import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
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
  bool _isCallInitiating = false;
  bool _isInitiatingCall = false; // Internal flag for UI feedback
  bool _isIncomingDialogShown = false;
  String? _currentUsername;
  
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  static const String ringtoneUrl = 'https://assets.mixkit.co/active_storage/sfx/1359/1359-preview.mp3';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _accessToken = prefs.getString('accessToken');
    _currentUsername = prefs.getString('username');
    await _fetchUsers();
    _startIncomingCallPolling();
  }

  @override
  void dispose() {
    _incomingCallTimer?.cancel();
    _ringtonePlayer.dispose();
    super.dispose();
  }

  void _startIncomingCallPolling() {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkIncomingCalls(),
    );
  }

  Future<void> _checkIncomingCalls() async {
    if (!mounted || _isIncomingDialogShown || _isCallInitiating) return;

    try {
      final result = await SignalingService.checkIncoming();
      if (!result['success'] || !mounted) return;

      final data = result['data'];
      if (data['has_incoming'] == true && !_isIncomingDialogShown) {
        _isIncomingDialogShown = true;
        _incomingCallTimer?.cancel(); 
        _showIncomingCallDialog(
          roomId: data['room_id'],
          callerName: data['caller'],
          callType: data['call_type'],
        );
      }
    } catch (e) {
      debugPrint('Check incoming error: $e');
    }
  }

  void _showIncomingCallDialog({
    required String roomId,
    required String callerName,
    required String callType,
  }) {
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    _ringtonePlayer.play(UrlSource(ringtoneUrl));

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
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
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
              _ringtonePlayer.stop();
              Navigator.pop(ctx);
              _isIncomingDialogShown = false;
              await SignalingService.answerCall(roomId, 'reject');
              _startIncomingCallPolling(); 
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              child: const Icon(Icons.call_end, color: Colors.white, size: 28),
            ),
          ),

          // Accept
          GestureDetector(
            onTap: () {
              _ringtonePlayer.stop();
              Navigator.pop(ctx);
              _isIncomingDialogShown = false;
              
              _navigateToCall(
                roomId: roomId,
                remoteUsername: callerName,
                callType: callType,
                isCaller: false,
              );
              
              SignalingService.answerCall(roomId, 'accept');
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
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
    if (!mounted) return;
    
    setState(() => isLoading = true);
    
    if (_accessToken != null) {
      try {
        final result = await ApiService.getUsers(_accessToken!);
        if (!mounted) return;
        
        if (result['success']) {
          final List fetchedUsers = result['data'];
          setState(() {
            users = fetchedUsers.where((u) => u['username'] != _currentUsername).toList();
            isLoading = false;
            error = null;
          });
        } else {
          setState(() {
            error = result['error'];
            isLoading = false;
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          error = "Connection error. Please try again.";
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
    if (_accessToken == null || _isCallInitiating || _isInitiatingCall) return;
    
    setState(() => _isInitiatingCall = true);
    _isCallInitiating = true;

    try {
      await _requestPermissions(callType);

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        if (mounted) {
          _showErrorDialog(context, "Microphone permission is required for calls.");
        }
        setState(() => _isInitiatingCall = false);
        _isCallInitiating = false;
        return;
      }

      if (callType == 'video') {
        final camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          if (mounted) {
            _showErrorDialog(context, "Camera permission is required for video calls.");
          }
          setState(() => _isInitiatingCall = false);
          _isCallInitiating = false;
          return;
        }
      }

      // Create call on server
      final result = await SignalingService.createCall(username, callType);

      if (!mounted) {
        _isCallInitiating = false;
        return;
      }

      if (result['success']) {
        final data = result['data'];
        _navigateToCall(
          roomId: data['room_id'],
          remoteUsername: username,
          callType: callType,
          isCaller: true,
        );
      } else {
        _showErrorDialog(context, result['error'] ?? 'Failed to create call');
      }
    } finally {
      if (mounted) {
        setState(() => _isInitiatingCall = false);
      }
      _isCallInitiating = false;
    }
  }

  void _navigateToCall({
    required String roomId,
    required String remoteUsername,
    required String callType,
    required bool isCaller,
  }) {
    _incomingCallTimer?.cancel(); 
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
      if (mounted) {
        _fetchUsers();
        _startIncomingCallPolling();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Community Users", style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.secondaryColor),
            onPressed: _fetchUsers,
          )
        ],
      ),
      body: Stack(
        children: [
          Container(
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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchUsers,
                          child: const Text("Retry"),
                        )
                      ],
                    ),
                  )
                : users.isEmpty
                ? const Center(child: Text("No users found", style: TextStyle(color: Colors.white54)))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: users.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _buildUserCard(users[index]),
                  ),
          ),
          if (_isInitiatingCall)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.secondaryColor),
                    SizedBox(height: 16),
                    Text(
                      "Initiating call...",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
            style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          user['username'],
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(user['email'], style: const TextStyle(color: Colors.white54, fontSize: 13)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _callActionBtn(Icons.call, Colors.green, () => _initiateCall(user['username'], 'audio')),
            const SizedBox(width: 8),
            _callActionBtn(Icons.videocam, Colors.blue, () => _initiateCall(user['username'], 'video')),
          ],
        ),
      ),
    );
  }

  Widget _callActionBtn(IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: color.withOpacity(0.8), size: 20),
        onPressed: onPressed,
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
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryColor)),
          ),
        ],
      ),
    );
  }
}
