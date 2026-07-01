import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fvp/fvp.dart' as fvp;
import './core/routing/route_const.dart';
import './core/routing/route_generator.dart';
import './core/services/notification_service.dart';
import './core/services/foreground_service.dart';
import './core/services/api_service.dart';
import './core/utils/app_logger.dart';
import './core/services/log_sync_service.dart';
import './core/services/reward_ad_service.dart';

// 🔹 Top-level background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed (some platforms require this in background)
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
  
  final notificationId = message.data['notification_id'];
  if (notificationId != null) {
    try {
      ApiService.trackNotification(notificationId.toString(), 'delivered');
    } catch (e) {
      debugPrint("Error tracking background delivery: $e");
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Capture Flutter framework/UI exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.e(
      "Unhandled Flutter UI Error: ${details.exceptionAsString()}",
      error: details.exception,
      stackTrace: details.stack,
      feature: "flutter_framework",
      isFatal: true,
    );
  };

  // 🔹 Capture asynchronous exceptions outside Flutter framework
  // Note: isFatal: false — connectivity/async errors are recoverable, not true crashes
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.e(
      "Unhandled Async Error: $error",
      error: error,
      stackTrace: stack,
      feature: "async_runtime",
      isFatal: false,
    );
    return true;
  };

  fvp.registerWith();
  
  // 🔹 Initialize Foreground Service (Sticky Notification)
  await ChessForegroundService.initService();

  try {

    // 🔹 Initialize Firebase
    await Firebase.initializeApp();

    // 🔹 Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 🔹 Initialize our local notification service
    NotificationService().init();
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
    // Continue app initialization even if Firebase fails (fallback to WS/Polling)
    NotificationService().init();
  }

  // 🔹 Initialize Rewarded Ads
  await RewardAdService.initialize();

  // 🔹 Trigger log sync on startup
  LogSyncService.syncLogs();

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService().navigatorKey,
      initialRoute: Routes.splashRoute,
      onGenerateRoute: RouteGenerator.generateRoute,
    );
  }
}
