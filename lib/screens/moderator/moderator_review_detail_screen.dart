import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/ai_score_chip.dart';

class ModeratorReviewDetailScreen extends StatefulWidget {
  final String reportId;

  const ModeratorReviewDetailScreen({super.key, required this.reportId});

  @override
  State<ModeratorReviewDetailScreen> createState() =>
      _ModeratorReviewDetailScreenState();
}

class _ModeratorReviewDetailScreenState
    extends State<ModeratorReviewDetailScreen> {
  Map<String, dynamic>? _reportData;
  String _authorName = 'Loading...';
  bool _isLoading = true;
  bool _isActing = false;
  String? _error;
  int _selectedMediaIndex = 0;
  final PageController _pageController = PageController();
  final TextEditingController _rejectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _rejectionController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.reportId)
          .get();

      if (!doc.exists) {
        setState(() {
          _error = 'Report not found.';
          _isLoading = false;
        });
        return;
      }

      final data = doc.data()!;
      setState(() {
        _reportData = data;
        _isLoading = false;
      });

      // Load author name
      final authorId = data['author_id'] as String?;
      if (authorId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .get();
        if (mounted) {
          setState(() {
            _authorName =
                (userDoc.data()?['display_name'] as String?) ?? 'Unknown';
          });
        }
      } else {
        setState(() => _authorName = 'Unknown');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _publish() async {
    final authProvider = context.read<AuthProvider>();
    final uid = authProvider.user?.uid;
    if (uid == null) return;

    setState(() => _isActing = true);
    try {
      await FirestoreService.instance.publishReport(widget.reportId, uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Published to community feed'),
            backgroundColor: Color(0xFF1FAA59),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _showRejectDialog() async {
    _rejectionController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reject Report',
          style: TextStyle(
            color: Color(0xFFD7263D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for rejecting this report:',
              style: TextStyle(color: Color(0xFF546E7A)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter rejection reason...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFD7263D),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF546E7A)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD7263D),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final reason = _rejectionController.text.trim();
      if (reason.isEmpty) return;
      await _reject(reason);
    }
  }

  Future<void> _reject(String reason) async {
    final authProvider = context.read<AuthProvider>();
    final uid = authProvider.user?.uid;
    if (uid == null) return;

    setState(() => _isActing = true);
    try {
      await FirestoreService.instance.updateReport(widget.reportId, {
        'status': 'rejected',
        'rejection_reason': reason,
        'reviewed_by': uid,
        'reviewed_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report rejected'),
            backgroundColor: Color(0xFFD7263D),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        title: const Text(
          'Review Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFD7263D)),
              ),
            )
          : _buildBody(),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionBar(),
          const ModeratorBottomNav(currentIndex: 0),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final data = _reportData!;
    final mediaUrls =
        (data['media_urls'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final reportType = (data['type'] as String?) ?? 'General';
    final description = (data['description'] as String?) ?? '';
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final aiScore = (data['ai_score'] as num?)?.toInt() ?? 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Media Gallery
          if (mediaUrls.isNotEmpty) _MediaGallery(mediaUrls: mediaUrls),

          const SizedBox(height: 16),

          // 2. Metadata Card
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Report Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 12),
                _MetaRow(
                  icon: Icons.label_outline,
                  label: 'Type',
                  value: reportType.replaceAll('_', ' ').toUpperCase(),
                ),
                _MetaRow(
                  icon: Icons.person_outline,
                  label: 'Author',
                  value: _authorName,
                ),
                if (createdAt != null)
                  _MetaRow(
                    icon: Icons.access_time,
                    label: 'Submitted',
                    value: DateFormat('MMM d, yyyy • h:mm a').format(createdAt),
                  ),
                if (lat != null && lng != null)
                  _MetaRow(
                    icon: Icons.location_on_outlined,
                    label: 'Coordinates',
                    value:
                        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 3. Description
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description.isNotEmpty
                      ? description
                      : 'No description provided.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF37474F),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 4. AI Analysis
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'AI Analysis',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AiScoreChip(score: aiScore),
                  ],
                ),
                const SizedBox(height: 10),
                _AiScoreExplanation(score: aiScore),
              ],
            ),
          ),

          // Bottom padding for sticky buttons
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Reject button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isActing ? null : _showRejectDialog,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD7263D),
                side: const BorderSide(color: Color(0xFFD7263D)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Publish button
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _isActing ? null : _publish,
              icon: _isActing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.publish, size: 18),
              label: Text(_isActing ? 'Publishing...' : 'Publish'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1FAA59),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Media Gallery
// ---------------------------------------------------------------------------

class _MediaGallery extends StatefulWidget {
  final List<String> mediaUrls;

  const _MediaGallery({required this.mediaUrls});

  @override
  State<_MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<_MediaGallery> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  final ScrollController _thumbnailController = ScrollController();

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main view
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaUrls.length,
            onPageChanged: (index) {
              setState(() => _selectedIndex = index);
            },
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: widget.mediaUrls[index],
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFFECEFF1),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFFECEFF1),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF546E7A),
                      size: 48,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Thumbnail strip
        if (widget.mediaUrls.length > 1)
          Container(
            height: 64,
            color: Colors.black87,
            child: ListView.builder(
              controller: _thumbnailController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: widget.mediaUrls.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedIndex;
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    setState(() => _selectedIndex = index);
                  },
                  child: Container(
                    width: 48,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1FAA59)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: widget.mediaUrls[index],
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade700),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF546E7A)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF546E7A)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF37474F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiScoreExplanation extends StatelessWidget {
  final int score;

  const _AiScoreExplanation({required this.score});

  String get _explanation {
    if (score >= 80) {
      return 'HIGH CREDIBILITY — This report contains strong indicators of a genuine emergency. '
          'The description is detailed, uses relevant disaster keywords, and includes supporting media. '
          'Recommend publishing to community feed.';
    } else if (score >= 50) {
      return 'MODERATE CREDIBILITY — This report shows some indicators of a real incident but may '
          'lack detail or media evidence. Review carefully before publishing. '
          'Consider requesting more information if needed.';
    } else {
      return 'LOW CREDIBILITY — This report has characteristics that suggest it may be inaccurate, '
          'incomplete, or potentially a test submission. Exercise caution. '
          'Consider rejecting unless additional context justifies publishing.';
    }
  }

  Color get _color {
    if (score >= 80) return const Color(0xFF1FAA59);
    if (score >= 50) return const Color(0xFFFF6B00);
    return const Color(0xFFD7263D);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _explanation,
        style: TextStyle(fontSize: 13, color: _color, height: 1.5),
      ),
    );
  }
}
