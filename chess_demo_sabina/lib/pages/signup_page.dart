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
                  const Text(
                    "Create Account",
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 50),

                  // ================= NAME =================
                  _buildLabel("NAME"),
                  const SizedBox(height: 4),
                  TextFormField(
                    onChanged: (value) => name = value,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Enter name";
                      }
                      if (!isValidName(value)) {
                        return "Invalid name";
                      }
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
                      if (value == null || value.isEmpty) {
                        return "Enter email";
                      }
                      if (!isValidEmail(value)) {
                        return "Enter valid email";
                      }
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
                      if (value == null || value.isEmpty) {
                        return "Enter password";
                      }
                      if (!isValidPassword(value)) {
                        return "Weak password (min 6 chars, A-Z, a-z, 0-9, special)";
                      }
                      return null;
                    },
                    decoration: _inputDecoration("Enter password").copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            showPassword = !showPassword;
                          });
                        },
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
                      if (value == null || value.isEmpty) {
                        return "Confirm password";
                      }
                      if (value != password) {
                        return "Passwords do not match";
                      }
                      return null;
                    },
                    decoration: _inputDecoration("Confirm password").copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          showConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            showConfirmPassword = !showConfirmPassword;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ================= SIGNUP BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            loader = true;
                          });

                          final result = await ApiService.signup(
                            name!,
                            email!,
                            password!,
                          );

                          if (context.mounted) {
                            setState(() {
                              loader = false;
                            });

                            if (result['success']) {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                'accessToken',
                                result['data']['access'],
                              );
                              await prefs.setString(
                                'refreshToken',
                                result['data']['refresh'],
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Signup successful"),
                                ),
                              );

                              RouteGenerator.navigateToPageWithoutStack(
                                context,
                                Routes.homeRoute,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result['error'])),
                              );
                            }
                          }
                        }
                      },
                      child: loader
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Sign Up",
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= LOGIN LINK =================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Already have an account? "),
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
