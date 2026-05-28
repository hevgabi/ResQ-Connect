import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  bool _showProfileToPublic = true;
  bool _shareLocationWithRescuers = true;
  bool _allowDataAnalytics = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final data = await FirestoreService.instance.getUser(uid);
      if (data != null && mounted) {
        setState(() {
          _showProfileToPublic   = data['privacy_show_profile']     as bool? ?? true;
          _shareLocationWithRescuers = data['privacy_share_location'] as bool? ?? true;
          _allowDataAnalytics    = data['privacy_data_analytics']   as bool? ?? false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await FirestoreService.instance.updateUser(uid, {
        'privacy_show_profile':    _showProfileToPublic,
        'privacy_share_location':  _shareLocationWithRescuers,
        'privacy_data_analytics':  _allowDataAnalytics,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Privacy settings saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        title: const Text(
          'Privacy Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            icon: Icons.shield_outlined,
            color: const Color(0xFF1B5E20),
            text:
            'These settings control how your data is shared within ResQConnect. Your location is only shared during active emergencies.',
          ),
          const SizedBox(height: 16),
          _sectionHeader('Visibility'),
          _SwitchTile(
            title: 'Show Profile to Public',
            subtitle: 'Your name and role are visible to other users',
            value: _showProfileToPublic,
            onChanged: (v) => setState(() => _showProfileToPublic = v),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchTile(
            title: 'Share Location with Rescuers',
            subtitle: 'Allow assigned rescuers to see your live location during emergencies',
            value: _shareLocationWithRescuers,
            onChanged: (v) => setState(() => _shareLocationWithRescuers = v),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Data & Analytics'),
          _SwitchTile(
            title: 'Allow Analytics',
            subtitle: 'Help improve the app by sharing anonymous usage data',
            value: _allowDataAnalytics,
            onChanged: (v) => setState(() => _allowDataAnalytics = v),
          ),
          const SizedBox(height: 24),
          Text(
            'For questions about your data, contact support@resqconnect.ph',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label.toUpperCase(),
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoCard({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary,
                    )),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF1B5E20),
          ),
        ],
      ),
    );
  }
}