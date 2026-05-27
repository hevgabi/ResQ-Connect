import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/alert_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../settings/hamburger_menu_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _orange = Color(0xFFFF6B00);
  static const _green = Color(0xFF1FAA59);
  static const _bg = Color(0xFFF5F7FA);
  static const _textSec = Color(0xFF546E7A);

  late final TabController _tabs;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Locally track which alert IDs have been seen this session
  Set<String> _seenAlertIds = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    // Load persisted seen IDs, then listen for tab switches to mark seen
    _loadSeenAlerts();
    _tabs.addListener(_onTabChanged);
  }

  Future<void> _loadSeenAlerts() async {
    final uid = _uid;
    if (uid == null) return;
    final ids = await FirestoreService.instance.getSeenAlertIds(uid);
    if (mounted) setState(() => _seenAlertIds = ids);
  }

  void _onTabChanged() {
    // When the user switches to the Community Alerts tab, mark all current
    // alerts as seen so the home-screen dot clears
    if (_tabs.index == 1) {
      _markAllAlertsSeen();
    }
  }

  Future<void> _markAllAlertsSeen() async {
    final uid = _uid;
    if (uid == null) return;
    // Get the latest alerts and persist their IDs
    FirestoreService.instance.alertsStream().first.then((alerts) {
      final ids = alerts.map((a) => a.id).toList();
      if (ids.isNotEmpty) {
        FirestoreService.instance.markAlertsAsSeen(uid, ids);
        if (mounted) setState(() => _seenAlertIds = ids.toSet());
      }
    });
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

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
        bottom: TabBar(
          controller: _tabs,
          labelColor: _blue,
          unselectedLabelColor: _textSec,
          indicatorColor: _blue,
          indicatorWeight: 3,
          labelStyle:
          const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'My Notifications'),
            Tab(text: 'Community Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPersonalTab(),
          _buildCommunityTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: Personal Notifications ────────────────────────────────────────

  Widget _buildPersonalTab() {
    final uid = _uid;
    if (uid == null) {
      return const Center(child: Text('Not logged in.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            icon: Icons.article_outlined,
            label: 'Post Status',
            color: _blue,
            child: _buildPostNotifications(uid),
          ),
          const SizedBox(height: 20),
          _buildSection(
            icon: Icons.hourglass_top_rounded,
            label: 'Pending Review',
            color: _orange,
            child: _buildPendingPosts(uid),
          ),
          const SizedBox(height: 20),
          _buildSection(
            icon: Icons.sos_rounded,
            label: 'SOS Updates',
            color: _red,
            child: _buildSosNotifications(uid),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String label,
    required Color color,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  // ── Post Approved / Rejected ───────────────────────────────────────────────

  Widget _buildPostNotifications(String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.citizenNotificationsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shimmerCard();
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) return _emptyChip('No post updates yet.');
        return Column(
          children: posts.map((p) => _buildPostNotifCard(uid, p)).toList(),
        );
      },
    );
  }

  Widget _buildPostNotifCard(String uid, Map<String, dynamic> post) {
    final status = post['status'] as String? ?? '';
    final isApproved = status == 'published';
    final isRead = post['notif_read'] as bool? ?? true;
    final color = isApproved ? _green : _red;
    final icon =
    isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final title = isApproved ? 'Post Approved' : 'Post Rejected';
    final postLabel = _postTitle(post);
    final message = isApproved
        ? '"$postLabel" is now live on the community feed.'
        : '"$postLabel" was not approved. ${_rejectionReason(post)}';
    final timeStr =
    _formatTime(post['reviewed_at'] ?? post['published_at']);

    return _notifCard(
      color: color,
      icon: icon,
      title: title,
      message: message,
      timeStr: timeStr,
      isRead: isRead,
      onTap: () {
        if (!isRead) {
          FirestoreService.instance
              .markReportNotifRead(post['id'] as String);
        }
        _showDetailSheet(
          context,
          color: color,
          icon: icon,
          title: title,
          rows: [
            _DetailRow('Post', postLabel),
            _DetailRow('Status',
                isApproved ? 'Published ✓' : 'Rejected ✗'),
            if (!isApproved)
              _DetailRow('Reason', _rejectionReason(post)),
            if (timeStr.isNotEmpty) _DetailRow('When', timeStr),
          ],
          note: isApproved
              ? 'Your post is now visible to everyone in the community feed.'
              : 'You may edit and resubmit your post for review.',
        );
      },
    );
  }

  // ── Pending Posts ──────────────────────────────────────────────────────────

  Widget _buildPendingPosts(String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.citizenPendingPostsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shimmerCard();
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) return _emptyChip('No posts pending review.');
        return Column(
          children: posts.map((p) => _buildPendingCard(p)).toList(),
        );
      },
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> post) {
    final postLabel = _postTitle(post);
    final timeStr = _formatTime(post['created_at']);

    return _notifCard(
      color: _orange,
      icon: Icons.hourglass_top_rounded,
      title: 'Awaiting Moderator Review',
      message: '"$postLabel" has been submitted and is pending approval.',
      timeStr: timeStr,
      isRead: true,
      onTap: () {
        _showDetailSheet(
          context,
          color: _orange,
          icon: Icons.hourglass_top_rounded,
          title: 'Awaiting Moderator Review',
          rows: [
            _DetailRow('Post', postLabel),
            _DetailRow('Status', 'Pending'),
            if (timeStr.isNotEmpty) _DetailRow('Submitted', timeStr),
          ],
          note:
          'A moderator will review your post shortly. You\'ll be notified once a decision is made.',
        );
      },
    );
  }

  // ── SOS Updates ───────────────────────────────────────────────────────────

  Widget _buildSosNotifications(String uid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.citizenSosNotificationsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shimmerCard();
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return _emptyChip('No SOS updates.');
        return Column(
          children: items.map((s) => _buildSosNotifCard(uid, s)).toList(),
        );
      },
    );
  }

  Widget _buildSosNotifCard(String uid, Map<String, dynamic> sos) {
    final status = sos['status'] as String? ?? '';
    final isRead = sos['sos_notif_read'] as bool? ?? true;

    Color color;
    IconData icon;
    String title;
    String message;
    String note;

    final rescuerName =
        sos['assigned_rescuer_name'] as String? ?? 'A rescuer';
    final address = sos['address'] as String? ?? 'your location';

    switch (status) {
      case 'assigned':
        color = _blue;
        icon = Icons.directions_run_rounded;
        title = 'Rescuer Assigned';
        message =
        '$rescuerName has been assigned to your SOS and is on the way.';
        note = 'Please stay at $address and keep your phone accessible.';
        break;
      case 'resolved':
        color = _green;
        icon = Icons.verified_rounded;
        title = 'SOS Resolved';
        message = 'Your SOS request has been marked as resolved. Stay safe!';
        note =
        'If you still need help, please submit a new SOS request immediately.';
        break;
      case 'cancelled':
        color = _textSec;
        icon = Icons.cancel_outlined;
        title = 'SOS Cancelled';
        message = 'Your SOS request was cancelled.';
        note =
        'If this was a mistake or you still need help, submit a new SOS request.';
        break;
      default:
        color = _orange;
        icon = Icons.info_outline_rounded;
        title = 'SOS Update';
        message = 'Your SOS status changed to "$status".';
        note = '';
    }

    final timeStr = _formatTime(sos['updated_at']);

    return _notifCard(
      color: color,
      icon: icon,
      title: title,
      message: message,
      timeStr: timeStr,
      isRead: isRead,
      onTap: () {
        if (!isRead) {
          FirestoreService.instance.markSosNotifRead(sos['id'] as String);
        }
        _showDetailSheet(
          context,
          color: color,
          icon: icon,
          title: title,
          rows: [
            _DetailRow('Status', status[0].toUpperCase() + status.substring(1)),
            if (status == 'assigned')
              _DetailRow('Rescuer', rescuerName),
            _DetailRow('Location', address),
            if (timeStr.isNotEmpty) _DetailRow('Updated', timeStr),
          ],
          note: note,
        );
      },
    );
  }

  // ─── TAB 2: Community Alerts ───────────────────────────────────────────────

  Widget _buildCommunityTab() {
    return StreamBuilder<List<AlertModel>>(
      stream: FirestoreService.instance.alertsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }

        final alerts = snapshot.data ?? [];

        // Mark alerts as seen once, without calling setState inside build
        if (_tabs.index == 1 && alerts.isNotEmpty) {
          final uid = _uid;
          if (uid != null) {
            final ids = alerts.map((a) => a.id).toList();
            final unseenIds =
            ids.where((id) => !_seenAlertIds.contains(id)).toList();
            if (unseenIds.isNotEmpty) {
              FirestoreService.instance.markAlertsAsSeen(uid, ids);
              // Schedule the setState outside of the build phase
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _seenAlertIds = ids.toSet());
                }
              });
            }
          }
        }

        if (alerts.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_off_outlined,
            title: 'No alerts right now',
            subtitle: 'You\'re all caught up!',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: alerts.map((alert) {
            final isNew = !_seenAlertIds.contains(alert.id);
            Color borderColor;
            IconData iconData;

            if (alert.severity == 'critical') {
              borderColor = _red;
              iconData = Icons.warning_rounded;
            } else if (alert.severity == 'warning') {
              borderColor = _orange;
              iconData = Icons.warning_amber_rounded;
            } else {
              borderColor = _blue;
              iconData = Icons.info_outline_rounded;
            }

            final timeStr = alert.createdAt != null
                ? timeago.format(alert.createdAt!)
                : '';

            return GestureDetector(
              onTap: () => _showAlertDetailSheet(context, alert,
                  borderColor: borderColor, iconData: iconData),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isNew
                      ? borderColor.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                      left: BorderSide(color: borderColor, width: 4)),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(iconData, color: borderColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  alert.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: borderColor,
                                  ),
                                ),
                              ),
                              if (isNew)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: borderColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (alert.region != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                    borderColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    alert.region!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: borderColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                              style: const TextStyle(
                                  fontSize: 11, color: _textSec),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400, size: 20),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ─── Detail bottom sheets ──────────────────────────────────────────────────

  void _showDetailSheet(
      BuildContext context, {
        required Color color,
        required IconData icon,
        required String title,
        required List<_DetailRow> rows,
        required String note,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        color: color,
        icon: icon,
        title: title,
        rows: rows,
        note: note,
      ),
    );
  }

  void _showAlertDetailSheet(
      BuildContext context,
      AlertModel alert, {
        required Color borderColor,
        required IconData iconData,
      }) {
    final timeStr =
    alert.createdAt != null ? timeago.format(alert.createdAt!) : '';
    final expiresStr =
    alert.expiresAt != null ? timeago.format(alert.expiresAt!) : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        color: borderColor,
        icon: iconData,
        title: alert.title,
        rows: [
          _DetailRow('Severity', alert.severity[0].toUpperCase() +
              alert.severity.substring(1)),
          if (alert.region != null) _DetailRow('Region', alert.region!),
          if (alert.type != null) _DetailRow('Type', alert.type!),
          if (timeStr.isNotEmpty) _DetailRow('Issued', timeStr),
          if (expiresStr.isNotEmpty) _DetailRow('Expires', expiresStr),
        ],
        note: alert.message,
        noteIsBody: true,
      ),
    );
  }

  // ─── Shared UI helpers ─────────────────────────────────────────────────────

  Widget _notifCard({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    required String timeStr,
    required bool isRead,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
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
                    Text(timeStr,
                        style:
                        const TextStyle(fontSize: 11, color: _textSec)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _emptyChip(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 13, color: _textSec)),
    );
  }

  Widget _shimmerCard() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  // ─── Data helpers ──────────────────────────────────────────────────────────

  String _postTitle(Map<String, dynamic> post) {
    final title = post['title'] as String?;
    if (title != null && title.isNotEmpty) return title;
    final text = post['text'] as String?;
    if (text != null && text.isNotEmpty) {
      return text.length > 40 ? '${text.substring(0, 40)}…' : text;
    }
    return post['type'] as String? ?? 'Your post';
  }

  String _rejectionReason(Map<String, dynamic> post) {
    final reason = post['rejection_reason'] as String?;
    if (reason != null && reason.isNotEmpty) return 'Reason: $reason';
    return 'No reason provided.';
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = (timestamp as dynamic).toDate() as DateTime;
      return timeago.format(dt);
    } catch (_) {
      return '';
    }
  }
}

// ─── Data class for detail rows ────────────────────────────────────────────

class _DetailRow {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
}

// ─── Detail bottom sheet widget ────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final List<_DetailRow> rows;
  final String note;
  final bool noteIsBody;

  const _DetailSheet({
    required this.color,
    required this.icon,
    required this.title,
    required this.rows,
    required this.note,
    this.noteIsBody = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 20),

          // Icon + title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Divider
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),

          // Detail rows
          ...rows.map(
                (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF546E7A),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1A237E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Note / body
          if (note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: noteIsBody
                    ? color.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: noteIsBody
                      ? color.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                ),
              ),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 13,
                  color: noteIsBody ? color : const Color(0xFF546E7A),
                  height: 1.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Close button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: color.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}