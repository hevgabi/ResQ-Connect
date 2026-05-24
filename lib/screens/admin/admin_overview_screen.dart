import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../services/firestore_service.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';
import '../../screens/settings/hamburger_menu_screen.dart';
import 'admin_incidents_screen.dart';
import 'admin_rescuers_screen.dart';
import 'admin_evac_centers_screen.dart';
import 'admin_approvals_screen.dart';

class AdminOverviewScreen extends StatelessWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          tooltip: 'Menu',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
              const HamburgerMenuScreen(role: HamburgerRole.admin),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Overview',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              _formattedDate(),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<int>(
            stream: FirestoreService.instance.pendingApprovalsCountStream(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminApprovalsScreen(),
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          count > 9 ? '9+' : count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const _StatusBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      _PendingApprovalsCard(),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminIncidentsScreen(),
                          ),
                        ),
                        child: const Text(
                          'See all →',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _LiveIncidentsList(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formattedDate() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = days[now.weekday - 1];
    final month = months[now.month - 1];
    return '$day, $month ${now.day}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATUS BANNER
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreService.instance.pendingApprovalsCountStream(),
      builder: (context, snapshot) {
        final pending = snapshot.data ?? 0;
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('sos_requests')
              .where('status', isEqualTo: 'open')
              .snapshots(),
          builder: (context, sosSnap) {
            final activeSOS = sosSnap.data?.docs.length ?? 0;

            Color bannerColor;
            Color textColor;
            Color dotColor;
            String message;

            if (activeSOS > 0) {
              bannerColor = const Color(0xFFFFEBEE);
              textColor = const Color(0xFFB71C1C);
              dotColor = const Color(0xFFE53935);
              message =
              '$activeSOS active SOS request${activeSOS > 1 ? 's' : ''} need attention';
            } else if (pending > 0) {
              bannerColor = const Color(0xFFFFF8E1);
              textColor = const Color(0xFFE65100);
              dotColor = const Color(0xFFF57F17);
              message =
              '$pending pending registration${pending > 1 ? 's' : ''} need review';
            } else {
              bannerColor = const Color(0xFFE8F5E9);
              textColor = const Color(0xFF2E7D32);
              dotColor = const Color(0xFF43A047);
              message = 'All systems normal';
            }

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: bannerColor,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KPI CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isLoading
                  ? Container(
                width: 50,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
              )
                  : Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF546E7A),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
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
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _KpiCard(
          label: 'Active SOS',
          value: snapshot.hasData ? count.toString() : '—',
          subtitle: count > 0 ? '● Needs attention' : '● All clear',
          icon: Icons.sos_outlined,
          color: count > 0
              ? const Color(0xFFD7263D)
              : const Color(0xFF1FAA59),
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
          .snapshots(),
      builder: (context, snapshot) {
        int onDuty = 0;
        int offDuty = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['is_on_duty'] == true) {
              onDuty++;
            } else {
              offDuty++;
            }
          }
        }
        return _KpiCard(
          label: 'Rescuers Active',
          value: snapshot.hasData ? onDuty.toString() : '—',
          subtitle: snapshot.hasData ? '$offDuty off duty' : '',
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
        String subtitle = '';
        bool loading = snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasData) {
          int freeSlots = 0;
          int totalSlots = 0;
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final total = (data['capacity'] as num?)?.toInt() ?? 0;
            final occupied =
                (data['current_occupancy'] as num?)?.toInt() ?? 0;
            freeSlots += (total - occupied).clamp(0, total);
            totalSlots += total;
          }
          display = freeSlots.toString();
          final pct = totalSlots > 0
              ? ((1 - freeSlots / totalSlots) * 100).toStringAsFixed(0)
              : '0';
          subtitle = '$pct% occupied';
        }

        return _KpiCard(
          label: 'Evac Slots Free',
          value: display,
          subtitle: subtitle,
          icon: Icons.home_outlined,
          color: const Color(0xFF0D47A1),
          isLoading: loading,
        );
      },
    );
  }
}

class _PendingApprovalsCard extends StatelessWidget {
  const _PendingApprovalsCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreService.instance.pendingApprovalsCountStream(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminApprovalsScreen(),
            ),
          ),
          child: _KpiCard(
            label: 'Pending Approvals',
            value: snapshot.hasData ? count.toString() : '—',
            subtitle: count > 0 ? '● Action required' : '● All reviewed',
            icon: Icons.how_to_reg_outlined,
            color: count > 0
                ? const Color(0xFFE65100)
                : const Color(0xFF1FAA59),
            isLoading: snapshot.connectionState == ConnectionState.waiting,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVE INCIDENTS LIST
// ═══════════════════════════════════════════════════════════════════════════

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
    final timeText =
    createdAt != null ? timeago.format(createdAt) : 'Unknown';

    Color dotColor;
    String priorityLabel;
    Color priorityBg;
    Color priorityText;

    if (status == 'open') {
      dotColor = const Color(0xFFE53935);
      priorityLabel = 'CRITICAL';
      priorityBg = const Color(0xFFFFEBEE);
      priorityText = const Color(0xFFB71C1C);
    } else if (status == 'assigned') {
      dotColor = const Color(0xFFFB8C00);
      priorityLabel = 'ACTIVE';
      priorityBg = const Color(0xFFFFF3E0);
      priorityText = const Color(0xFFE65100);
    } else {
      dotColor = const Color(0xFF43A047);
      priorityLabel = 'MONITORING';
      priorityBg = const Color(0xFFE8F5E9);
      priorityText = const Color(0xFF2E7D32);
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
              color: dotColor,
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
                    fontSize: 11,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: priorityBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priorityLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: priorityText,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeText,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF546E7A),
                ),
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
            width: 70,
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

// ═══════════════════════════════════════════════════════════════════════════
// PULSING DOT ANIMATION
// ═══════════════════════════════════════════════════════════════════════════

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