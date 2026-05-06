import 'package:flutter/material.dart';
import '../utils/color_utils.dart';
import '../utils/route_const.dart';

class ChallengeAcceptedPage extends StatelessWidget {
  final String gameId;
  final int opponentId;
  final String opponentUsername;
  final String? opponentPhotoUrl;

  const ChallengeAcceptedPage({
    super.key,
    required this.gameId,
    required this.opponentId,
    required this.opponentUsername,
    this.opponentPhotoUrl,
  });

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
              // ── Opponent Profile Photo ──
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.secondaryColor, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondaryColor.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: opponentPhotoUrl != null
                      ? Image.network(
                          opponentPhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                opponentUsername,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Text(
                  "CHALLENGE ACCEPTED!",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "$opponentUsername has accepted your challenge! They are waiting for you at the board.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                ),
              ),
              const Spacer(),
              // ── Action Buttons ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () {
                          debugPrint("CHESS_FLOW: Sender tapping 'Play Now'. gameId: $gameId");
                          
                          if (gameId.isEmpty) {
                            debugPrint("CHESS_ERROR: gameId is null or empty!");
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Error: Invalid game session.")),
                            );
                            return;
                          }

                          Navigator.of(context).pushNamedAndRemoveUntil(
                            Routes.liveGameRoute,
                            (route) => route.isFirst,
                            arguments: {
                              'gameId': gameId,
                              'opponentId': opponentId,
                              'opponentUsername': opponentUsername,
                              'color': 'white',
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown.shade800,
                          foregroundColor: AppColors.secondaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(color: AppColors.secondaryColor, width: 1),
                          ),
                          elevation: 12,
                          shadowColor: Colors.black.withOpacity(0.5),
                        ),
                        child: const Text(
                          "PLAY NOW",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white38),
                          foregroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text(
                          "IGNORE",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
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

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surfaceColor,
      child: Center(
        child: Text(
          opponentUsername[0].toUpperCase(),
          style: const TextStyle(color: AppColors.secondaryColor, fontSize: 60, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
