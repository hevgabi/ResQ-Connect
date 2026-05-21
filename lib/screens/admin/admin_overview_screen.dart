import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../services/firestore_service.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';
import '../settings/settings_screen.dart';
import 'admin_incidents_screen.dart';

class AdminOverviewScreen extends StatelessWidget {
  const AdminOverviewScreen({super.key});

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.people_outline,
                color: Color(0xFF0D47A1),
              ),
              title: const Text('Manage User Roles'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(
                Icons.notifications_outlined,
                color: Color(0xFF0D47A1),
              ),
              title: const Text('Alert Broadcasts'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF546E7A)),
              title: const Text('App Info'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        title: const Text(
          'Admin Overview',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: const [
                _ActiveSOSCard(),
                _RescuersActiveCard(),
                _EvacSlotsFreeCard(),
                _AvgResponseCard(),
              ],
            ),
            const SizedBox(height: 24),
            // Live Incidents section
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7263D),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live Incidents',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
                const SizedBox(width: 8),
                _PulsingDot(),
              ],
            ),
            const SizedBox(height: 12),
            _LiveIncidentsList(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminIncidentsScreen()),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        icon: const Icon(Icons.manage_search, color: Colors.white),
        label: const Text(
          'Manage Incidents',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Cards
// ---------------------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isLoading
                  ? Container(
                      width: 50,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                  : Text(
                      value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF546E7A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveSOSCard extends StatelessWidget {
  const _ActiveSOSCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_requests')
          .where('status', isEqualTo: 'open')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData
            ? snapshot.data!.docs.length.toString()
            : '—';
        return _KpiCard(
          label: 'Active SOS',
          value: count,
          icon: Icons.sos_outlined,
          color: const Color(0xFFD7263D),
          isLoading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }
}

class _RescuersActiveCard extends StatelessWidget {
  const _RescuersActiveCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuers')
          .where('is_on_duty', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData
            ? snapshot.data!.docs.length.toString()
            : '—';
        return _KpiCard(
          label: 'Rescuers Active',
          value: count,
          icon: Icons.emergency_outlined,
          color: const Color(0xFF1FAA59),
          isLoading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }
}

class _EvacSlotsFreeCard extends StatelessWidget {
  const _EvacSlotsFreeCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('evacuation_centers')
          .snapshots(),
      builder: (context, snapshot) {
        String display = '—';
        bool loading = snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasData) {
          int freeSlots = 0;
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final total = (data['total_slots'] as num?)?.toInt() ?? 0;
            final occupied = (data['occupied_slots'] as num?)?.toInt() ?? 0;
            freeSlots += (total - occupied).clamp(0, total);
          }
          display = freeSlots.toString();
        }

        return _KpiCard(
          label: 'Evac Slots Free',
          value: display,
          icon: Icons.home_outlined,
          color: const Color(0xFF0D47A1),
          isLoading: loading,
        );
      },
    );
  }
}

class _AvgResponseCard extends StatelessWidget {
  const _AvgResponseCard();

  @override
  Widget build(BuildContext context) {
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .where('accepted_at', isGreaterThanOrEqualTo: since)
          .snapshots(),
      builder: (context, snapshot) {
        String display = '—';
        bool loading = snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          double totalMin = 0;
          int count = 0;
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final arrivedAt = data['arrived_at'] as Timestamp?;
            final acceptedAt = data['accepted_at'] as Timestamp?;
            if (arrivedAt != null && acceptedAt != null) {
              final diff = (arrivedAt.seconds - acceptedAt.seconds) / 60.0;
              if (diff >= 0) {
                totalMin += diff;
                count++;
              }
            }
          }
          display = count > 0 ? (totalMin / count).toStringAsFixed(1) : '—';
        }

        return _KpiCard(
          label: 'Avg Response (min)',
          value: display,
          icon: Icons.timer_outlined,
          color: const Color(0xFFFF6B00),
          isLoading: loading,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Live Incidents List
// ---------------------------------------------------------------------------

class _LiveIncidentsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_requests')
          .where('status', isEqualTo: 'open')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _IncidentRowSkeleton(),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.check_circle_outline,
            iconColor: Color(0xFF1FAA59),
            title: 'No Active Incidents',
            subtitle: 'All clear — no open SOS requests right now.',
          );
        }

        final docs = snapshot.data!.docs;
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _IncidentRow(data: data),
            );
          }).toList(),
        );
      },
    );
  }
}

class _IncidentRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const _IncidentRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final type = (data['type'] as String?) ?? 'Unknown';
    final status = (data['status'] as String?) ?? 'open';
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();

    final locationText = (lat != null && lng != null)
        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
        : 'Unknown location';
    final timeText = createdAt != null ? timeago.format(createdAt) : 'Unknown';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'assigned':
        statusColor = const Color(0xFF0D47A1);
        statusLabel = 'Assigned';
        break;
      case 'resolved':
        statusColor = const Color(0xFF1FAA59);
        statusLabel = 'Resolved';
        break;
      default:
        statusColor = const Color(0xFFD7263D);
        statusLabel = 'Open';
    }

    return Container(
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  locationText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF546E7A),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeText,
                style: const TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncidentRowSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFECEFF1),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 12,
                  width: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 22,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFD7263D),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
