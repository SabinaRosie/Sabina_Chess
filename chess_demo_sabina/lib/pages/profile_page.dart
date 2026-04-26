import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../utils/route_const.dart';
import '../utils/route_generator.dart';
import '../utils/color_utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  String? username;
  String? email;
  bool isLoading = true;
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  // Settings state
  bool _biometricEnabled = false;
  bool _soundEnabled = true;
  bool _notificationsEnabled = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchProfile();
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');

    if (token != null) {
      final result = await ApiService.getProfile(token);
      if (result['success']) {
        setState(() {
          username = result['data']['username'];
          email = result['data']['email'];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } else {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedBioUser = await secureStorage.read(key: 'bio_username');
    setState(() {
      _biometricEnabled = storedBioUser != null;
      _soundEnabled = prefs.getBool('soundEnabled') ?? true;
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('accessToken');
    final refreshToken = prefs.getString('refreshToken');

    if (accessToken != null && refreshToken != null) {
      await ApiService.logout(accessToken, refreshToken);
    }

    // 🔹 Clear session tokens and remember-me flag
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    await prefs.remove('isRemembered');

    if (mounted) {
      RouteGenerator.navigateToPageWithoutStack(context, Routes.loginRoute);
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
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
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.secondaryColor,
                ),
              )
            : SafeArea(
                child: Column(
                  children: [
                    // ── Header ──
                    _buildHeader(),

                    // ── Tab Bar ──
                    _buildTabBar(),

                    // ── Tab Views ──
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPersonalInfoTab(),
                          _buildSettingsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Center(
        child: Column(
          children: [
            // Avatar
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primaryColor, AppColors.secondaryColor],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFe2b96f).withOpacity(0.4),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '♔',
                  style: TextStyle(fontSize: 42, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Name
            Text(
              username ?? 'Player',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            // email
            Text(
              email ?? '—',
              style: const TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // TAB BAR
  // ─────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.secondaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: AppColors.backgroundColor,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Personal Info'),
          Tab(text: 'Settings'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // PERSONAL INFO TAB
  // ─────────────────────────────────────────────────────
  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _sectionTitle('Account Details'),
          const SizedBox(height: 14),
          _infoTile(Icons.person_outline_rounded, 'Username', username ?? '—'),
          const SizedBox(height: 12),
          _infoTile(Icons.email_outlined, 'Email', email ?? '—'),
          const SizedBox(height: 28),
          _sectionTitle('Game Stats'),
          const SizedBox(height: 14),
          Row(
            children: [
              _gameStatCard('🏆', 'Wins', '0'),
              const SizedBox(width: 12),
              _gameStatCard('💀', 'Losses', '0'),
              const SizedBox(width: 12),
              _gameStatCard('🤝', 'Draws', '0'),
            ],
          ),
          const SizedBox(height: 28),
          // Logout button at the bottom of personal info tab
          _logoutButton(),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFe2b96f), size: 22),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gameStatCard(String emoji, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
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
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // SETTINGS TAB
  // ─────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _sectionTitle('Security'),
          const SizedBox(height: 14),
          _settingsTile(
            icon: Icons.fingerprint_rounded,
            title: 'Fingerprint Login',
            subtitle: 'Use biometrics to sign in quickly',
            value: _biometricEnabled,
            onChanged: (val) async {
              if (val) {
                // Enabling fingerprint
                try {
                  bool canCheckBiometrics = await auth.canCheckBiometrics;
                  bool isDeviceSupported = await auth.isDeviceSupported();

                  if (!canCheckBiometrics || !isDeviceSupported) {
                    if (mounted) {
                      _showErrorDialog(
                        context,
                        "Biometrics not supported on this device.",
                      );
                    }
                    return;
                  }

                  // 1. Mandatory biometric scan before enabling
                  bool didAuthenticate = await auth.authenticate(
                    localizedReason:
                        'Please authenticate to enable fingerprint login',
                    options: const AuthenticationOptions(
                      biometricOnly: true,
                      stickyAuth: true,
                    ),
                  );

                  if (didAuthenticate) {
                    final prefs = await SharedPreferences.getInstance();
                    final access = prefs.getString('accessToken');
                    final refresh = prefs.getString('refreshToken');

                    if (access != null && refresh != null) {
                      // 2. Store in SharedPreferences
                      await prefs.setString('bio_access_token', access);
                      await prefs.setString('bio_refresh_token', refresh);

                      setState(() => _biometricEnabled = true);
                      await _saveSetting('isBiometricEnabled', true);
                      if (mounted) {
                        _showMessageDialog(
                          context,
                          "Fingerprint Enabled",
                          "You can now use your fingerprint for quick login!",
                        );
                      }
                    } else {
                      _showErrorDialog(
                        context,
                        "Session error. Please logout and login again.",
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    _showErrorDialog(context, "Biometric Error: $e");
                  }
                }
              } else {
                // Disabling fingerprint — clear stored credentials
                await secureStorage.delete(key: 'bio_username');
                await secureStorage.delete(key: 'bio_password');
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('bio_access_token');
                await prefs.remove('bio_refresh_token');
                await prefs.remove('isBiometricEnabled');

                setState(() => _biometricEnabled = false);
                if (mounted) {
                  _showMessageDialog(
                    context,
                    "Fingerprint Disabled",
                    "Biometric login has been turned off.",
                  );
                }
              }
            },
          ),
          const SizedBox(height: 28),
          _sectionTitle('Preferences'),
          const SizedBox(height: 14),
          _settingsTile(
            icon: Icons.volume_up_rounded,
            title: 'Sound Effects',
            subtitle: 'Play sounds during the game',
            value: _soundEnabled,
            onChanged: (val) async {
              setState(() => _soundEnabled = val);
              await _saveSetting('soundEnabled', val);
            },
          ),
          const SizedBox(height: 12),
          _settingsTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Receive game updates and alerts',
            value: _notificationsEnabled,
            onChanged: (val) async {
              setState(() => _notificationsEnabled = val);
              await _saveSetting('notificationsEnabled', val);
            },
          ),
          const SizedBox(height: 28),
          _sectionTitle('Account'),
          const SizedBox(height: 14),
          _actionTile(
            icon: Icons.lock_reset_rounded,
            title: 'Change Password',
            subtitle: 'Update your account password',
            iconColor: const Color(0xFF5b9cff),
            onTap: () {
              _showMessageDialog(
                context,
                "Coming Soon",
                "Change Password feature will be available in the next update!",
              );
            },
          ),
          const SizedBox(height: 12),
          _actionTile(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: 'Sign out of your account',
            iconColor: Colors.redAccent,
            onTap: _showLogoutDialog,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.secondaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.secondaryColor,
            activeTrackColor: AppColors.secondaryColor.withOpacity(0.3),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.secondaryColor,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Logout', style: TextStyle(fontSize: 17)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent.withOpacity(0.85),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 4,
        ),
      ),
    );
  }

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
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
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
}
