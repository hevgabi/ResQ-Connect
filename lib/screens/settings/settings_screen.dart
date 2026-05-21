import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return StreamBuilder<UserModel?>(
      stream: FirestoreService.instance.userStream(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            title: const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            elevation: 0,
          ),
          body: ListView(
            children: [
              // ── Profile Header Card ──────────────────────────────────────
              _ProfileHeaderTile(user: user),

              const SizedBox(height: 8),

              // ── Account Section ──────────────────────────────────────────
              _SectionHeader(title: 'Account'),
              _SettingsTile(
                icon: Icons.person_outline,
                iconColor: AppTheme.primaryBlue,
                title: 'Personal Information',
                subtitle: 'Name, phone number',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsTile(
                icon: Icons.email_outlined,
                iconColor: AppTheme.primaryBlue,
                title: 'Email Address',
                subtitle: user?.email ?? '—',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                iconColor: AppTheme.primaryBlue,
                title: 'Change Password',
                subtitle: 'Update your password',
                onTap: () => _showChangePasswordDialog(context),
              ),

              const SizedBox(height: 8),

              // ── Notifications Section ────────────────────────────────────
              _SectionHeader(title: 'Notifications'),
              _SettingsSwitchTile(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFFE65100),
                title: 'Push Notifications',
                subtitle: 'Alerts, updates, and messages',
                initialValue: true,
              ),
              _SettingsSwitchTile(
                icon: Icons.campaign_outlined,
                iconColor: const Color(0xFFE65100),
                title: 'Emergency Alerts',
                subtitle: 'SOS and critical notifications',
                initialValue: true,
              ),

              const SizedBox(height: 8),

              // ── Privacy & Security Section ───────────────────────────────
              _SectionHeader(title: 'Privacy & Security'),
              _SettingsTile(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF1B5E20),
                title: 'Privacy Settings',
                subtitle: 'Manage your data and visibility',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsTile(
                icon: Icons.location_on_outlined,
                iconColor: const Color(0xFF1B5E20),
                title: 'Location Access',
                subtitle: 'Control when the app uses your location',
                onTap: () => _showComingSoon(context),
              ),

              const SizedBox(height: 8),

              // ── Support Section ──────────────────────────────────────────
              _SectionHeader(title: 'Help & Support'),
              _SettingsTile(
                icon: Icons.help_outline,
                iconColor: AppTheme.textSecondary,
                title: 'Help Center',
                subtitle: 'FAQs and support articles',
                onTap: () => _showComingSoon(context),
              ),
              _SettingsTile(
                icon: Icons.info_outline,
                iconColor: AppTheme.textSecondary,
                title: 'About ResQConnect',
                subtitle: 'Version, terms, and licenses',
                onTap: () => _showAboutDialog(context),
              ),

              const SizedBox(height: 8),

              // ── Logout ───────────────────────────────────────────────────
              _SectionHeader(title: 'Account Actions'),
              _SettingsTile(
                icon: Icons.logout,
                iconColor: AppTheme.dangerRed,
                title: 'Log Out',
                subtitle: 'Sign out of your account',
                titleColor: AppTheme.dangerRed,
                showChevron: false,
                onTap: () => _showLogoutDialog(context),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  void _showLogoutDialog(BuildContext context) {
    // Capture BOTH the provider and navigator before the dialog opens.
    // After Navigator.pop(ctx), the dialog's ctx is gone — but these refs survive.
    final authProvider = context.read<app_auth.AuthProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(90, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await authProvider.logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    bool sent = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Change Password',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: sent
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: AppTheme.successGreen,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Password reset email sent! Check your inbox.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "We'll send a password reset link to your email address.",
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController
                        ..text = FirebaseAuth.instance.currentUser?.email ?? '',
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
          actions: sent
              ? [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await FirebaseAuth.instance.sendPasswordResetEmail(
                          email: emailController.text.trim(),
                        );
                        setState(() => sent = true);
                      } catch (e) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    child: const Text('Send Link'),
                  ),
                ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ResQConnect',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.emergency,
        color: AppTheme.dangerRed,
        size: 40,
      ),
      children: const [
        Text(
          'ResQConnect is a disaster response and emergency management platform connecting citizens, rescuers, and coordinators.',
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _ProfileHeaderTile extends StatelessWidget {
  final UserModel? user;
  const _ProfileHeaderTile({required this.user});

  String _initials() {
    final f = user?.firstName ?? '';
    final l = user?.lastName ?? '';
    return ((f.isNotEmpty ? f[0] : '') + (l.isNotEmpty ? l[0] : ''))
        .toUpperCase();
  }

  Color _roleColor() {
    switch (user?.role.toLowerCase()) {
      case 'admin':
        return const Color(0xFF0D47A1);
      case 'rescuer':
        return const Color(0xFF1FAA59);
      case 'moderator':
        return const Color(0xFF6A1B9A);
      default:
        return AppTheme.primaryBlue;
    }
  }

  String _roleLabel() {
    final r = user?.role ?? 'citizen';
    return r[0].toUpperCase() + r.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 34,
            backgroundColor: _roleColor().withValues(alpha: 0.15),
            backgroundImage: user?.photoUrl != null
                ? CachedNetworkImageProvider(user!.photoUrl!)
                : null,
            child: user?.photoUrl == null
                ? Text(
                    _initials().isNotEmpty ? _initials() : '?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _roleColor(),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          // Name + email + role badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? user?.name ?? 'User',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '—',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _roleColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _roleLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _roleColor(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final bool showChevron;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: titleColor ?? AppTheme.textPrimary,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            trailing: showChevron
                ? const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                    size: 20,
                  )
                : null,
            onTap: onTap,
          ),
          const Divider(height: 1, indent: 68),
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool initialValue;

  const _SettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.initialValue,
  });

  @override
  State<_SettingsSwitchTile> createState() => _SettingsSwitchTileState();
}

class _SettingsSwitchTileState extends State<_SettingsSwitchTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: widget.iconColor, size: 20),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            subtitle: Text(
              widget.subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            value: _value,
            activeColor: AppTheme.primaryBlue,
            onChanged: (v) => setState(() => _value = v),
          ),
          const Divider(height: 1, indent: 68),
        ],
      ),
    );
  }
}
