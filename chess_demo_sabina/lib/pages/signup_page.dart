import 'package:flutter/material.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  String? name, email, password;
  bool showPassword = false;

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
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
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
                        return "Weak password";
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

                  const SizedBox(height: 30),

                  // ================= SIGNUP BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Signup successful"),
                            ),
                          );

                          RouteGenerator.navigateToPage(
                            context,
                            Routes.loginRoute,
                          );
                        }
                      },
                      child: const Text(
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  // 🔹 Reusable input decoration
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
      ),
    );
  }
}
