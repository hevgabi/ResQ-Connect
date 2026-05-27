import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/report_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';

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
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () =>
                  showHamburgerMenu(context, role: HamburgerRole.moderator),
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
    return StreamBuilder<List<ReportModel>>(
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

        final reports = snapshot.data!;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) =>
              _PublishedCard(report: reports[index]),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _CardSkeleton(),
    );
  }
}

class _PublishedCard extends StatefulWidget {
  final ReportModel report;
  const _PublishedCard({required this.report});

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
          .where('report_id', isEqualTo: widget.report.id)
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

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostDetailSheet(
        report: widget.report,
        hasActiveMission: _hasActiveMission,
        rescuerCount: _rescuerCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final reportType = report.category;
    final title = report.title.isNotEmpty
        ? report.title
        : reportType.replaceAll('_', ' ').toUpperCase();
    final publishedAt = report.publishedAt;
    final metaText = publishedAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(publishedAt)
        : 'Recently';
    final mediaUrls = report.photoUrls;

    return _FeedCard(
      title: title,
      reportType: reportType,
      body: report.body,
      photoUrls: mediaUrls,
      statusBadge: _StatusBadge.published,
      metaIcon: Icons.check_circle_outline,
      metaText: 'Published $metaText',
      metaColor: const Color(0xFF1FAA59),
      trailingBadge: _hasActiveMission ? const _LiveBadge() : null,
      extraInfo: _rescuerCount > 0
          ? _InfoRow(
              icon: Icons.people_outline,
              text:
                  '$_rescuerCount rescuer${_rescuerCount > 1 ? 's' : ''} assigned',
              color: const Color(0xFF0D47A1),
            )
          : null,
      onTap: () => _showDetail(context),
    );
  }
}

// ---------------------------------------------------------------------------
// Post Detail Bottom Sheet (Published)
// ---------------------------------------------------------------------------

class _PostDetailSheet extends StatelessWidget {
  final ReportModel report;
  final bool hasActiveMission;
  final int rescuerCount;

  const _PostDetailSheet({
    required this.report,
    required this.hasActiveMission,
    required this.rescuerCount,
  });

  @override
  Widget build(BuildContext context) {
    final mediaUrls = report.photoUrls;
    final reportType = report.category;
    final title = report.title.isNotEmpty
        ? report.title
        : reportType.replaceAll('_', ' ').toUpperCase();
    final body = report.body;
    final authorName = report.reporterName;
    final address = report.address ?? '';
    final publishedAt = report.publishedAt;
    final publishedAtText = publishedAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(publishedAt)
        : 'Recently';
    final createdAt = report.createdAt;
    final submittedAtText = createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt)
        : '';

    return _DetailSheet(
      title: title,
      reportType: reportType,
      body: body,
      mediaUrls: mediaUrls,
      authorName: authorName.isNotEmpty ? authorName : 'Anonymous',
      address: address,
      submittedAtText: submittedAtText,
      statusChip: _SheetStatusChip(
        label: 'Published',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF1FAA59),
      ),
      extraBadge: hasActiveMission ? const _LiveBadge() : null,
      detailRows: [
        if (submittedAtText.isNotEmpty)
          _DetailRow(
            icon: Icons.upload_outlined,
            label: 'Submitted',
            value: submittedAtText,
          ),
        _DetailRow(
          icon: Icons.check_circle_outline,
          label: 'Published',
          value: publishedAtText,
          valueColor: const Color(0xFF1FAA59),
        ),
        if (rescuerCount > 0)
          _DetailRow(
            icon: Icons.people_outline,
            label: 'Rescuers',
            value: '$rescuerCount assigned',
            valueColor: const Color(0xFF0D47A1),
          ),
      ],
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

        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aTs =
                (a.data() as Map<String, dynamic>)['reviewed_at'] as Timestamp?;
            final bTs =
                (b.data() as Map<String, dynamic>)['reviewed_at'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });
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
      itemBuilder: (_, __) => const _CardSkeleton(),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RejectedCard({required this.data});

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RejectedDetailSheet(data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportType =
        (data['category'] as String?) ?? (data['type'] as String?) ?? 'General';
    final title =
        (data['title'] as String?) ??
        reportType.replaceAll('_', ' ').toUpperCase();
    final body =
        (data['body'] as String?)?.trim() ??
        (data['text'] as String?)?.trim() ??
        '';
    final photoUrls = List<String>.from(
      data['photo_urls'] ?? data['media_urls'] ?? [],
    );
    final reviewedAt = (data['reviewed_at'] as Timestamp?)?.toDate();
    final metaText = reviewedAt != null
        ? timeago.format(reviewedAt)
        : 'Recently';

    return _FeedCard(
      title: title,
      reportType: reportType,
      body: body,
      photoUrls: photoUrls,
      statusBadge: _StatusBadge.rejected,
      metaIcon: Icons.cancel_outlined,
      metaText: 'Rejected $metaText',
      metaColor: const Color(0xFFD7263D),
      onTap: () => _showDetail(context),
    );
  }
}

// ---------------------------------------------------------------------------
// Rejected Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _RejectedDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RejectedDetailSheet({required this.data});

  @override
  Widget build(BuildContext context) {
    final reportType =
        (data['category'] as String?) ?? (data['type'] as String?) ?? 'General';
    final title =
        (data['title'] as String?) ??
        reportType.replaceAll('_', ' ').toUpperCase();
    final body =
        (data['body'] as String?)?.trim() ??
        (data['text'] as String?)?.trim() ??
        '';
    final photoUrls = List<String>.from(
      data['photo_urls'] ?? data['media_urls'] ?? [],
    );
    final authorName =
        ((data['reporter_name'] as String?) ??
                (data['author_name'] as String?) ??
                '')
            .trim();
    final address = (data['address'] as String?) ?? '';
    final rejectionReason =
        (data['rejection_reason'] as String?) ?? 'No reason provided';
    final reviewedAt = (data['reviewed_at'] as Timestamp?)?.toDate();
    final reviewedAtText = reviewedAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(reviewedAt)
        : 'Recently';
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final submittedAtText = createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt)
        : '';

    return _DetailSheet(
      title: title,
      reportType: reportType,
      body: body,
      mediaUrls: photoUrls,
      authorName: authorName.isNotEmpty ? authorName : 'Anonymous',
      address: address,
      submittedAtText: submittedAtText,
      statusChip: _SheetStatusChip(
        label: 'Rejected',
        icon: Icons.cancel_outlined,
        color: const Color(0xFFD7263D),
      ),
      rejectionReason: rejectionReason,
      detailRows: [
        if (submittedAtText.isNotEmpty)
          _DetailRow(
            icon: Icons.upload_outlined,
            label: 'Submitted',
            value: submittedAtText,
          ),
        _DetailRow(
          icon: Icons.cancel_outlined,
          label: 'Rejected',
          value: reviewedAtText,
          valueColor: const Color(0xFFD7263D),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared Feed Card — same layout for both Published & Rejected
// ---------------------------------------------------------------------------

enum _StatusBadge { published, rejected }

class _FeedCard extends StatelessWidget {
  final String title;
  final String reportType;
  final String body;
  final List<String> photoUrls;
  final _StatusBadge statusBadge;
  final IconData metaIcon;
  final String metaText;
  final Color metaColor;
  final Widget? trailingBadge;
  final Widget? extraInfo;
  final VoidCallback? onTap;

  const _FeedCard({
    required this.title,
    required this.reportType,
    required this.body,
    required this.photoUrls,
    required this.statusBadge,
    required this.metaIcon,
    required this.metaText,
    required this.metaColor,
    this.trailingBadge,
    this.extraInfo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasMedia = photoUrls.isNotEmpty;
    final isRejected = statusBadge == _StatusBadge.rejected;
    final borderColor = isRejected
        ? const Color(0xFFD7263D).withAlpha(51)
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (hasMedia) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  photoUrls.first,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _mediaPh(),
                ),
              ),
              const SizedBox(width: 12),
            ],

            // Text content
            Expanded(
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
                      if (trailingBadge != null) trailingBadge!,
                    ],
                  ),
                  const SizedBox(height: 6),
                  _TypeChipSmall(type: reportType),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF546E7A),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InfoRow(icon: metaIcon, text: metaText, color: metaColor),
                  if (extraInfo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: extraInfo!,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaPh() => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.image_outlined, color: Color(0xFF90A4AE), size: 28),
  );
}

// ---------------------------------------------------------------------------
// Shared Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _DetailSheet extends StatelessWidget {
  final String title;
  final String reportType;
  final String body;
  final List<String> mediaUrls;
  final String authorName;
  final String address;
  final String submittedAtText;
  final _SheetStatusChip statusChip;
  final Widget? extraBadge;
  final String? rejectionReason;
  final List<Widget> detailRows;

  const _DetailSheet({
    required this.title,
    required this.reportType,
    required this.body,
    required this.mediaUrls,
    required this.authorName,
    required this.address,
    required this.submittedAtText,
    required this.statusChip,
    this.extraBadge,
    this.rejectionReason,
    required this.detailRows,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2B45),
                    ),
                  ),
                ),
                if (extraBadge != null) ...[
                  const SizedBox(width: 8),
                  extraBadge!,
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Type chip + status badge
            Row(
              children: [
                _TypeChipSmall(type: reportType),
                const SizedBox(width: 8),
                statusChip,
              ],
            ),
            const SizedBox(height: 16),

            // Rejection reason banner (only for rejected)
            if (rejectionReason != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD7263D).withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD7263D).withAlpha(51),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REJECTION REASON',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD7263D),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rejectionReason!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF37474F),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Media gallery
            if (mediaUrls.isNotEmpty) ...[
              SizedBox(
                height: mediaUrls.length == 1 ? 200 : 160,
                child: mediaUrls.length == 1
                    ? _MediaItem(url: mediaUrls.first)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: mediaUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => SizedBox(
                          width: 220,
                          child: _MediaItem(url: mediaUrls[i]),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
            ],

            // Divider
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),

            // Description
            if (body.isNotEmpty) ...[
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF546E7A),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF37474F),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Detail rows
            _DetailRow(
              icon: Icons.person_outline,
              label: 'Author',
              value: authorName,
            ),
            if (address.isNotEmpty)
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: address,
              ),
            ...detailRows,

            const SizedBox(height: 20),

            // Close button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF0D47A1).withAlpha(20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Color(0xFF0D47A1),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet Status Chip
// ---------------------------------------------------------------------------

class _SheetStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _SheetStatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Media Item
// ---------------------------------------------------------------------------

class _MediaItem extends StatelessWidget {
  final String url;

  const _MediaItem({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade100,
          child: const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Color(0xFF90A4AE),
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF90A4AE)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF546E7A),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? const Color(0xFF1A2B45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live Badge
// ---------------------------------------------------------------------------

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

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
  const _CardSkeleton();

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
