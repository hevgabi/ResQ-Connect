import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  String? _expandedId;

  static const _faqs = [
    _FAQ(
      id: 'sos',
      question: 'How do I send an SOS request?',
      answer:
      'Tap the red SOS button on your home screen. You can choose an emergency category (e.g., Medical, Fire, Rescue) and optionally add a description or photo. Your location is automatically shared with nearby rescuers.',
    ),
    _FAQ(
      id: 'track',
      question: 'How do I track my rescue request?',
      answer:
      'After submitting an SOS, go to the Queue tab or check your Alerts & Notifications. You will see live status updates as a rescuer accepts and responds to your request.',
    ),
    _FAQ(
      id: 'cancel',
      question: 'Can I cancel an SOS request?',
      answer:
      'Yes. Open your active SOS from the Queue or Notifications screen and tap "Cancel Request." Please only cancel if the emergency has been resolved or was submitted by mistake.',
    ),
    _FAQ(
      id: 'location',
      question: 'Why does the app need my location?',
      answer:
      'ResQConnect uses your GPS location to dispatch the nearest available rescuer and to show your position on the live map. Location access is required for SOS and tracking features to work correctly.',
    ),
    _FAQ(
      id: 'rescuer',
      question: 'How are rescuers assigned to my request?',
      answer:
      'Rescuers who are marked "On Duty" receive SOS alerts in their queue. The first available rescuer who accepts your request is assigned. You will be notified immediately when this happens.',
    ),
    _FAQ(
      id: 'profile',
      question: 'How do I update my personal information?',
      answer:
      'Go to Menu → Personal Information to update your name and phone number. You can also update your profile photo by tapping your avatar on the profile or menu screen.',
    ),
    _FAQ(
      id: 'password',
      question: 'How do I change my password?',
      answer:
      'Go to Menu → Change Password. Enter your email address and we will send you a password reset link. Follow the instructions in the email to set a new password.',
    ),
    _FAQ(
      id: 'alerts',
      question: 'What are Community Alerts?',
      answer:
      'Community Alerts are emergency broadcasts sent by moderators or admins to inform citizens about ongoing incidents, evacuation orders, or public safety notices in your area.',
    ),
    _FAQ(
      id: 'post',
      question: 'How do I report an incident or create a post?',
      answer:
      'Tap the "+" icon or use the "Report Incident" option from your home screen. Your post goes into a moderation queue and will be reviewed before being published to the community feed.',
    ),
    _FAQ(
      id: 'notif',
      question: 'Why am I not receiving notifications?',
      answer:
      'Make sure Push Notifications and Emergency Alerts are enabled in Menu → Notifications. Also check your device notification settings to ensure ResQConnect has permission to send alerts.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.support_agent, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How can we help?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Browse FAQs or contact us directly.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Contact options
          _sectionTitle('Contact Us'),
          const SizedBox(height: 10),
          _ContactCard(
            icon: Icons.email_outlined,
            iconColor: AppTheme.primaryBlue,
            title: 'Email Support',
            subtitle: 'support@resqconnect.ph',
            onTap: () => _launchUrl('mailto:support@resqconnect.ph'),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.phone_outlined,
            iconColor: const Color(0xFF1FAA59),
            title: 'Emergency Hotline',
            subtitle: '911 — National Emergency',
            onTap: () => _launchUrl('tel:911'),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.language_outlined,
            iconColor: const Color(0xFF6A1B9A),
            title: 'Visit our Website',
            subtitle: 'www.resqconnect.ph',
            onTap: () => _launchUrl('https://www.resqconnect.ph'),
          ),

          const SizedBox(height: 24),

          // FAQs
          _sectionTitle('Frequently Asked Questions'),
          const SizedBox(height: 10),

          ..._faqs.map((faq) => _FAQTile(
            faq: faq,
            isExpanded: _expandedId == faq.id,
            onTap: () {
              setState(() {
                _expandedId = _expandedId == faq.id ? null : faq.id;
              });
            },
          )),

          const SizedBox(height: 24),

          // App version footer
          Center(
            child: Text(
              'ResQConnect v1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link.')),
        );
      }
    }
  }
}

// ── FAQ Data Model ────────────────────────────────────────────────────────────

class _FAQ {
  final String id;
  final String question;
  final String answer;
  const _FAQ({required this.id, required this.question, required this.answer});
}

// ── FAQ Tile ──────────────────────────────────────────────────────────────────

class _FAQTile extends StatelessWidget {
  final _FAQ faq;
  final bool isExpanded;
  final VoidCallback onTap;

  const _FAQTile({
    required this.faq,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExpanded
                          ? Icons.remove_rounded
                          : Icons.add_rounded,
                      size: 16,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      faq.question,
                      style: TextStyle(
                        fontWeight: isExpanded ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                        color: isExpanded
                            ? AppTheme.primaryBlue
                            : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: Text(
                    faq.answer,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Contact Card ──────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}