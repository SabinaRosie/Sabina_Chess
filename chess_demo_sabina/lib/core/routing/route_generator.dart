import 'package:flutter/material.dart';
import '../../features/auth/pages/signup_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../pages/splashscreen.dart';
import '../../features/dashboard/pages/home_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/auth/pages/forgot_password_page.dart';
import '../../features/profile/pages/users_list_page.dart';
import '../../features/chat/pages/call_page.dart';
import '../../features/chat/pages/conversations_page.dart';
import '../../features/chat/pages/chat_page.dart';
import '../../features/profile/pages/public_profile_page.dart';
import '../../features/game/pages/game_screen.dart';
import '../../features/profile/pages/friend_selection_page.dart';
import '../../features/game/pages/live_game_page.dart';
import '../../features/game/pages/game_invitation_screen.dart';
import '../../features/game/pages/challenge_accepted_page.dart';
import '../../features/game/pages/game_invitation_waiting_screen.dart';
import './route_const.dart';

class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    debugPrint("ROUTE_GEN: Navigating to ${settings.name} with args: ${settings.arguments}");
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

      case Routes.conversationsRoute:
        return MaterialPageRoute(builder: (_) => const ConversationsPage());

      case Routes.chatRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: args['conversationId'],
            otherUser: args['otherUser'],
          ),
        );

      case Routes.publicProfileRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => PublicProfilePage(user: args['user']),
        );

      case Routes.friendSelectionRoute:
        return MaterialPageRoute(builder: (_) => const FriendSelectionPage());

      case Routes.liveGameRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LiveGamePage(
            gameId: args['gameId'],
            opponentId: args['opponentId'],
            opponentUsername: args['opponentUsername'],
            userColor: args['color'],
          ),
        );

      case Routes.gameInvitationRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => GameInvitationScreen(
            invitationId: args['invitationId'],
            senderId: args['senderId'],
            senderUsername: args['senderUsername'],
          ),
        );
      
      case Routes.challengeAcceptedRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ChallengeAcceptedPage(
            gameId: args['gameId'],
            opponentId: args['opponentId'],
            opponentUsername: args['opponentUsername'],
            opponentPhotoUrl: args['opponentPhotoUrl'],
          ),
        );

      case Routes.invitationWaitingRoute:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => GameInvitationWaitingScreen(
            invitationId: args['invitationId'],
            gameId: args['gameId'],
            opponentId: args['opponentId'],
            opponentUsername: args['opponentUsername'],
          ),
        );

      default:
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text("No route found"))),
        );
    }
  }

  static Future<dynamic> navigateToPage(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamed(context, routeName, arguments: arguments);
  }

  static void navigateToPageWithoutStack(
    BuildContext context,
    String routeName,
  ) {
    Navigator.pushReplacementNamed(context, routeName);
  }
}
