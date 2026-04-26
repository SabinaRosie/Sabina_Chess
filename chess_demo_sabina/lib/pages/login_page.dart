import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import '../services/api_service.dart';
import '../utils/color_utils.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String? username, password;
  bool showPassword = false;
  bool loader = false;

  final localAuth = LocalAuthentication();
  final secureStorage = const FlutterSecureStorage();
  bool isBiometricAvailable = false;
  bool isBiometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
    _checkExistingSession();
  }

  Future<void> _checkBiometricSupport() async {
    bool canCheck = await localAuth.canCheckBiometrics;
    bool isSupported = await localAuth.isDeviceSupported();
    setState(() {
      isBiometricAvailable = canCheck && isSupported;
    });
  }

  Future<void> _checkExistingSession() async {
    // Check if biometric credentials are actually stored (not just the flag)
    final storedBioUser = await secureStorage.read(key: 'bio_username');
    setState(() {
      isBiometricEnabled = storedBioUser != null;
    });
  }

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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),

                    // 🔹 Welcome Text
                    const Center(
                      child: Text(
                        "Welcome",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 50),

                    // ================= USERNAME =================
                    _buildLabel("USERNAME"),
                    const SizedBox(height: 4),

                    TextFormField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter username",
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: AppColors.secondaryColor,
                          ),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter password",
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: AppColors.secondaryColor,
                          ),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white38,
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
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ================= LOGIN BUTTON =================
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() => loader = true);

                            final result = await ApiService.login(
                              username!,
                              password!,
                            );

                            if (context.mounted) {
                              setState(() => loader = false);

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

                                // 🔹 Also save credentials if rememberMe or for Biometric setup later
                                await prefs.setString(
                                  'last_username',
                                  username!,
                                );

                                // 🔹 Check if biometric setup is needed for THIS user
                                final storedBioUser = await secureStorage.read(key: 'bio_username');
                                final biometricSetForThisUser = storedBioUser == username;

                                if (!biometricSetForThisUser &&
                                    isBiometricAvailable &&
                                    context.mounted) {
                                  _showEnableBiometricDialog(
                                    context,
                                    result['data']['access'],
                                    result['data']['refresh'],
                                    username!,
                                    password!,
                                  );
                                } else {
                                  RouteGenerator.navigateToPageWithoutStack(
                                    context,
                                    Routes.homeRoute,
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  _showErrorDialog(context, result['error']);
                                }
                              }
                            }
                          }
                        },
                        child: loader
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                "Login",
                                style: TextStyle(fontSize: 18),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ================= FINGERPRINT LOGIN =================
                    if (isBiometricAvailable)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isBiometricEnabled
                                  ? AppColors.secondaryColor
                                  : Colors.white24,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            foregroundColor: isBiometricEnabled
                                ? AppColors.secondaryColor
                                : Colors.white54,
                          ),
                          icon: const Icon(Icons.fingerprint, size: 28),
                          label: const Text(
                            "Login with Fingerprint",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            if (isBiometricEnabled) {
                              _loginWithBiometric();
                            } else {
                              _showBiometricNotEnabledDialog(context);
                            }
                          },
                        ),
                      ),

                    if (isBiometricEnabled)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          "Biometric login is active",
                          style: TextStyle(color: Colors.green, fontSize: 13),
                        ),
                      ),

                    const SizedBox(height: 30),

                    // ================= SIGNUP LINK =================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Colors.white70),
                        ),
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
                              color: AppColors.secondaryColor,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.secondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 Biometric Login Core Logic
  Future<void> _loginWithBiometric() async {
    try {
      bool didAuth = await localAuth.authenticate(
        localizedReason: 'Scan fingerprint to access your account',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuth && context.mounted) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('bio_access_token');
        final refreshToken = prefs.getString('bio_refresh_token');

        // 1. Try with existing access token first
        if (accessToken != null) {
          final result = await ApiService.getProfile(accessToken);
          if (result['success'] && context.mounted) {
            await prefs.setString('accessToken', accessToken);
            RouteGenerator.navigateToPageWithoutStack(
              context,
              Routes.homeRoute,
            );
            return;
          }
        }

        // 2. Access token expired — try refreshing it
        if (refreshToken != null) {
          final refreshResult = await ApiService.refreshToken(refreshToken);
          if (refreshResult['success'] && context.mounted) {
            final newAccess = refreshResult['data']['access'];
            await prefs.setString('bio_access_token', newAccess);
            await prefs.setString('accessToken', newAccess);
            RouteGenerator.navigateToPageWithoutStack(
              context,
              Routes.homeRoute,
            );
            return;
          }
        }

        // 3. Both tokens expired — use stored credentials for fresh login
        final storedUsername = await secureStorage.read(key: 'bio_username');
        final storedPassword = await secureStorage.read(key: 'bio_password');

        if (storedUsername != null && storedPassword != null) {
          final loginResult = await ApiService.login(storedUsername, storedPassword);
          if (loginResult['success'] && context.mounted) {
            final newAccess = loginResult['data']['access'];
            final newRefresh = loginResult['data']['refresh'];
            // Update stored tokens for next time
            await prefs.setString('bio_access_token', newAccess);
            await prefs.setString('bio_refresh_token', newRefresh);
            await prefs.setString('accessToken', newAccess);
            await prefs.setString('refreshToken', newRefresh);
            RouteGenerator.navigateToPageWithoutStack(
              context,
              Routes.homeRoute,
            );
            return;
          }
        }

        // 4. Nothing worked — credentials invalid (e.g. password changed)
        if (context.mounted) {
          _showMessageDialog(
            context,
            "Login Failed",
            "Could not authenticate. Please login with your password to re-enable fingerprint.",
          );
        }
      }
    } catch (e) {
      debugPrint("Biometric Auth error: $e");
    }
  }

  // 🔹 Dialog for biometric not enabled
  void _showBiometricNotEnabledDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.fingerprint, color: AppColors.secondaryColor),
            SizedBox(width: 10),
            Text("Enable Fingerprint", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "To use fingerprint login, please log in manually with your username and password once first. \n\nAfter logging in, you'll be asked if you want to enable it!",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Got it",
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 Dialog to enable biometrics
  void _showEnableBiometricDialog(
    BuildContext context,
    String accessToken,
    String refreshToken,
    String loginUsername,
    String loginPassword,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.3)),
        ),
        title: const Text("Enable Fingerprint?", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          "Use your fingerprint for secure and fast login next time.",
          style: TextStyle(color: AppColors.textSecondary),
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
            child: const Text("Skip", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: AppColors.backgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              // 1. Mandatory biometric scan before enabling
              bool didAuth = await localAuth.authenticate(
                localizedReason: 'Scan fingerprint to enable biometric login',
                options: const AuthenticationOptions(
                  stickyAuth: true,
                  biometricOnly: true,
                ),
              );

              if (didAuth && context.mounted) {
                // 2. Store tokens in SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('bio_access_token', accessToken);
                await prefs.setString('bio_refresh_token', refreshToken);
                await prefs.setBool('isBiometricEnabled', true);

                // 3. Store credentials securely for persistent biometric login
                await secureStorage.write(key: 'bio_username', value: loginUsername);
                await secureStorage.write(key: 'bio_password', value: loginPassword);

                if (context.mounted) {
                  Navigator.pop(context);
                  _showMessageDialog(
                    context,
                    "Setup Successful",
                    "Fingerprint login has been enabled! You can now use it for your next login.",
                  );
                  RouteGenerator.navigateToPageWithoutStack(
                    context,
                    Routes.homeRoute,
                  );
                }
              }
            },
            child: const Text("Enable & Verify"),
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
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Error", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 Dialog for general messages
  void _showMessageDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.secondaryColor),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondaryColor),
            ),
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
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: AppColors.textSecondary,
        letterSpacing: 1.1,
      ),
    ),
  );
}
