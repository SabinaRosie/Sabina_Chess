import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/color_utils.dart';
import '../utils/route_generator.dart';
import '../utils/route_const.dart';

class GameInvitationScreen extends StatefulWidget {
  final dynamic invitationId;
  final int senderId;
  final String senderUsername;

  const GameInvitationScreen({
    super.key,
    required this.invitationId,
    required this.senderId,
    required this.senderUsername,
  });

  @override
  State<GameInvitationScreen> createState() => _GameInvitationScreenState();
}

class _GameInvitationScreenState extends State<GameInvitationScreen> {
  bool isProcessing = false;

  Future<void> _handleResponse(String status) async {
    setState(() => isProcessing = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');

    if (token != null) {
      final result = await ApiService.respondInvitation(token, widget.invitationId, status);
      if (mounted) {
        if (result['success']) {
          if (status == 'accepted') {
            // Navigation to game is handled by the result here OR by the global WS listener
            // The API returns game_id on success
            Navigator.pushReplacementNamed(
              context, 
              Routes.liveGameRoute,
              arguments: {
                'gameId': result['data']['game_id'],
                'opponentId': widget.senderId,
                'opponentUsername': widget.senderUsername,
                'color': 'black', // Invited user plays black
              }
            );
          } else {
            Navigator.pop(context);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? "Action failed")),
          );
          setState(() => isProcessing = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // ── Chess Piece Icon ──
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondaryColor.withOpacity(0.1),
                  border: Border.all(color: AppColors.secondaryColor, width: 2),
                ),
                child: const Center(
                  child: Text('⚔️', style: TextStyle(fontSize: 60)),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "CHESS CHALLENGE!",
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "${widget.senderUsername} has challenged you to a live chess match.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
              const Spacer(),
              if (isProcessing)
                const CircularProgressIndicator(color: AppColors.secondaryColor)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: () => _handleResponse('accepted'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("ACCEPT CHALLENGE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: OutlinedButton(
                          onPressed: () => _handleResponse('declined'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white38),
                            foregroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("DECLINE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
