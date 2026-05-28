import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/broadcast_alert_overlay.dart';

class ModeratorStatisticsScreen extends StatelessWidget {
  const ModeratorStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'My Statistics',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 2,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.moderator),
          ),
        ],
      ),
      body: Stack(
        children: [
          uid.isEmpty
              ? const Center(child: Text('Not logged in'))
              : _StatisticsBody(moderatorId: uid),
          const BroadcastAlertOverlay(topOffset: 12),
        ],
      ),
      bottomNavigationBar: const ModeratorBottomNav(currentIndex: 2),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Body
// ---------------------------------------------------------------------------

class _StatisticsBody extends StatelessWidget {
  final String moderatorId;

  const _StatisticsBody({required this.moderatorId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: FirestoreService.instance.moderatorStatsStream(moderatorId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final stats =
            snapshot.data ??
            {
              'published': 0,
              'rejected': 0,
              'pending': 0,
              'avgReviewMinutes': 0.0,
              'highConfidence': 0,
              'mediumConfidence': 0,
              'lowConfidence': 0,
              'recentActivity': <Map<String, dynamic>>[],
            };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── KPI Cards ──────────────────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _KpiCard(
                  icon: Icons.check_circle_outline,
                  iconColor: const Color(0xFF1FAA59),
                  label: 'Published',
                  value: '${stats['published']}',
                ),
                _KpiCard(
                  icon: Icons.cancel_outlined,
                  iconColor: const Color(0xFFD7263D),
                  label: 'Rejected',
                  value: '${stats['rejected']}',
                ),
                _KpiCard(
                  icon: Icons.pending_actions_outlined,
                  iconColor: const Color(0xFFFF6B00),
                  label: 'Pending',
                  value: '${stats['pending']}',
                ),
                _KpiCard(
                  icon: Icons.timer_outlined,
                  iconColor: const Color(0xFF0D47A1),
                  label: 'Avg Review',
                  value:
                      '${(stats['avgReviewMinutes'] as double).toStringAsFixed(1)} min',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── AI Score Breakdown ─────────────────────────────────────────
            _SectionHeader(
              title: 'AI Score Breakdown',
              icon: Icons.analytics_outlined,
            ),
            const SizedBox(height: 10),
            _AiBreakdownCard(
              high: stats['highConfidence'] as int,
              medium: stats['mediumConfidence'] as int,
              low: stats['lowConfidence'] as int,
            ),

            const SizedBox(height: 20),

            // ── Recent Activity ────────────────────────────────────────────
            _SectionHeader(
              title: 'Recent Activity',
              icon: Icons.history_outlined,
            ),
            const SizedBox(height: 10),
            _RecentActivityList(
              activities: List<Map<String, dynamic>>.from(
                stats['recentActivity'] ?? [],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Card
// ---------------------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF546E7A)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Score Breakdown Card
// ---------------------------------------------------------------------------

class _AiBreakdownCard extends StatelessWidget {
  final int high;
  final int medium;
  final int low;

  const _AiBreakdownCard({
    required this.high,
    required this.medium,
    required this.low,
  });

  @override
  Widget build(BuildContext context) {
    final total = high + medium + low;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _ScoreRow(
            label: 'High Confidence',
            sublabel: '≥ 75',
            count: high,
            total: total,
            color: const Color(0xFF6A1B9A),
          ),
          const SizedBox(height: 12),
          _ScoreRow(
            label: 'Medium Confidence',
            sublabel: '40 – 74',
            count: medium,
            total: total,
            color: const Color(0xFFFF6B00),
          ),
          const SizedBox(height: 12),
          _ScoreRow(
            label: 'Low Confidence',
            sublabel: '< 40',
            count: low,
            total: total,
            color: const Color(0xFFD7263D),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final int count;
  final int total;
  final Color color;

  const _ScoreRow({
    required this.label,
    required this.sublabel,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF37474F),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF90A4AE),
                  ),
                ),
              ],
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: color.withAlpha(30),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Activity List
// ---------------------------------------------------------------------------

class _RecentActivityList extends StatelessWidget {
  final List<Map<String, dynamic>> activities;

  const _RecentActivityList({required this.activities});

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No recent activity yet.',
            style: TextStyle(color: Color(0xFF546E7A)),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final item = activities[index];
          final status = item['status'] as String? ?? 'pending';
          final category = item['category'] as String? ?? 'other';
          final publishedAt = item['published_at'];
          final reviewedAt = publishedAt is Timestamp
              ? publishedAt.toDate()
              : null;

          final isPublished = status == 'published';
          final statusColor = isPublished
              ? const Color(0xFF1FAA59)
              : const Color(0xFFD7263D);
          final statusIcon = isPublished ? Icons.check_circle : Icons.cancel;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, color: statusColor, size: 18),
            ),
            title: Text(
              category.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF37474F),
              ),
            ),
            subtitle: reviewedAt != null
                ? Text(
                    _formatDate(reviewedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF90A4AE),
                    ),
                  )
                : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Section Header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6A1B9A)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF263238),
          ),
        ),
      ],
    );
  }
}
