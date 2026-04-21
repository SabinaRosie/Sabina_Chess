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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Forgot Password")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step == 0) ...[
                  const Text("Enter your email address to receive an OTP.", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Email"),
                    onChanged: (val) => email = val.trim(),
                    validator: (val) => val != null && val.contains("@") ? null : "Enter valid email",
                  ),
                ] else if (step == 1) ...[
                  const Text("Enter the OTP sent to your email.", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "OTP"),
                    onChanged: (val) => otp = val.trim(),
                    validator: (val) => val != null && val.isNotEmpty ? null : "Enter OTP",
                  ),
                ] else if (step == 2) ...[
                  const Text("Enter your new password.", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  TextFormField(
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "New Password"),
                    onChanged: (val) => newPassword = val,
                    validator: (val) => val != null && val.length >= 6 ? null : "Min 6 characters",
                  ),
                ],

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        setState(() => loader = true);
                        
                        Map<String, dynamic> result;
                        if (step == 0) {
                          result = await ApiService.forgotPassword(email);
                          if (result['success']) {
                            setState(() => step = 1);
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
                              _showSuccessDialog(context, "Password reset successful");
                            }
                          }
                        }

                        if (context.mounted) {
                          setState(() => loader = false);
                          if (result != null && !result['success']) {
                            _showErrorDialog(context, result['error'] ?? 'Error');
                          }
                        }
                      }
                    },
                    child: loader 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(step == 0 ? "Send OTP" : step == 1 ? "Verify OTP" : "Reset Password"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
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

  void _showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Colors.green),
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
            child: const Text("Continue to Login", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
