import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../entry/login_screen.dart';
import '../admin/admin_rescuers_screen.dart';
import '../admin/admin_evac_centers_screen.dart';
import '../admin/admin_incidents_screen.dart';
import '../admin/admin_approvals_screen.dart';
import '../admin/admin_broadcast_screen.dart';
import '../admin/admin_reports_screen.dart';
import '../citizen/help_support_screen.dart';
import '../citizen/personal_information_screen.dart';
import '../citizen/privacy_settings_screen.dart';

// =============================================================================
// ROLE ENUM
// =============================================================================

enum HamburgerRole { citizen, rescuer, moderator, admin }

// =============================================================================
// PUBLIC HELPER — call this from any screen
// =============================================================================

void showHamburgerMenu(
    BuildContext context, {
      HamburgerRole role = HamburgerRole.citizen,
    }) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => HamburgerMenuScreen(role: role)),
  );
}

// =============================================================================
// MAIN SCREEN
// =============================================================================

class HamburgerMenuScreen extends StatefulWidget {
  final HamburgerRole role;
  const HamburgerMenuScreen({super.key, required this.role});

  @override
  State<HamburgerMenuScreen> createState() => _HamburgerMenuScreenState();
}

class _HamburgerMenuScreenState extends State<HamburgerMenuScreen> {
  StreamSubscription<UserModel?>? _userSub;
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userSub = FirestoreService.instance
          .userStream(uid)
          .listen(
            (user) {
          if (mounted) setState(() => _user = user);
        },
        onError: (e) {
          debugPrint(
            'HamburgerMenuScreen userStream error (post-logout): $e',
          );
          _userSub?.cancel();
          if (mounted) Navigator.of(context).pop();
        },
      );
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  Color get _roleAccent {
    switch (widget.role) {
      case HamburgerRole.rescuer:
        return const Color(0xFF1FAA59);
      case HamburgerRole.moderator:
        return const Color(0xFF6A1B9A);
      case HamburgerRole.admin:
        return const Color(0xFF0D47A1);
      case HamburgerRole.citizen:
      default:
        return AppTheme.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _roleAccent,
        foregroundColor: Colors.white,
        title: const Text(
          'Menu',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // ── Profile Header Card ──────────────────────────────────────────
          _ProfileHeaderTile(user: user),

          const SizedBox(height: 8),

          // ── Admin Navigation Section ─────────────────────────────────────
          if (widget.role == HamburgerRole.admin) ...[
            _SectionHeader(title: 'Admin Navigation'),
            _MenuTile(
              icon: Icons.people_outline,
              iconColor: const Color(0xFF0D47A1),
              title: 'Rescuers',
              subtitle: 'View and manage all rescuers',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminRescuersScreen(),
                ),
              ),
            ),
            _MenuTile(
              icon: Icons.location_city_outlined,
              iconColor: const Color(0xFF0D47A1),
              title: 'Evac Centers',
              subtitle: 'Manage evacuation centers',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminEvacCentersScreen(),
                ),
              ),
            ),
            _MenuTile(
              icon: Icons.warning_amber_outlined,
              iconColor: const Color(0xFF0D47A1),
              title: 'Incidents',
              subtitle: 'View all SOS incidents',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminIncidentsScreen(),
                ),
              ),
            ),
            StreamBuilder<int>(
              stream:
              FirestoreService.instance.pendingApprovalsCountStream(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return _MenuTile(
                  icon: Icons.how_to_reg_outlined,
                  iconColor: const Color(0xFF0D47A1),
                  title: 'Approvals',
                  subtitle: 'Review pending registrations',
                  badge: count > 0 ? '$count pending' : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminApprovalsScreen(),
                    ),
                  ),
                );
              },
            ),
            _MenuTile(
              icon: Icons.campaign_outlined,
              iconColor: const Color(0xFF0D47A1),
              title: 'Broadcast Alert',
              subtitle: 'Send emergency alerts to users',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminBroadcastScreen(),
                ),
              ),
            ),
            _MenuTile(
              icon: Icons.bar_chart_outlined,
              iconColor: const Color(0xFF0D47A1),
              title: 'Reports',
              subtitle: 'Incident & rescuer statistics',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminReportsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Role-specific support section ────────────────────────────────
          if (widget.role == HamburgerRole.citizen) ...[
            _SectionHeader(title: 'Support'),
            _MenuTile(
              icon: Icons.help_outline,
              iconColor: AppTheme.primaryBlue,
              title: 'Help & Support',
              subtitle: 'FAQs and support articles',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (widget.role == HamburgerRole.rescuer) ...[
            _SectionHeader(title: 'Support'),
            _MenuTile(
              icon: Icons.help_outline,
              iconColor: const Color(0xFF1FAA59),
              title: 'Help & Support',
              subtitle: 'FAQs and support articles',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (widget.role == HamburgerRole.moderator) ...[
            _SectionHeader(title: 'Support'),
            _MenuTile(
              icon: Icons.help_outline,
              iconColor: const Color(0xFF6A1B9A),
              title: 'Help & Support',
              subtitle: 'FAQs and support articles',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Account Section ──────────────────────────────────────────────
          _SectionHeader(title: 'Account'),
          _MenuTile(
            icon: Icons.person_outline,
            iconColor: _roleAccent,
            title: 'Personal Information',
            subtitle: 'Name, phone number',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PersonalInformationScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.email_outlined,
            iconColor: _roleAccent,
            title: 'Email Address',
            subtitle: user?.email ?? '—',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email address cannot be changed. Contact support if you need help.'),
                behavior: SnackBarBehavior.floating,
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.lock_outline,
            iconColor: _roleAccent,
            title: 'Change Password',
            subtitle: 'Update your password',
            onTap: () => _showChangePasswordDialog(context),
          ),

          const SizedBox(height: 8),

          // ── Notifications Section ────────────────────────────────────────
          _SectionHeader(title: 'Notifications'),
          _SwitchMenuTile(
            icon: Icons.notifications_outlined,
            iconColor: const Color(0xFFE65100),
            title: 'Push Notifications',
            subtitle: 'Alerts, updates, and messages',
            initialValue: true,
          ),
          _SwitchMenuTile(
            icon: Icons.campaign_outlined,
            iconColor: const Color(0xFFE65100),
            title: 'Emergency Alerts',
            subtitle: 'SOS and critical notifications',
            initialValue: true,
          ),

          const SizedBox(height: 8),

          // ── Privacy & Security Section ───────────────────────────────────
          _SectionHeader(title: 'Privacy & Security'),
          _MenuTile(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF1B5E20),
            title: 'Privacy Settings',
            subtitle: 'Manage your data and visibility',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.location_on_outlined,
            iconColor: const Color(0xFF1B5E20),
            title: 'Location Access',
            subtitle: 'Control when the app uses your location',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Open your device Settings → Apps → ResQConnect → Permissions to manage location access.'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 4),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── About Section ────────────────────────────────────────────────
          _SectionHeader(title: 'About'),
          _MenuTile(
            icon: Icons.info_outline,
            iconColor: AppTheme.textSecondary,
            title: 'About ResQConnect',
            subtitle: 'Version, terms, and licenses',
            onTap: () => _showAboutDialog(context),
          ),

          const SizedBox(height: 8),

          // ── Account Actions ──────────────────────────────────────────────
          _SectionHeader(title: 'Account Actions'),
          _MenuTile(
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
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showLogoutDialog(BuildContext context) {
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
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
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
                  ..text =
                      FirebaseAuth.instance.currentUser?.email ?? '',
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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

// =============================================================================
// SUB-WIDGETS
// =============================================================================

class _ProfileHeaderTile extends StatefulWidget {
  final UserModel? user;
  const _ProfileHeaderTile({required this.user});

  @override
  State<_ProfileHeaderTile> createState() => _ProfileHeaderTileState();
}

class _ProfileHeaderTileState extends State<_ProfileHeaderTile> {
  bool _uploadingPhoto = false;

  String _initials() {
    final f = widget.user?.firstName ?? '';
    final l = widget.user?.lastName ?? '';
    return ((f.isNotEmpty ? f[0] : '') + (l.isNotEmpty ? l[0] : ''))
        .toUpperCase();
  }

  Color _roleColor() {
    switch (widget.user?.role.toLowerCase()) {
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
    final r = widget.user?.role ?? 'citizen';
    return r[0].toUpperCase() + r.substring(1);
  }

  Future<void> _pickAndUploadPhoto() async {
    final uid = widget.user?.uid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await StorageService.instance.uploadProfilePhoto(uid, File(picked.path));
      await FirestoreService.instance.updateUserField(uid, 'photo_url', url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _roleColor();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: color.withValues(alpha: 0.15),
                  backgroundImage: widget.user?.photoUrl != null
                      ? CachedNetworkImageProvider(widget.user!.photoUrl!)
                      : null,
                  child: widget.user?.photoUrl == null
                      ? Text(
                    _initials().isNotEmpty ? _initials() : '?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _uploadingPhoto
                        ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user?.displayName ?? widget.user?.name ?? 'User',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.user?.email ?? '—',
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
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _roleLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
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

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final bool showChevron;
  final String? badge;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
    this.showChevron = true,
    this.badge,
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
            trailing: badge != null
                ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color:
                const Color(0xFF546E7A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF546E7A),
                ),
              ),
            )
                : showChevron
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

class _SwitchMenuTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool initialValue;

  const _SwitchMenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.initialValue,
  });

  @override
  State<_SwitchMenuTile> createState() => _SwitchMenuTileState();
}

class _SwitchMenuTileState extends State<_SwitchMenuTile> {
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