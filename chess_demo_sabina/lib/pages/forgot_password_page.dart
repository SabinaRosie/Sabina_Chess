import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  int step = 0; // 0: Email, 1: OTP, 2: New Password
  
  String email = "";
  String otp = "";
  String newPassword = "";
  bool loader = false;
  bool showPassword = false;

  int _timerSeconds = 60;
  bool _canResend = false;
  Timer? _timer;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reset Password"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Icon(
                    step == 0 ? Icons.email_outlined : step == 1 ? Icons.lock_clock_outlined : Icons.lock_reset_rounded,
                    size: 80,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    step == 0 ? "Forgot Password?" : step == 1 ? "Enter OTP" : "New Password",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    step == 0 
                      ? "Don't worry! Enter your email below to receive a reset code." 
                      : step == 1 
                        ? "Enter the 6-digit code sent to $email"
                        : "Almost there! Create a strong new password for your account.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 40),

                  if (step == 0) ...[
                    _buildLabel("EMAIL ADDRESS"),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: _inputDecoration("Enter email", Icons.mail_outline),
                      onChanged: (val) => email = val.trim(),
                      validator: (val) => val != null && val.contains("@") ? null : "Enter valid email",
                    ),
                  ] else if (step == 1) ...[
                    _buildLabel("VERIFICATION CODE"),
                    const SizedBox(height: 8),
                    TextFormField(
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
                      decoration: _inputDecoration("000000", null).copyWith(counterText: ""),
                      onChanged: (val) => otp = val.trim(),
                      validator: (val) => val != null && val.length == 6 ? null : "Enter 6-digits",
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_canResend ? "Didn't receive code? " : "Resend code in "),
                        if (_canResend)
                          GestureDetector(
                            onTap: () async {
                              _startTimer();
                              await ApiService.forgotPassword(email);
                            },
                            child: const Text("Resend", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          )
                        else
                          Text("${_timerSeconds}s", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ] else if (step == 2) ...[
                    _buildLabel("NEW PASSWORD"),
                    const SizedBox(height: 8),
                    TextFormField(
                      obscureText: !showPassword,
                      decoration: _inputDecoration("New password", Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(showPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => showPassword = !showPassword),
                        ),
                      ),
                      onChanged: (val) => newPassword = val,
                      validator: (val) => val != null && val.length >= 6 ? null : "Min 6 characters",
                    ),
                  ],

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 4,
                      ),
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() => loader = true);
                          
                          Map<String, dynamic> result;
                          if (step == 0) {
                            result = await ApiService.forgotPassword(email);
                            if (result['success']) {
                              setState(() => step = 1);
                              _startTimer();
                            }
                          } else if (step == 1) {
                            result = await ApiService.verifyOtp(email, otp);
                            if (result['success']) {
                              setState(() => step = 2);
                            }
                          } else {
                            result = await ApiService.resetPassword(email, newPassword);
                            if (result['success']) {
                              if (context.mounted) {
                                _showSuccessDialog(context, "Your password has been reset successfully.");
                              }
                            }
                          }

                          if (context.mounted) {
                            setState(() => loader = false);
                            if (result != null && !result['success']) {
                              _showErrorDialog(context, result['error'] ?? 'An unexpected error occurred');
                            }
                          }
                        }
                      },
                      child: loader 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              step == 0 ? "Send Code" : step == 1 ? "Verify Code" : "Reset Password",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  if (step == 1)
                    TextButton(
                      onPressed: () => setState(() => step = 0),
                      child: const Text("Entered wrong email? Change it", style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData? icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      filled: true,
      fillColor: Colors.grey.withOpacity(0.05),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Verification failed"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 10),
            Text("Success"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              RouteGenerator.navigateToPageWithoutStack(context, Routes.loginRoute);
            },
            child: const Text("Log In Now", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
