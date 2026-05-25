import 'dart:async';
import 'package:flutter/material.dart';
import './dashboard_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../profile/pages/users_list_page.dart';
import '../../chat/pages/conversations_page.dart';
import '../../video_playlist/presentation/screens/video_library_screen.dart';
import '../../../core/utils/color_utils.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../chat/services/chat_service.dart';
import '../../../core/services/foreground_service.dart';

class HomePage extends StatefulWidget {

  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  int _totalUnread = 0;
  Timer? _badgeTimer;
  final ChatService _chatService = ChatService();

  final List<Widget> _pages = [
    const DashboardPage(),
    const VideoLibraryScreen(),
    const UsersListPage(),
    const ConversationsPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _updateUnreadCount();
    _badgeTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateUnreadCount());

    // 🔹 Start Sticky Notification Service
    ChessForegroundService.startService();
  }

  Future<void> _updateUnreadCount() async {
    final count = await _chatService.getTotalUnreadCount();
    if (mounted && _totalUnread != count) {
      setState(() => _totalUnread = count);
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.woodGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent, // Allow container gradient to show
          extendBody:
              true, // ── 🔹 Fix: Allow body to flow under navigation bar ──
          body: IndexedStack(index: _currentIndex, children: _pages),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1A0F0A), // Darker wood shade for bottom
                  Color(0xFF0F0805),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 15,
                  offset: const Offset(0, -2),
                ),
              ],
              // ── 🔹 Fix: Remove potential default borders ──
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                  width: 0.5,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              backgroundColor: Colors.transparent, // Uses container's gradient
              selectedItemColor: AppColors.secondaryColor,
              unselectedItemColor: Colors.white.withOpacity(0.4),
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              onTap: (index) {
                setState(() => _currentIndex = index);
                _updateUnreadCount();
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.play_circle_fill_rounded),
                  label: 'Videos',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.people_rounded),
                  label: 'Community',
                ),
                BottomNavigationBarItem(
                  icon: Stack(
                    children: [
                      const Icon(Icons.chat_bubble_rounded),
                      if (_totalUnread > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _totalUnread > 9 ? '9+' : '$_totalUnread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: 'Messages',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
