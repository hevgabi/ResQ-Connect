import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/alert_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../settings/hamburger_menu_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _orange = Color(0xFFFF6B00);
  static const _green = Color(0xFF1FAA59);
  static const _bg = Color(0xFFF5F7FA);
  static const _textSec = Color(0xFF546E7A);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Alerts & Notifications',
          style: TextStyle(
            color: _blue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _blue),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: _blue),
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.citizen),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_uid != null) _buildPersonalNotifications(_uid!),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Community Alerts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _textSec,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            _buildGlobalAlerts(),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Widget _buildPersonalNotifications(String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      // Uses citizenNotificationsStream — reads from `reports` collection
      // which citizen already has read access to (no new Firestore rules needed)
      stream: FirestoreService.instance.citizenNotificationsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Post Updates',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _textSec,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...posts.map((post) => _buildPostNotifCard(uid, post)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPostNotifCard(String uid, Map<String, dynamic> post) {
    final status = post['status'] as String? ?? '';
    final isApproved = status == 'published';
    final isRead = post['notif_read'] as bool? ?? true;
    final color = isApproved ? _green : _red;
    final icon = isApproved
        ? Icons.check_circle_outline
        : Icons.cancel_outlined;

    final title = isApproved ? 'Post Approved' : 'Post Not Approved';
    final postLabel = (post['title'] as String?)?.isNotEmpty == true
        ? post['title'] as String
        : (post['type'] as String? ?? 'Your post');
    final message = isApproved
        ? '"$postLabel" has been published to the community feed.'
        : '"$postLabel" was not approved. Reason: ${post['rejection_reason'] ?? 'No reason given.'}';

    // Time
    String timeStr = '';
    final reviewed = post['reviewed_at'] ?? post['published_at'];
    if (reviewed != null) {
      try {
        final dt = (reviewed as dynamic).toDate() as DateTime;
        timeStr = timeago.format(dt);
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () {
        if (!isRead) {
          FirestoreService.instance.markReportNotifRead(post['id'] as String);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: color,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textSec,
                      height: 1.4,
                    ),
                  ),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(fontSize: 11, color: _textSec),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalAlerts() {
    return StreamBuilder<List<AlertModel>>(
      stream: FirestoreService.instance.alertsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_off_outlined,
            title: 'No alerts right now',
            subtitle: 'You\'re all caught up!',
          );
        }

        return Column(
          children: snapshot.data!.map((alert) {
            final isCritical = alert.severity == 'critical';
            final borderColor = isCritical ? _red : _orange;
            final iconData = isCritical
                ? Icons.warning_rounded
                : Icons.info_outline_rounded;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: borderColor, width: 4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconData, color: borderColor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: borderColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.message,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSec,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
