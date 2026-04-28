import 'package:flutter/material.dart';
import '../pages/signup_page.dart';
import '../pages/login_page.dart';
import '../pages/splashscreen.dart';
import '../pages/home_page.dart';
import '../pages/profile_page.dart';
import '../pages/forgot_password_page.dart';
import '../pages/users_list_page.dart';
import '../pages/call_page.dart';
import '../screens/game_screen.dart';
import 'route_const.dart';

class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splashRoute:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case Routes.signupRoute:
        return MaterialPageRoute(builder: (_) => const SignupPage());

      case Routes.loginRoute:
        return MaterialPageRoute(builder: (_) => const LoginPage());

      case Routes.gameRoute:
        return MaterialPageRoute(builder: (_) => const GameScreen());

      case Routes.homeRoute:
        return MaterialPageRoute(builder: (_) => const HomePage());

      case Routes.profileRoute:
        return MaterialPageRoute(builder: (_) => const ProfilePage());

      case Routes.forgotPasswordRoute:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordPage());

      case Routes.usersListRoute:
        return MaterialPageRoute(builder: (_) => const UsersListPage());

      case Routes.callRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => CallPage(
            roomId: args['roomId'],
            remoteUsername: args['remoteUsername'],
            callType: args['callType'],
            isCaller: args['isCaller'],
          ),
        );

      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text("No route found"))),
        );
    }
  }

  static void navigateToPage(BuildContext context, String routeName) {
    Navigator.pushNamed(context, routeName);
  }

  static void navigateToPageWithoutStack(
    BuildContext context,
    String routeName,
  ) {
    Navigator.pushReplacementNamed(context, routeName);
  }
}
