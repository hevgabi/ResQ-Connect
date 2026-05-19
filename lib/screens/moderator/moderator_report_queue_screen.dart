import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/ai_score_chip.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';
import 'moderator_review_detail_screen.dart';

class ModeratorReportQueueScreen extends StatelessWidget {
  const ModeratorReportQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.instance.pendingReportsStream(),
        builder: (context, snapshot) {
          final pendingCount = (snapshot.hasData)
              ? snapshot.data!.docs.length
              : 0;

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                title: Row(
                  children: [
                    const Text(
                      'Review Queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7263D),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                backgroundColor: const Color(0xFF0D47A1),
                floating: true,
                snap: true,
                elevation: 2,
              ),
            ],
            body: _buildBody(context, snapshot),
          );
        },
      ),
      bottomNavigationBar: const ModeratorBottomNav(currentIndex: 0),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _SkeletonLoader();
    }
    if (snapshot.hasError) {
      return ErrorBanner(message: snapshot.error.toString());
    }
    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        iconColor: Color(0xFF1FAA59),
        title: 'No Pending Reports',
        subtitle: 'All reports have been reviewed. Check back later.',
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
        return _ReportQueueCard(reportId: doc.id, data: data);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Report Queue Card
// ---------------------------------------------------------------------------

class _ReportQueueCard extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const _ReportQueueCard({required this.reportId, required this.data});

  @override
  State<_ReportQueueCard> createState() => _ReportQueueCardState();
}

class _ReportQueueCardState extends State<_ReportQueueCard> {
  String _authorName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadAuthor();
  }

  Future<void> _loadAuthor() async {
    final authorId = widget.data['author_id'] as String?;
    if (authorId == null) {
      setState(() => _authorName = 'Unknown');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .get();
      if (mounted) {
        setState(() {
          _authorName = (doc.data()?['display_name'] as String?) ?? 'Unknown';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _authorName = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final mediaUrls = (data['media_urls'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final firstMedia = (mediaUrls != null && mediaUrls.isNotEmpty)
        ? mediaUrls[0]
        : null;
    final reportType = (data['type'] as String?) ?? 'General';
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final aiScore = (data['ai_score'] as num?)?.toInt() ?? 0;

    final locationText = (lat != null && lng != null)
        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
        : 'Location unavailable';

    final timeText = createdAt != null
        ? timeago.format(createdAt)
        : 'Unknown time';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ModeratorReviewDetailScreen(reportId: widget.reportId),
        ),
      ),
      child: Container(
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 100,
                height: 120,
                child: firstMedia != null
                    ? CachedNetworkImage(
                        imageUrl: firstMedia,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: const Color(0xFFECEFF1),
                          child: const Icon(
                            Icons.image,
                            color: Color(0xFF546E7A),
                            size: 32,
                          ),
                        ),
                        errorWidget: (_, __, ___) => _MediaPlaceholder(),
                      )
                    : _MediaPlaceholder(),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type chip + AI score
                    Row(
                      children: [
                        _TypeChip(type: reportType),
                        const Spacer(),
                        AiScoreChip(score: aiScore),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Author
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Color(0xFF546E7A),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _authorName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF37474F),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Location
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Color(0xFF546E7A),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF546E7A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Time
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: Color(0xFF546E7A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Chevron
            const Padding(
              padding: EdgeInsets.only(right: 8, top: 48),
              child: Icon(Icons.chevron_right, color: Color(0xFF546E7A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFECEFF1),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Color(0xFF546E7A),
          size: 32,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;

  const _TypeChip({required this.type});

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
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
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

// ---------------------------------------------------------------------------
// Skeleton Loader
// ---------------------------------------------------------------------------

class _SkeletonLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _shimmer(60, 14),
                    _shimmer(120, 12),
                    _shimmer(100, 12),
                    _shimmer(80, 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmer(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
