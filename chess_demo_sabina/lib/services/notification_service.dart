import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'signaling_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _configureAudio();
  }

  StreamSubscription? _wsSubscription;
  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  bool _isIncomingDialogShown = false;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  static const String ringtoneUrl = 'https://assets.mixkit.co/active_storage/sfx/1359/1359-preview.mp3';

  // Global navigator key to show dialogs from anywhere
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void _configureAudio() {
    // 🔹 Ensure ringtone is audible even if the app is in background
    AudioPlayer.global.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🔹 Immediately check for calls when returning to foreground
      _checkOnce();
      _initNotifications(); // Re-establish socket if dropped
    }
  }

  void init() {
    _initNotifications();
    _startPolling();
  }

  Future<void> _checkOnce() async {
    if (!_isIncomingDialogShown) {
      final result = await SignalingService.checkIncoming();
      if (result['success'] && result['data']['has_incoming'] == true) {
        _handleIncomingCall(result['data']);
      }
    }
  }

  void _initNotifications() async {
    _wsSubscription?.cancel();
    final stream = await SignalingService.connectNotificationSocket();
    
    if (stream != null) {
      _wsSubscription = stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'incoming_call') {
            _handleIncomingCall(data['data']);
          } else if (data['type'] == 'call_cancelled') {
            _cancelIncomingCall();
          }
        },
        onDone: _reconnect,
        onError: (e) => _reconnect(),
      );
    } else {
      _reconnect();
    }
  }

  void _reconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _initNotifications);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isIncomingDialogShown) {
        final result = await SignalingService.checkIncoming();
        if (result['success'] && result['data']['has_incoming'] == true) {
          _handleIncomingCall(result['data']);
        }
      }
    });
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    if (_isIncomingDialogShown) return;
    _isIncomingDialogShown = true;
    
    final context = navigatorKey.currentContext;
    if (context == null) return;

    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    _ringtonePlayer.play(UrlSource(ringtoneUrl));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: AppColors.secondaryColor.withValues(alpha: 0.3), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Animated Avatar Placeholder
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primaryColor, AppColors.secondaryColor.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondaryColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Center(
                child: Text(
                  data['caller'].toString().isNotEmpty ? data['caller'].toString()[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 25),
            Text(
              data['caller'] ?? "Unknown",
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Incoming ${data['call_type'] == 'video' ? 'Video' : 'Audio'} Call",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject Button
                GestureDetector(
                  onTap: () {
                    _ringtonePlayer.stop();
                    _isIncomingDialogShown = false;
                    Navigator.pop(ctx);
                    SignalingService.answerCall(data['room_id'], 'reject');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.call_end, color: Colors.redAccent, size: 32),
                  ),
                ),
                // Accept Button
                GestureDetector(
                  onTap: () {
                    _ringtonePlayer.stop();
                    _isIncomingDialogShown = false;
                    Navigator.pop(ctx);
                    SignalingService.answerCall(data['room_id'], 'accept');
                    
                    navigatorKey.currentState?.pushNamed(Routes.callRoute, arguments: {
                      'roomId': data['room_id'],
                      'remoteUsername': data['caller'],
                      'callType': data['call_type'],
                      'isCaller': false,
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                    ),
                    child: Icon(
                      data['call_type'] == 'video' ? Icons.videocam : Icons.call,
                      color: Colors.greenAccent,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _cancelIncomingCall() {
    if (_isIncomingDialogShown) {
      _ringtonePlayer.stop();
      _isIncomingDialogShown = false;
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSubscription?.cancel();
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
    _ringtonePlayer.dispose();
  }
}
