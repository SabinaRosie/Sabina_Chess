import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/signaling_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';

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
  bool _isCallInitiating = false;
  bool _isInitiatingCall = false; // Internal flag for UI feedback
  String? _currentUsername;
  bool _isCallCooldown = false;

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
    
    if (_currentUsername == null && _accessToken != null) {
      final profile = await ApiService.getProfile(_accessToken!);
      if (profile['success']) {
        _currentUsername = profile['data']['username'];
        await prefs.setString('username', _currentUsername!);
      }
    }
    
    await _fetchUsers();
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
            // Case-insensitive filtering for robustness
            users = fetchedUsers.where((u) => 
              u['username'].toString().toLowerCase() != _currentUsername?.toLowerCase()
            ).toList();
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
    if (_accessToken == null || _isCallInitiating || _isInitiatingCall || _isCallCooldown) return;
    
    setState(() {
      _isInitiatingCall = true;
      _isCallCooldown = true;
    });
    
    // Reset cooldown after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isCallCooldown = false);
    });

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
    Navigator.pushNamed(
      context,
      Routes.callRoute,
      arguments: {
        'roomId': roomId,
        'remoteUsername': remoteUsername,
        'callType': callType,
        'isCaller': isCaller,
      },
    ).then((_) {
      if (mounted) {
        _fetchUsers();
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
