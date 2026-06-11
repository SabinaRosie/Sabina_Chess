import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/services/foreground_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _didRedirectToSettings = false;

  bool _allowCalls = true;
  bool _allowMessages = true;
  bool _allowInvitations = true;
  bool _allowSticky = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _didRedirectToSettings) {
      _didRedirectToSettings = false;
      _showSavedSnackBar();
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getNotificationSettings();
    if (result['success'] && mounted) {
      final data = result['data'];
      setState(() {
        _allowCalls = data['allow_calls'] ?? true;
        _allowMessages = data['allow_messages'] ?? true;
        _allowInvitations = data['allow_invitations'] ?? true;
        _allowSticky = data['allow_sticky'] ?? true;
        _isLoading = false;
      });

      final hasPermission = await Permission.notification.isGranted;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? '';
      
      if (hasPermission && username.isNotEmpty) {
        final syncKey = 'has_initially_synced_notifications_$username';
        final hasSynced = prefs.getBool(syncKey) ?? false;
        
        if (!hasSynced) {
          final updateResult = await ApiService.updateNotificationSettings(
            allowCalls: true,
            allowMessages: true,
            allowInvitations: true,
            allowSticky: true,
          );
          if (updateResult['success'] && mounted) {
            setState(() {
              _allowCalls = true;
              _allowMessages = true;
              _allowInvitations = true;
              _allowSticky = true;
            });
            await prefs.setBool(syncKey, true);
            await prefs.setBool('allow_sticky', true);
            await ChessForegroundService.startService();
          }
        } else {
          await prefs.setBool('allow_sticky', _allowSticky);
        }
      } else {
        await prefs.setBool('allow_sticky', _allowSticky);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _showSavedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.secondaryColor.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Settings saved successfully!',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final result = await ApiService.updateNotificationSettings(
      allowCalls: _allowCalls,
      allowMessages: _allowMessages,
      allowInvitations: _allowInvitations,
      allowSticky: _allowSticky,
    );
    setState(() => _isSaving = false);

    if (!mounted) return;

    if (result['success']) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allow_sticky', _allowSticky);

      if (_allowSticky) {
        await ChessForegroundService.startService();
      } else {
        await ChessForegroundService.stopService();
      }

      _showSavedSnackBar();

      final allOff = !_allowCalls && !_allowMessages && !_allowInvitations && !_allowSticky;
      final allOn = _allowCalls && _allowMessages && _allowInvitations && _allowSticky;
      if (allOff || allOn) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppColors.secondaryColor.withOpacity(0.3)),
            ),
            title: const Row(
              children: [
                Icon(Icons.settings_suggest_rounded, color: AppColors.secondaryColor, size: 28),
                SizedBox(width: 10),
                Text(
                  'Device Settings',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              allOff
                  ? 'You have disabled all in-app notifications. Would you also like to open your device settings to disable notifications completely for this app?'
                  : 'You have enabled all in-app notifications. Would you like to check your device settings to ensure system notifications are turned on for this app?',
              style: const TextStyle(color: AppColors.textSecondary),
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
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: AppColors.backgroundColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  _didRedirectToSettings = true;
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                result['error'] ?? 'Failed to save settings.',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
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
        child: SafeArea(
          child: Column(
            children: [
              // ── AppBar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notification Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Choose what you want to be notified about',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Content ──
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.secondaryColor),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel('📞  Calls'),
                            const SizedBox(height: 10),
                            _notifTile(
                              icon: Icons.call_rounded,
                              iconColor: const Color(0xFF4caf50),
                              title: 'Incoming Calls',
                              subtitle:
                                  'Receive alerts when someone calls you',
                              value: _allowCalls,
                              onChanged: (v) =>
                                  setState(() => _allowCalls = v),
                            ),
                            const SizedBox(height: 24),
                            _sectionLabel('💬  Messages'),
                            const SizedBox(height: 10),
                            _notifTile(
                              icon: Icons.chat_bubble_rounded,
                              iconColor: const Color(0xFF5b9cff),
                              title: 'Chat Messages',
                              subtitle:
                                  'Receive alerts for new messages from friends',
                              value: _allowMessages,
                              onChanged: (v) =>
                                  setState(() => _allowMessages = v),
                            ),
                            const SizedBox(height: 24),
                            _sectionLabel('♟️  Game'),
                            const SizedBox(height: 10),
                            _notifTile(
                              icon: Icons.sports_esports_rounded,
                              iconColor: AppColors.secondaryColor,
                              title: 'Game Invitations',
                              subtitle:
                                  'Get notified when someone challenges you',
                              value: _allowInvitations,
                              onChanged: (v) =>
                                  setState(() => _allowInvitations = v),
                            ),
                            const SizedBox(height: 24),
                            _sectionLabel('📌  Advanced'),
                            const SizedBox(height: 10),
                            _notifTile(
                              icon: Icons.push_pin_rounded,
                              iconColor: const Color(0xFFb39ddb),
                              title: 'Sticky / High-Priority Alerts',
                              subtitle:
                                  'Allow pop-up banners that appear over other apps',
                              value: _allowSticky,
                              onChanged: (v) =>
                                  setState(() => _allowSticky = v),
                            ),
                            const SizedBox(height: 16),
                            // Explanation card
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.secondaryColor.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      color: AppColors.secondaryColor, size: 18),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'When a notification type is turned off, it is recorded as "Blocked" in the server logs. This helps us understand your preferences.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveSettings,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(
                                  _isSaving ? 'Saving...' : 'Save Settings',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondaryColor,
                                  foregroundColor: AppColors.backgroundColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.secondaryColor,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _notifTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: value
            ? Colors.white.withOpacity(0.09)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? iconColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(value ? 0.2 : 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: value ? iconColor : Colors.white24, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value ? Colors.white : Colors.white54,
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
            activeThumbColor: iconColor,
            activeTrackColor: iconColor.withOpacity(0.3),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}
