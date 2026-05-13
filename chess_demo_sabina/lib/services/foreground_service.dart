import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

@pragma('vm:entry-point')
void foregroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(ChessTaskHandler());
}

class ChessTaskHandler extends TaskHandler {
  int _currentTipIndex = 0;

  static final List<String> _chessTips = [
    "Control the center of the board 🎯",
    "Develop your pieces early ♟️",
    "Don't move the same piece twice in opening 🔄",
    "Castle early to protect your king 🏰",
    "Connect your rooks 🔗",
    "Think before you move ⏱️",
    "Control key squares 📍",
    "Don't bring your queen out too early 👑",
    "Look for tactical opportunities 👀",
    "Always check for checks! ✓",
  ];

  static String _getCurrentTime() {
    final now = DateTime.now();
    return DateFormat('h:mm a').format(now);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint("ChessTaskHandler: Started");
    _updateNotification();
  }

  void _updateNotification() {
    final String currentTime = _getCurrentTime();
    final String currentTip = _chessTips[_currentTipIndex];
    
    FlutterForegroundTask.updateService(
      notificationTitle: '🕐 $currentTime • Chess Daily',
      notificationText: currentTip,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _currentTipIndex = (_currentTipIndex + 1) % _chessTips.length;
    _updateNotification();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint("ChessTaskHandler: Destroyed");
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp("/");
  }
}

class ChessForegroundService {
  static bool _isInitialized = false;

  static Future<void> initService() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chess_foreground_service',
        channelName: 'Chess App Service',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(120000), // 2 minutes
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  static Future<void> startService() async {
    if (await FlutterForegroundTask.isRunningService) return;

    await initService();

    // Check permissions
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceTypes: [
        ForegroundServiceTypes.specialUse,
      ],
      notificationTitle: 'Chess App',
      notificationText: 'Service is running',
      callback: foregroundStartCallback,
    );
  }

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }
}
