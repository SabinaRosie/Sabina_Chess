import 'package:flutter/material.dart';
import '../../../core/routing/route_const.dart';
import '../../../core/routing/route_generator.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/color_utils.dart';

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

  // Removing step/otp logic as per requirement

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

  // 🔹 Detailed password feedback
  String? getPasswordError(String password) {
    if (password.isEmpty) return 'Enter password';
    List<String> missing = [];
    if (password.length < 6) missing.add('• At least 6 characters');
    if (!RegExp(r'[A-Z]').hasMatch(password))
      missing.add('• An uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(password))
      missing.add('• A lowercase letter');
    if (!RegExp(r'\d').hasMatch(password)) missing.add('• A number');
    if (!RegExp(r'[-_@#$%^&+=]').hasMatch(password))
      missing.add('• A special character (-_@#\$%^&+=)');

    if (missing.isEmpty) return null;
    return 'Password must contain:\n${missing.join('\n')}';
  }

  // 🔹 Name validation (letters + numbers allowed, but not only numbers)
  bool isValidName(String name) {
    final regex = RegExp(r'^(?!\d+$)[a-zA-Z0-9 ]+$');
    return regex.hasMatch(name.trim());
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 🔹 Show Error Dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 10),
            Text(
              "Error",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "OK",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.woodGradient,
          ),
        ),
        child: SafeArea(
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
                      "Create Account",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      "Join the chess community today!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),

                    const SizedBox(height: 40),

                    if (true) ...[
                      // ================= NAME =================
                      _buildLabel("NAME"),
                      const SizedBox(height: 4),
                      TextFormField(
                        style: const TextStyle(color: Colors.white),
                        onChanged: (value) => name = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Enter name";
                          }
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
                        style: const TextStyle(color: Colors.white),
                        onChanged: (value) => email = value.trim(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Enter email";
                          }
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
                        style: const TextStyle(color: Colors.white),
                        obscureText: !showPassword,
                        onChanged: (value) => password = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter password';
                          }
                          return getPasswordError(value);
                        },
                        decoration: _inputDecoration("Enter password").copyWith(
                          errorMaxLines: 10,
                          suffixIcon: IconButton(
                            icon: Icon(
                              showPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white38,
                            ),
                            onPressed: () =>
                                setState(() => showPassword = !showPassword),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ================= CONFIRM PASSWORD =================
                      _buildLabel("CONFIRM PASSWORD"),
                      const SizedBox(height: 4),
                      TextFormField(
                        style: const TextStyle(color: Colors.white),
                        obscureText: !showConfirmPassword,
                        onChanged: (value) => confirmPassword = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Confirm password";
                          }
                          if (value != password) {
                            return "Passwords do not match";
                          }
                          return null;
                        },
                        decoration: _inputDecoration("Confirm password")
                            .copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  showConfirmPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Colors.white38,
                                ),
                                onPressed: () => setState(
                                  () => showConfirmPassword =
                                      !showConfirmPassword,
                                ),
                              ),
                            ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    // ================= PRIMARY BUTTON =================
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 5,
                        ),
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() => loader = true);

                            final result = await ApiService.signup(
                              name!,
                              email!,
                              password!,
                            );
                            if (context.mounted) {
                              setState(() => loader = false);
                              if (result['success']) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Account created successfully! Please login.',
                                    ),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                                RouteGenerator.navigateToPageWithoutStack(
                                  context,
                                  Routes.loginRoute,
                                );
                              } else {
                                _showErrorDialog(result['error']);
                              }
                            }
                          }
                        },
                        child: loader
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                "Sign Up",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ================= NAVIGATION LINK =================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Already have an account? ",
                          style: TextStyle(color: Colors.white70),
                        ),
                        GestureDetector(
                          onTap: () {
                            RouteGenerator.navigateToPage(
                              context,
                              Routes.loginRoute,
                            );
                          },
                          child: const Text(
                            "Login",
                            style: TextStyle(
                              color: AppColors.secondaryColor,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.secondaryColor,
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
      ),
    );
  }

  // 🔹 Reusable label widget
  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: AppColors.textSecondary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  // 🔹 Reusable input decoration
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: AppColors.secondaryColor),
      ),
    );
  }
}
