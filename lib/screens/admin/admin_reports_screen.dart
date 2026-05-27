import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reports',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Incidents'),
            Tab(text: 'Rescuers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _IncidentStatsTab(),
          _RescuerStatsTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INCIDENT STATS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _IncidentStatsTab extends StatelessWidget {
  const _IncidentStatsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_requests')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('No data available.'));
        }

        final docs = snapshot.data!.docs;
        int open = 0, assigned = 0, resolved = 0;
        int totalResponseSecs = 0;
        int responseCount = 0;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] as String?) ?? 'open';
          switch (status) {
            case 'open':
              open++;
              break;
            case 'assigned':
              assigned++;
              break;
            case 'resolved':
              resolved++;
              break;
          }
          final createdAt = data['created_at'] as Timestamp?;
          final resolvedAt = data['resolved_at'] as Timestamp?;
          if (createdAt != null && resolvedAt != null) {
            final diff = resolvedAt.seconds - createdAt.seconds;
            if (diff > 0) {
              totalResponseSecs += diff;
              responseCount++;
            }
          }
        }

        final total = docs.length;
        final avgMins = responseCount > 0
            ? (totalResponseSecs / responseCount / 60).toStringAsFixed(1)
            : '—';
        final resolvedPct = total > 0
            ? ((resolved / total) * 100).toStringAsFixed(0)
            : '0';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ReportSectionHeader('Overview'),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _StatCard(
                    label: 'Total Incidents',
                    value: total.toString(),
                    icon: Icons.warning_amber_outlined,
                    color: AppTheme.primaryBlue,
                  ),
                  _StatCard(
                    label: 'Resolved',
                    value: '$resolved ($resolvedPct%)',
                    icon: Icons.check_circle_outline,
                    color: AppTheme.successGreen,
                  ),
                  _StatCard(
                    label: 'Open',
                    value: open.toString(),
                    icon: Icons.sos_outlined,
                    color: AppTheme.dangerRed,
                  ),
                  _StatCard(
                    label: 'Avg Response',
                    value: '$avgMins min',
                    icon: Icons.timer_outlined,
                    color: AppTheme.warningOrange,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _ReportSectionHeader('Status Breakdown'),
              const SizedBox(height: 12),
              _StatusBar(
                  label: 'Open',
                  count: open,
                  total: total,
                  color: AppTheme.dangerRed),
              const SizedBox(height: 8),
              _StatusBar(
                  label: 'Assigned',
                  count: assigned,
                  total: total,
                  color: AppTheme.primaryBlue),
              const SizedBox(height: 8),
              _StatusBar(
                  label: 'Resolved',
                  count: resolved,
                  total: total,
                  color: AppTheme.successGreen),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESCUER STATS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _RescuerStatsTab extends StatelessWidget {
  const _RescuerStatsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuers')
          .snapshots(),
      builder: (context, rescuerSnap) {
        if (rescuerSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rescuers = rescuerSnap.data?.docs ?? [];
        int onDuty = 0, offDuty = 0;

        for (final doc in rescuers) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['is_on_duty'] == true) {
            onDuty++;
          } else {
            offDuty++;
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('missions')
              .snapshots(),
          builder: (context, missionSnap) {
            final missions = missionSnap.data?.docs ?? [];
            int completed = 0;
            double totalMissionMins = 0;
            int timedMissions = 0;

            for (final doc in missions) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['status'] == 'completed') completed++;
              final acceptedAt = data['accepted_at'] as Timestamp?;
              final arrivedAt = data['arrived_at'] as Timestamp?;
              if (acceptedAt != null && arrivedAt != null) {
                final diff = (arrivedAt.seconds - acceptedAt.seconds) / 60.0;
                if (diff > 0) {
                  totalMissionMins += diff;
                  timedMissions++;
                }
              }
            }

            final avgResponseMins = timedMissions > 0
                ? (totalMissionMins / timedMissions).toStringAsFixed(1)
                : '—';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ReportSectionHeader('Rescuer Overview'),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _StatCard(
                        label: 'Total Rescuers',
                        value: rescuers.length.toString(),
                        icon: Icons.people_outline,
                        color: AppTheme.primaryBlue,
                      ),
                      _StatCard(
                        label: 'On Duty',
                        value: onDuty.toString(),
                        icon: Icons.emergency_outlined,
                        color: AppTheme.successGreen,
                      ),
                      _StatCard(
                        label: 'Missions Done',
                        value: completed.toString(),
                        icon: Icons.task_alt_outlined,
                        color: AppTheme.warningOrange,
                      ),
                      _StatCard(
                        label: 'Avg Response',
                        value: '$avgResponseMins min',
                        icon: Icons.timer_outlined,
                        color: AppTheme.dangerRed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _ReportSectionHeader('Duty Status'),
                  const SizedBox(height: 12),
                  _StatusBar(
                    label: 'On Duty',
                    count: onDuty,
                    total: rescuers.length,
                    color: AppTheme.successGreen,
                  ),
                  const SizedBox(height: 8),
                  _StatusBar(
                    label: 'Off Duty',
                    count: offDuty,
                    total: rescuers.length,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 24),
                  const _ReportSectionHeader('Top Rescuers by Missions'),
                  const SizedBox(height: 12),
                  ..._topRescuers(rescuers),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _topRescuers(List<QueryDocumentSnapshot> rescuers) {
    final sorted = [...rescuers];
    sorted.sort((a, b) {
      final aCount =
          ((a.data() as Map)['active_mission_count'] as num?)?.toInt() ??
              0;
      final bCount =
          ((b.data() as Map)['active_mission_count'] as num?)?.toInt() ??
              0;
      return bCount.compareTo(aCount);
    });

    return sorted.take(5).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name =
          (data['display_name'] as String?) ?? 'Unknown Rescuer';
      final missions =
          (data['active_mission_count'] as num?)?.toInt() ?? 0;
      final isOnDuty = data['is_on_duty'] == true;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
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
            CircleAvatar(
              radius: 20,
              backgroundColor:
              AppTheme.primaryBlue.withValues(alpha: 0.1),
              child: Text(initial,
                  style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                    '$missions active mission${missions != 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isOnDuty
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFECEFF1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isOnDuty ? 'On Duty' : 'Off Duty',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isOnDuty
                      ? AppTheme.successGreen
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _ReportSectionHeader extends StatelessWidget {
  final String title;
  const _ReportSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2B45),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _StatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(
                '$count (${(pct * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}