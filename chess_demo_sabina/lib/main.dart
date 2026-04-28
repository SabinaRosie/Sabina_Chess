import 'package:flutter/material.dart';
import 'utils/route_const.dart';
import 'utils/route_generator.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService().init();
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
