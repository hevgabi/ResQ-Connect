import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';
import '../settings/settings_screen.dart';

// TANDAAN: Kung may ginawa kang ReportModel class, siguraduhing i-import mo rito kung kinakailangan.
// halimbawa: import '../../models/report_model.dart';

class ModeratorPublishedFeedScreen extends StatelessWidget {
  const ModeratorPublishedFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D47A1),
          title: const Text(
            'Community Feed',
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
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: 'Published'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        body: const TabBarView(children: [_PublishedTab(), _RejectedTab()]),
        bottomNavigationBar: const ModeratorBottomNav(currentIndex: 1),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Published Tab
// ---------------------------------------------------------------------------

class _PublishedTab extends StatelessWidget {
  const _PublishedTab();

  @override
  Widget build(BuildContext context) {
    // FIX: Binago mula QuerySnapshot patungong List<dynamic> (o List<ReportModel> depende sa iyong model setup)
    return StreamBuilder<List<dynamic>>(
      stream: FirestoreService.instance.publishedReportsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.public_off,
            iconColor: Color(0xFF546E7A),
            title: 'No Published Reports',
            subtitle: 'Reports you approve will appear here.',
          );
        }

        // FIX: Direkta nang List ang data, wala nang .docs
        final reports = snapshot.data!;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final report = reports[index];

            // KUNG ang report ay isang custom object (Model), kadalasan ay may id at toMap() o fields ito.
            // Iniaangkop natin ito para gumana kahit Model o Map ang balik ng iyong stream.
            final String reportId = report.id;
            final Map<String, dynamic> data = (report is Map)
                ? report as Map<String, dynamic>
                : report.toMap();

            return _PublishedCard(reportId: reportId, data: data);
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _CardSkeleton(),
    );
  }
}

class _PublishedCard extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const _PublishedCard({required this.reportId, required this.data});

  @override
  State<_PublishedCard> createState() => _PublishedCardState();
}

class _PublishedCardState extends State<_PublishedCard> {
  bool _hasActiveMission = false;
  int _rescuerCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMissionData();
  }

  Future<void> _loadMissionData() async {
    try {
      final missionsSnap = await FirebaseFirestore.instance
          .collection('missions')
          .where('report_id', isEqualTo: widget.reportId)
          .where('status', isEqualTo: 'active')
          .get();

      if (mounted) {
        setState(() {
          _hasActiveMission = missionsSnap.docs.isNotEmpty;
          _rescuerCount = missionsSnap.docs.length;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final reportType = (data['type'] as String?) ?? 'General';
    final title =
        (data['title'] as String?) ??
        reportType.replaceAll('_', ' ').toUpperCase();
    final approvedAt = (data['approved_at'] as Timestamp?)?.toDate();
    final approvedAtText = approvedAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(approvedAt)
        : 'Recently';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasActiveMission
              ? const Color(0xFF1FAA59).withAlpha(102)
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
              ),
              if (_hasActiveMission) _LiveBadge(),
            ],
          ),
          const SizedBox(height: 8),
          _TypeChipSmall(type: reportType),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.check_circle_outline,
            text: 'Approved $approvedAtText',
            color: const Color(0xFF1FAA59),
          ),
          if (_rescuerCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _InfoRow(
                icon: Icons.people_outline,
                text:
                    '$_rescuerCount rescuer${_rescuerCount > 1 ? 's' : ''} assigned',
                color: const Color(0xFF0D47A1),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD7263D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rejected Tab
// ---------------------------------------------------------------------------

class _RejectedTab extends StatelessWidget {
  const _RejectedTab();

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid;

    if (uid == null) {
      return const Center(child: Text('Not authenticated'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'rejected')
          .where('reviewed_by', isEqualTo: uid)
          .orderBy('reviewed_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.thumb_up_outlined,
            iconColor: Color(0xFF1FAA59),
            title: 'No Rejected Reports',
            subtitle: 'Reports you reject will appear here.',
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _RejectedCard(data: data);
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => _CardSkeleton(),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RejectedCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final reportType = (data['type'] as String?) ?? 'General';
    final title =
        (data['title'] as String?) ??
        reportType.replaceAll('_', ' ').toUpperCase();
    final rejectionReason =
        (data['rejection_reason'] as String?) ?? 'No reason provided';
    final reviewedAt = (data['reviewed_at'] as Timestamp?)?.toDate();
    final reviewedAtText = reviewedAt != null
        ? timeago.format(reviewedAt)
        : 'Recently';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD7263D).withAlpha(51),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
              ),
              const Icon(
                Icons.cancel_outlined,
                color: Color(0xFFD7263D),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TypeChipSmall(type: reportType),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD7263D).withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7263D).withAlpha(51)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rejection Reason',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD7263D),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rejectionReason,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF37474F),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.access_time,
            text: 'Rejected $reviewedAtText',
            color: const Color(0xFF546E7A),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TypeChipSmall extends StatelessWidget {
  final String type;

  const _TypeChipSmall({required this.type});

  Color get _color {
    switch (type.toLowerCase()) {
      case 'flood':
        return const Color(0xFF0D47A1);
      case 'fire':
        return const Color(0xFFD7263D);
      case 'rescue_needed':
        return const Color(0xFFFF6B00);
      default:
        return const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _color,
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [_shimmer(180, 14), _shimmer(60, 12), _shimmer(220, 12)],
      ),
    );
  }

  Widget _shimmer(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}
