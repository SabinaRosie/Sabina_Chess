import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';

class GameInvitationWaitingScreen extends StatefulWidget {
  final String gameId;
  final int opponentId;
  final String opponentUsername;

  const GameInvitationWaitingScreen({
    super.key,
    required this.gameId,
    required this.opponentId,
    required this.opponentUsername,
  });

  @override
  State<GameInvitationWaitingScreen> createState() => _GameInvitationWaitingScreenState();
}

class _GameInvitationWaitingScreenState extends State<GameInvitationWaitingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription? _invitationSub;
  Timer? _timeoutTimer;
  int _secondsLeft = 120;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startTimeout();
    _listenToInvitations();
  }

  void _startTimeout() {
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _handleTimeout();
      }
    });
  }

  void _listenToInvitations() {
    _invitationSub = NotificationService().invitationEventStream.listen((event) {
      if (!mounted) return;

      if (event['type'] == 'accepted' && event['game_id'] == widget.gameId) {
        _handleAccepted(event);
      } else if (event['type'] == 'declined' && event['opponent_username'] == widget.opponentUsername) {
        _handleDeclined();
      }
    });
  }

  void _handleAccepted(Map<String, dynamic> event) {
    _timeoutTimer?.cancel();
    _invitationSub?.cancel();
    
    // Navigate to Live Game
    Navigator.pushReplacementNamed(
      context,
      Routes.liveGameRoute,
      arguments: {
        'gameId': widget.gameId,
        'opponentId': widget.opponentId,
        'opponentUsername': widget.opponentUsername,
        'color': 'white',
      },
    );
  }

  void _handleDeclined() {
    if (_isCancelled) return;
    _showMinimalPopup("${widget.opponentUsername} declined the invitation.", isError: true);
    _close();
  }

  void _handleTimeout() {
    if (_isCancelled) return;
    _showMinimalPopup("Invitation timed out. No response received.", isError: true);
    _cancelInvitation();
  }

  Future<void> _cancelInvitation() async {
    if (_isCancelled) return;
    _isCancelled = true;
    _timeoutTimer?.cancel();
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    if (token != null) {
      // Find the invitation ID if needed, or if game_id is used for cancellation
      // For now we just go back as the backend will clean up or the user can cancel from Sent tab
      await ApiService.cancelInvitation(token, widget.gameId);
    }
    _close();
  }

  void _close() {
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showMinimalPopup(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _invitationSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.woodGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Pulsing Icon
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondaryColor.withOpacity(0.1),
                    border: Border.all(
                      color: AppColors.secondaryColor.withOpacity(0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondaryColor.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.hourglass_empty_rounded,
                    size: 60,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                "Waiting for Opponent",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Waiting for ${widget.opponentUsername} to accept...",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              // Timer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.secondaryColor.withOpacity(0.3)),
                ),
                child: Text(
                  "Expires in $_secondsLeft s",
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const Spacer(),
              // Cancel Button
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.2),
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _cancelInvitation,
                    child: const Text(
                      "Cancel Invitation",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
