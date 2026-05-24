import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';

class ModeratorActivityLogsScreen extends StatefulWidget {
  const ModeratorActivityLogsScreen({super.key});

  @override
  State<ModeratorActivityLogsScreen> createState() =>
      _ModeratorActivityLogsScreenState();
}

class _ModeratorActivityLogsScreenState
    extends State<ModeratorActivityLogsScreen> {
  String _filterStatus = 'all'; // all | published | rejected

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        title: const Text(
          'Activity Logs',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        automaticallyImplyLeading: false,
        elevation: 2,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: const Color(0xFF0D47A1),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filterStatus == 'all',
                  onTap: () => setState(() => _filterStatus = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Published',
                  selected: _filterStatus == 'published',
                  color: const Color(0xFF1FAA59),
                  onTap: () => setState(() => _filterStatus = 'published'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Rejected',
                  selected: _filterStatus == 'rejected',
                  color: const Color(0xFFD7263D),
                  onTap: () => setState(() => _filterStatus = 'rejected'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('Not logged in'))
          : _buildLogs(uid),
      bottomNavigationBar: const ModeratorBottomNav(currentIndex: 4),
    );
  }

  Widget _buildLogs(String uid) {
    // Build query based on filter
    Query query;

    if (_filterStatus == 'published') {
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('moderator_id', isEqualTo: uid)
          .where('status', isEqualTo: 'published')
          .orderBy('published_at', descending: true)
          .limit(50);
    } else if (_filterStatus == 'rejected') {
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('reviewed_by', isEqualTo: uid)
          .where('status', isEqualTo: 'rejected')
          .orderBy('reviewed_at', descending: true)
          .limit(50);
    } else {
      // All: fetch by moderator_id (covers published)
      // We'll show both published and rejected by combining
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('moderator_id', isEqualTo: uid)
          .orderBy('published_at', descending: true)
          .limit(50);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.history_outlined,
            iconColor: Color(0xFF546E7A),
            title: 'No Activity Yet',
            subtitle: 'Your moderation actions will appear here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _ActivityLogCard(data: data, docId: doc.id);
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [_shimmer(140, 13), _shimmer(200, 11)],
        ),
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

// ---------------------------------------------------------------------------
// Activity Log Card
// ---------------------------------------------------------------------------

class _ActivityLogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;

  const _ActivityLogCard({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'unknown';
    final category = (data['category'] ?? data['type'] as String?) ?? 'other';
    final title = data['title'] as String? ?? category.replaceAll('_', ' ');
    final rejectionReason = data['rejection_reason'] as String?;

    final isPublished = status == 'published';
    final isRejected = status == 'rejected';

    final statusColor = isPublished
        ? const Color(0xFF1FAA59)
        : isRejected
        ? const Color(0xFFD7263D)
        : const Color(0xFF546E7A);

    final statusIcon = isPublished
        ? Icons.check_circle
        : isRejected
        ? Icons.cancel
        : Icons.pending;

    // Timestamp: published_at for published, reviewed_at for rejected
    final rawTs = isPublished
        ? data['published_at'] as Timestamp?
        : data['reviewed_at'] as Timestamp?;
    final actionTime = rawTs?.toDate();
    final timeText = actionTime != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(actionTime)
        : 'Date unknown';

    final aiScore = (data['ai_score'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withAlpha(51), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2B45),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusBadge(status: status, color: statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: Color(0xFF90A4AE),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF90A4AE),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: Color(0xFF6A1B9A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI: $aiScore',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6A1B9A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (isRejected && rejectionReason != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7263D).withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 13,
                          color: Color(0xFFD7263D),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            rejectionReason,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF37474F),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white.withAlpha(76),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? (color == Colors.white
                      ? const Color(0xFF0D47A1)
                      : Colors.white)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}
