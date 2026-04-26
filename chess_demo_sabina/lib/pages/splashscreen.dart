import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import '../utils/color_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;

      // Check if user chose "Remember Me" on last login
      final prefs = await SharedPreferences.getInstance();
      final isRemembered = prefs.getBool('isRemembered') ?? false;
      final hasToken = prefs.getString('accessToken') != null;

      if (mounted) {
        if (isRemembered && hasToken) {
          // Auto-login: go straight to home
          RouteGenerator.navigateToPageWithoutStack(context, Routes.homeRoute);
        } else {
          // Not remembered: go to login
          RouteGenerator.navigateToPageWithoutStack(context, Routes.loginRoute);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.woodGradient,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 2),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("♟️", style: TextStyle(fontSize: 80)),
                        const SizedBox(height: 20),
                        const Text(
                          "Grandmaster Chess",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Strategy. Skill. Victory.",
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: CircularProgressIndicator(
                  color: AppColors.secondaryColor.withOpacity(0.5),
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
