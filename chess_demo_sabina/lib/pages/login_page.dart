import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import '../services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  String? username, password;
  bool showPassword = false;
  bool rememberMe = false;
  bool loader = false;

  // 🔹 Username validation
  bool isValidUsername(String username) {
    return username.trim().isNotEmpty;
  }

  // 🔹 Password validation (basic for now)
  bool isValidPassword(String password) {
    return password.length >= 6;
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),

                  // 🔹 Welcome Text
                  const Center(
                    child: Text(
                      "Welcome",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),

                  // ================= USERNAME =================
                  _buildLabel("USERNAME"),
                  const SizedBox(height: 4),

                  TextFormField(
                    decoration: InputDecoration(
                      hintText: "Enter username",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onChanged: (value) => username = value.trim(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Enter username";
                      }
                      if (!isValidUsername(value)) {
                        return "Enter valid username";
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  // ================= PASSWORD =================
                  _buildLabel("PASSWORD"),
                  const SizedBox(height: 4),

                  TextFormField(
                    obscureText: !showPassword,
                    decoration: InputDecoration(
                      hintText: "Enter password",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
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
                    onChanged: (value) => password = value,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Enter password";
                      }
                      if (!isValidPassword(value)) {
                        return "Password must be at least 6 characters";
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 10),

                  // 🔹 Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        RouteGenerator.navigateToPage(
                          context,
                          Routes.forgotPasswordRoute,
                        );
                      },
                      child: const Text("Forgot Password?"),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= LOGIN BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            loader = true;
                          });

                          final result = await ApiService.login(
                            username!,
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

                              // 🔹 Check if biometric is enabled; if not, ask to enable
                              bool isBiometricEnabled =
                                  prefs.getBool('isBiometricEnabled') ?? false;

                              if (!isBiometricEnabled && context.mounted) {
                                _showEnableBiometricDialog(context, prefs);
                              } else {
                                RouteGenerator.navigateToPageWithoutStack(
                                  context,
                                  Routes.homeRoute,
                                );
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Login successful"),
                                ),
                              );
                            } else {
                              if (context.mounted) {
                                _showErrorDialog(context, result['error']);
                              }
                            }
                          }
                        }
                      },
                      child: loader
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("Login", style: TextStyle(fontSize: 18)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= FINGERPRINT LOGIN =================
                  IconButton(
                    icon: const Icon(
                      Icons.fingerprint,
                      size: 50,
                      color: Colors.blueAccent,
                    ),
                    onPressed: () async {
                      final localAuth = LocalAuthentication();

                      try {
                        bool canCheckBiometrics =
                            await localAuth.canCheckBiometrics;
                        bool isDeviceSupported = await localAuth
                            .isDeviceSupported();

                        if (!canCheckBiometrics || !isDeviceSupported) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Biometrics not supported on this device",
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        final prefs = await SharedPreferences.getInstance();
                        bool isBiometricEnabled =
                            prefs.getBool('isBiometricEnabled') ?? false;

                        if (!isBiometricEnabled) {
                          if (context.mounted) {
                            _showBiometricNotEnabledDialog(context);
                          }
                          return;
                        }

                        bool didAuthenticate = await localAuth.authenticate(
                          localizedReason: 'Please authenticate to login',
                          options: const AuthenticationOptions(
                            biometricOnly: true,
                            stickyAuth: true,
                          ),
                        );

                        if (didAuthenticate && context.mounted) {
                          final token = prefs.getString('accessToken');
                          if (token != null && token.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Biometric Login successful"),
                              ),
                            );
                            RouteGenerator.navigateToPageWithoutStack(
                              context,
                              Routes.homeRoute,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Session expired. Please login manually.",
                                ),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text("Error: $e")));
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  // ================= SIGNUP LINK =================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? "),
                      GestureDetector(
                        onTap: () {
                          RouteGenerator.navigateToPage(
                            context,
                            Routes.signupRoute,
                          );
                        },
                        child: const Text(
                          "Sign up",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 Dialog to enable biometrics
  void _showEnableBiometricDialog(
    BuildContext context,
    SharedPreferences prefs,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enable Fingerprint?"),
        content: const Text(
          "Would you like to use your fingerprint for faster login next time?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              RouteGenerator.navigateToPageWithoutStack(
                context,
                Routes.homeRoute,
              );
            },
            child: const Text("Maybe Later"),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setBool('isBiometricEnabled', true);
              if (context.mounted) {
                Navigator.pop(context);
                RouteGenerator.navigateToPageWithoutStack(
                  context,
                  Routes.homeRoute,
                );
              }
            },
            child: const Text("Enable"),
          ),
        ],
      ),
    );
  }

  // 🔹 Dialog for biometric not enabled
  void _showBiometricNotEnabledDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text("Fingerprint Login"),
          ],
        ),
        content: const Text(
          "Fingerprint login is not enabled yet. Please login manually with your username and password first.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🔹 Dialog for errors
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Login Failed"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Try Again", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
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
