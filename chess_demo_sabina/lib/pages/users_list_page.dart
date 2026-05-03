import 'package:chess_demo_sabina/utils/route_generator.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import '../services/signaling_service.dart';
import '../services/chat_service.dart';
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
  String? _currentUsername;

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

  void _initiateChat(dynamic user) {
    RouteGenerator.navigateToPage(context, Routes.chatRoute, arguments: {
      'conversationId': null,
      'otherUser': user,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Community Users", style: TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.secondaryColor),
            onPressed: _fetchUsers,
          )
        ],
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
    );
  }

  Widget _buildUserCard(dynamic user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: () => _initiateChat(user),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.secondaryColor.withOpacity(0.15),
            border: Border.all(color: AppColors.secondaryColor.withOpacity(0.3), width: 1.5),
          ),
          child: Center(
            child: Text(
              user['username'][0].toUpperCase(),
              style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        title: Text(
          user['username'],
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        // Email removed as per request
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          color: AppColors.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          onSelected: (value) {
            if (value == 'chat') {
              _initiateChat(user);
            } else if (value == 'profile') {
              RouteGenerator.navigateToPage(context, Routes.publicProfileRoute, arguments: {'user': user});
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'chat',
              child: Row(
                children: [
                  Icon(Icons.chat, color: AppColors.secondaryColor, size: 20),
                  SizedBox(width: 12),
                  Text("Message", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person, color: AppColors.textSecondary, size: 20),
                  SizedBox(width: 12),
                  Text("View Profile", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
