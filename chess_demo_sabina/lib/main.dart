import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/route_const.dart';
import 'utils/route_generator.dart';
import 'services/notification_service.dart';
import 'services/foreground_service.dart';

// 🔹 Top-level background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed (some platforms require this in background)
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
  // The notification is automatically shown by the system for "Notification" type messages.
  // For "Data" type messages, you would use flutter_local_notifications here.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
