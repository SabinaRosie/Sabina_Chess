import 'dart:async';
import 'dart:convert';

import 'package:chess_demo_sabina/core/services/notification_service.dart';
import 'package:flutter/material.dart';
import '../../../core/routing/route_const.dart';
import '../../../core/routing/route_generator.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/services/api_service.dart';
import '../../payment/services/esewa_service.dart';
import '../../../core/services/reward_ad_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _showInfo = false; // ── Toggle for description ──
  int _invitationCount = 0;
  int _coins = 0;
  StreamSubscription? _invitationSub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    WidgetsBinding.instance.addObserver(this);
    _invitationSub = NotificationService().invitationCountStream.listen((
      count,
    ) {
      if (mounted) setState(() => _invitationCount = count);
    });
    // Initial fetch
    _invitationCount = NotificationService().currentInvitationCount;
    _fetchCoins();
  }

  Future<void> _fetchCoins() async {
    final result = await ApiService.getUserProfile();
    if (result['success']) {
      setState(() {
        _coins = result['data']['coins'] ?? 0;
      });
    }
  }

  void _showCoinDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0F0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 12),
            Text(
              "Wallet Balance",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    "$_coins",
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    "Total Coins",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _payWithEsewa(
                    100,
                    "coins_1000",
                  ); // Example: 100 NPR for 1000 coins
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Buy More Coins",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── Watch Ad to Earn Coins Button ──
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _watchAdForCoins();
                },
                icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
                label: const Text(
                  "Watch Ad (+100 Coins)",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber,
                  side: BorderSide(color: Colors.amber.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _payWithEsewa(double amount, String productId) async {
    // 1. Initiate on Backend to get a unique Transaction UUID
    final initResult = await ApiService.initiatePayment(amount, productId);
    if (!initResult['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to initiate: ${initResult['error']}")),
        );
      }
      return;
    }

    // Extract the transaction_uuid created by the backend
    final paymentData = initResult['data']['payment_data'];
    final String transactionUuid = paymentData['transaction_uuid'];

    // 2. Launch Native eSewa SDK
    EsewaService.initiatePayment(
      productId:
          transactionUuid, // Use UUID as productId to guarantee uniqueness
      productName: "Chess Coins ($amount NPR)",
      amount: amount.toString(),
      onSuccess: () async {
        // 3. Payment successful and verified by SDK. Now inform Backend to add coins.
        // We mock the base64 structure the backend verify_payment expects.
        final payload = {
          "transaction_uuid": transactionUuid,
          "total_amount": amount.toString(),
          "status": "COMPLETE",
          "transaction_code": "NATIVE_SDK_SUCCESS",
        };
        final encodedData = base64.encode(utf8.encode(jsonEncode(payload)));

        final verifyResult = await ApiService.verifyPayment(encodedData);

        if (verifyResult['success']) {
          _fetchCoins(); // Update the UI balance
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Payment Successful! Coins added."),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Backend Verification Failed: ${verifyResult['error']}",
                ),
              ),
            );
          }
        }
      },
      onFailure: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );
  }

  void _watchAdForCoins() {
    if (!RewardAdService.isAdReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ad is loading, please try again in a moment."),
          backgroundColor: Colors.orange,
        ),
      );
      RewardAdService.loadAd();
      return;
    }

    RewardAdService.showAd(
      onRewardEarned: () async {
        // User watched the full ad — claim coins from backend
        final result = await ApiService.claimReward();
        if (result['success']) {
          final newBalance = result['data']['coins'] ?? _coins + 100;
          setState(() => _coins = newBalance);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("🎉 +100 Coins added to your wallet!"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Fallback: update locally even if backend call fails
          setState(() => _coins += 100);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Coins added locally. Sync issue: ${result['error']}",
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService().updateInvitationCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invitationSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Allow gradient to show through
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
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Coin Header Row ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _showCoinDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.monetization_on_rounded,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "$_coins",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ── Chess King Icon ──
                    Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primaryColor,
                            AppColors.secondaryColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.secondaryColor.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '♔',
                          style: TextStyle(fontSize: 54, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // ── Title ──
                    const Text(
                      'Welcome to Chess',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    // ── Gold accent line ──
                    Container(
                      width: 56,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Description Card (Collapsible) ──
                    GestureDetector(
                      onTap: () => setState(() => _showInfo = !_showInfo),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(
                              _showInfo ? 0.2 : 0.12,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'The Game of Kings',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.secondaryColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  _showInfo
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: AppColors.secondaryColor,
                                  size: 20,
                                ),
                              ],
                            ),
                            if (_showInfo) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Chess is one of the world\'s most beloved strategy '
                                'games, enjoyed by millions for over 1,500 years. '
                                'It is a battle of minds — two players, 32 pieces, '
                                'and an infinite number of possibilities.\n\n'
                                'Anticipate your opponent\'s moves, protect your King, '
                                'and control the board. Whether you\'re a beginner or '
                                'a grandmaster in the making, every move tells a story.',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.textSecondary,
                                  height: 1.75,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ] else ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Tap to learn about the game',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // ── Play with Friends Button ──
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: OutlinedButton(
                              onPressed: () {
                                NotificationService().clearInvitationCount();
                                RouteGenerator.navigateToPage(
                                  context,
                                  Routes.friendSelectionRoute,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.secondaryColor,
                                  width: 2,
                                ),
                                foregroundColor: AppColors.secondaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_alt_rounded, size: 24),
                                  SizedBox(width: 10),
                                  Text(
                                    'Play with Friends',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_invitationCount > 0)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.surfaceColor,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // ── Stats Row ──
                    Row(
                      children: [
                        _statCard('♟', 'Strategy', 'Outsmart\nyour opponent'),
                        const SizedBox(width: 12),
                        _statCard('⚔️', 'Battle', 'Protect\nyour King'),
                        const SizedBox(width: 12),
                        _statCard('🏆', 'Victory', 'Claim\ncheckmate'),
                      ],
                    ),
                    const SizedBox(height: 36),
                    // ── Start Playing Button ──
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: () {
                          RouteGenerator.navigateToPage(
                            context,
                            Routes.gameRoute,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                          elevation: 10,
                          shadowColor: AppColors.primaryColor.withOpacity(0.5),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 28),
                            SizedBox(width: 8),
                            Text(
                              'Start Playing',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String emoji, String title, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
