import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import '../services/api_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  String? name, email, password, confirmPassword;
  bool showPassword = false;
  bool showConfirmPassword = false;
  bool loader = false;

  int step = 0; // 0: signup, 1: verify
  String? otp;
  int _timerSeconds = 60;
  bool _canResend = false;
  Timer? _timer;

  // 🔹 Email validation
  bool isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email.trim());
  }

  // 🔹 Password validation
  bool isValidPassword(String password) {
    final regex = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[-_@#$%^&+=]).{6,}$',
    );
    return regex.hasMatch(password);
  }

  // 🔹 Name validation (letters + numbers allowed, but not only numbers)
  bool isValidName(String name) {
    final regex = RegExp(r'^(?!\d+$)[a-zA-Z0-9 ]+$');
    return regex.hasMatch(name.trim());
  }

  // 🔹 Timer for Resend OTP
  void _startTimer() {
    setState(() {
      _timerSeconds = 60;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        setState(() => _canResend = true);
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 🔹 Show Error Dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Error"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // 🔹 Title
                  Text(
                    step == 0 ? "Create Account" : "Verify Email",
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    step == 0 
                      ? "Join the chess community today!" 
                      : "We've sent a 6-digit code to $email",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 40),

                  if (step == 0) ...[
                    // ================= NAME =================
                    _buildLabel("NAME"),
                    const SizedBox(height: 4),
                    TextFormField(
                      onChanged: (value) => name = value,
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter name";
                        if (!isValidName(value)) return "Invalid name";
                        return null;
                      },
                      decoration: _inputDecoration("Enter name"),
                    ),

                    const SizedBox(height: 20),

                    // ================= EMAIL =================
                    _buildLabel("EMAIL ADDRESS"),
                    const SizedBox(height: 4),
                    TextFormField(
                      onChanged: (value) => email = value.trim(),
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter email";
                        if (!isValidEmail(value)) return "Enter valid email";
                        return null;
                      },
                      decoration: _inputDecoration("Enter email"),
                    ),

                    const SizedBox(height: 20),

                    // ================= PASSWORD =================
                    _buildLabel("PASSWORD"),
                    const SizedBox(height: 4),
                    TextFormField(
                      obscureText: !showPassword,
                      onChanged: (value) => password = value,
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter password";
                        if (!isValidPassword(value)) return "Weak password";
                        return null;
                      },
                      decoration: _inputDecoration("Enter password").copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(showPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => showPassword = !showPassword),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ================= CONFIRM PASSWORD =================
                    _buildLabel("CONFIRM PASSWORD"),
                    const SizedBox(height: 4),
                    TextFormField(
                      obscureText: !showConfirmPassword,
                      onChanged: (value) => confirmPassword = value,
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Confirm password";
                        if (value != password) return "Passwords do not match";
                        return null;
                      },
                      decoration: _inputDecoration("Confirm password").copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(showConfirmPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => showConfirmPassword = !showConfirmPassword),
                        ),
                      ),
                    ),
                  ] else ...[
                    // ================= OTP =================
                    _buildLabel("ENTER OTP"),
                    const SizedBox(height: 4),
                    TextFormField(
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (value) => otp = value.trim(),
                      style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      validator: (value) => value != null && value.length == 6 ? null : "Enter 6-digit OTP",
                      decoration: _inputDecoration("000000").copyWith(counterText: ""),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_canResend ? "Didn't receive code? " : "Resend code in "),
                        if (_canResend)
                          GestureDetector(
                            onTap: () async {
                              _startTimer();
                              await ApiService.forgotPassword(email!); // Reuse forgotPassword for resend
                            },
                            child: const Text("Resend", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          )
                        else
                          Text("${_timerSeconds}s", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 30),

                  // ================= PRIMARY BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 5,
                      ),
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => loader = true);

                          if (step == 0) {
                            final result = await ApiService.signup(name!, email!, password!);
                            if (context.mounted) {
                              setState(() => loader = false);
                              if (result['success']) {
                                // 🔹 Save tokens and go to Home (Verification Removed)
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('accessToken', result['data']['access']);
                                await prefs.setString('refreshToken', result['data']['refresh']);
                                
                                if (context.mounted) {
                                  RouteGenerator.navigateToPageWithoutStack(context, Routes.homeRoute);
                                }
                              } else {
                                _showErrorDialog(result['error']);
                              }
                            }
                          } else {
                            final result = await ApiService.verifyOtp(email!, otp!);
                            if (context.mounted) {
                              setState(() => loader = false);
                              if (result['success']) {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('accessToken', result['data']['access']);
                                await prefs.setString('refreshToken', result['data']['refresh']);
                                
                                if (context.mounted) {
                                  RouteGenerator.navigateToPageWithoutStack(context, Routes.homeRoute);
                                }
                              } else {
                                _showErrorDialog(result['error']);
                              }
                            }
                          }
                        }
                      },
                      child: loader
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              step == 0 ? "Sign Up" : "Verify & Continue",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= NAVIGATION LINK =================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(step == 0 ? "Already have an account? " : "Entered wrong email? "),
                      GestureDetector(
                        onTap: () {
                          if (step == 0) {
                            RouteGenerator.navigateToPage(context, Routes.loginRoute);
                          } else {
                            setState(() => step = 0);
                          }
                        },
                        child: Text(
                          step == 0 ? "Login" : "Change Email",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 Reusable label widget
  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  // 🔹 Reusable input decoration
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
    );
  }
}
