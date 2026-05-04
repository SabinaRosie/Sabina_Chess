import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'signaling_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _configureAudio();
    _ringtonePlayer.setSource(UrlSource(ringtoneUrl));
  }

  StreamSubscription? _wsSubscription;
  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isIncomingDialogShown = false;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  static const String ringtoneUrl = 'https://assets.mixkit.co/active_storage/sfx/1359/1359-preview.mp3';

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  void _configureAudio() {
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.defaultToSpeaker, AVAudioSessionOptions.allowBluetooth},
        ),
      ));
      _ringtonePlayer.setVolume(1.0);
    } catch (e) {
      debugPrint("Warning: Could not configure global audio context: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOnce();
      _initNotifications(); 
    }
  }

  void init() {
    _initFirebase();
    _setupLocalNotifications();
    _initNotifications();
    _startPolling();
    _startHeartbeat();
  }

  void _initFirebase() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _fcm.getToken();
      if (token != null) {
        _registerToken(token);
      }

      _fcm.onTokenRefresh.listen(_registerToken);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'incoming_call') {
          _handleIncomingCall(message.data);
        } else {
          _showLocalNotification(message);
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message.data);
      });
    }
  }

  void _registerToken(String token) async {
    await SignalingService.registerFcmToken(token);
  }

  void _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    // Create the high importance channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
    }

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        if (details.payload != null) {
          final data = jsonDecode(details.payload!);
          _handleNotificationTap(data);
        }
      },
    );
  }

  void _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'high_importance_channel', 'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: AppColors.secondaryColor,
      enableLights: true,
      fullScreenIntent: true, // Crucial for showing on top of lock screen
      category: AndroidNotificationCategory.message,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'reply', 'Reply',
          inputs: [AndroidNotificationActionInput(label: 'Type your message...')],
        ),
        AndroidNotificationAction('mark_read', 'Mark as read'),
      ],
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await _localNotifications.show(
      notification?.hashCode ?? DateTime.now().millisecond,
      notification?.title ?? data['sender'] ?? "New Message",
      notification?.body ?? data['content'] ?? "",
      platformChannelSpecifics,
      payload: jsonEncode(data),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    if (data['type'] == 'chat') {
      // Future implementation for direct navigation
    } else if (data['type'] == 'incoming_call') {
      _handleIncomingCall(data);
    } else if (data['type'] == 'game_invitation') {
      _handleGameInvitation(data);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      SignalingService.sendNotificationPing();
    });
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
          } else if (data['type'] == 'chat_notification') {
            _handleChatNotification(data['data']);
          } else if (data['type'] == 'game_invitation') {
            _handleGameInvitation(data['data']);
          } else if (data['type'] == 'invitation_accepted') {
            _handleInvitationAccepted(data['data']);
          } else if (data['type'] == 'invitation_declined') {
            _handleInvitationDeclined(data['data']);
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
          side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.3), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppColors.primaryColor, AppColors.secondaryColor]),
                boxShadow: [BoxShadow(color: AppColors.secondaryColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Center(
                child: Text(
                  data['caller'].toString().isNotEmpty ? data['caller'].toString()[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 25),
            Text(data['caller'] ?? "Unknown", style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Incoming ${data['call_type'] == 'video' ? 'Video' : 'Audio'} Call", style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () {
                    _ringtonePlayer.stop(); _isIncomingDialogShown = false; Navigator.pop(ctx);
                    SignalingService.answerCall(data['room_id'], 'reject');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.redAccent.withOpacity(0.5))),
                    child: const Icon(Icons.call_end, color: Colors.redAccent, size: 32),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _ringtonePlayer.stop(); _isIncomingDialogShown = false; Navigator.pop(ctx);
                    SignalingService.answerCall(data['room_id'], 'accept');
                    navigatorKey.currentState?.pushNamed(Routes.callRoute, arguments: {
                      'roomId': data['room_id'], 'remoteUsername': data['caller'], 'callType': data['call_type'], 'isCaller': false,
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent.withOpacity(0.5))),
                    child: Icon(data['call_type'] == 'video' ? Icons.videocam : Icons.call, color: Colors.greenAccent, size: 32),
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

  void _handleChatNotification(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.secondaryColor, width: 0.5)),
        content: Row(
          children: [
            const Icon(Icons.chat_bubble_outline, color: AppColors.secondaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['sender'] ?? "New Message", style: const TextStyle(color: AppColors.secondaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(data['content'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(label: "REPLY", textColor: AppColors.secondaryColor, onPressed: () {}),
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

  void _handleGameInvitation(Map<String, dynamic> data) {
    navigatorKey.currentState?.pushNamed(
      Routes.gameInvitationRoute,
      arguments: {
        'invitationId': data['invitation_id'],
        'senderId': data['sender_id'],
        'senderUsername': data['sender_username'],
      },
    );
  }

  void _handleInvitationAccepted(Map<String, dynamic> data) {
    // When the sender's invitation is accepted, move them to the live game
    navigatorKey.currentState?.pushReplacementNamed(
      Routes.liveGameRoute,
      arguments: {
        'gameId': data['game_id'],
        'opponentId': data['opponent_id'],
        'opponentUsername': data['opponent_username'],
        'color': 'white', // The sender plays white
      },
    );
  }

  void _handleInvitationDeclined(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Pop any waiting dialog if it exists (via context)
    // Actually, it's better to just show a snackbar or alert
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${data['sender_username']} declined your invitation."),
        backgroundColor: Colors.redAccent,
      ),
    );
    
    // If we are in the waiting dialog, it might need to be popped.
    // In FriendSelectionPage, we handle the timer, but we should also handle this signal.
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSubscription?.cancel();
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _ringtonePlayer.dispose();
  }
}
