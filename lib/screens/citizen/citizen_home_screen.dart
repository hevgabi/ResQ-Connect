import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/alert_model.dart';
import '../../models/evac_center_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/empty_state.dart';
import '../citizen/alerts_screen.dart';
import '../citizen/emergency_hotlines_screen.dart';
import '../citizen/create_post_screen.dart';
import '../settings/hamburger_menu_screen.dart';

// =============================================================================
// SKELETON BOX
// =============================================================================

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// =============================================================================
// SLIDE-IN TOAST NOTIFICATION
// =============================================================================

class _NotifToast extends StatefulWidget {
  final String title;
  final String message;
  final bool isApproved;
  final VoidCallback onDismiss;

  const _NotifToast({
    required this.title,
    required this.message,
    required this.isApproved,
    required this.onDismiss,
  });

  @override
  State<_NotifToast> createState() => _NotifToastState();
}

class _NotifToastState extends State<_NotifToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);

    _ctrl.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isApproved
        ? const Color(0xFF1FAA59)
        : const Color(0xFFD7263D);
    final icon = widget.isApproved
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF546E7A),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.close, size: 16, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CITIZEN HOME SCREEN
// =============================================================================

class CitizenHomeScreen extends StatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  State<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends State<CitizenHomeScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _green = Color(0xFF1FAA59);
  static const _orange = Color(0xFFFF6B00);
  static const _bg = Color(0xFFF5F7FA);
  static const _textSec = Color(0xFF546E7A);

  final Set<String> _dismissedAlerts = {};
  double? _userLat;
  double? _userLng;
  bool _locationLoaded = false;

  Future<Map<String, dynamic>?>? _rescuerFuture;
  Future<Map<String, dynamic>?>? _evacFuture;

  final _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  // ── Notification toast state ─────────────────────────────────────────────
  StreamSubscription<List<Map<String, dynamic>>>? _notifSub;
  final Set<String> _seenNotifIds = {};
  // Queue of toasts to show one at a time
  final List<Map<String, dynamic>> _toastQueue = [];
  bool _showingToast = false;
  Map<String, dynamic>? _currentToast;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _listenNotifications();
  }

  void _listenNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _notifSub = FirestoreService.instance
        .citizenNotificationsStream(uid)
        .listen((posts) {
          for (final post in posts) {
            final id = post['id'] as String;
            if (!_seenNotifIds.contains(id)) {
              _seenNotifIds.add(id);
              _toastQueue.add(post);
            }
          }
          if (!_showingToast && _toastQueue.isNotEmpty) {
            _showNextToast();
          }
        });
  }

  void _showNextToast() {
    if (_toastQueue.isEmpty || !mounted) return;
    setState(() {
      _showingToast = true;
      _currentToast = _toastQueue.removeAt(0);
    });
  }

  void _dismissToast() {
    if (!mounted) return;
    final id = _currentToast?['id'] as String?;
    if (id != null) {
      FirestoreService.instance.markReportNotifRead(id);
    }
    setState(() {
      _showingToast = false;
      _currentToast = null;
    });
    // Show next toast if any, after a short gap
    if (_toastQueue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), _showNextToast);
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.instance.getCurrentPosition();
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    if (pos != null && auth.user != null) {
      final uid = auth.user!.uid;
      await FirestoreService.instance.updateUserLocation(
        uid,
        pos.latitude,
        pos.longitude,
      );
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _locationLoaded = true;
        _rescuerFuture = _fetchNearestRescuer();
        _evacFuture = _fetchNearestEvacCenter();
      });
    } else {
      setState(() => _locationLoaded = true);
    }
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double d) => d * pi / 180;

  Future<Map<String, dynamic>?> _fetchNearestRescuer() async {
    if (_userLat == null || _userLng == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('rescuers')
        .where('is_on_duty', isEqualTo: true)
        .get();

    if (snap.docs.isEmpty) return null;

    Map<String, dynamic>? nearest;
    double minDist = double.infinity;

    for (final doc in snap.docs) {
      final d = doc.data();
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final dist = _haversine(_userLat!, _userLng!, lat, lng);
      if (dist < minDist) {
        minDist = dist;
        nearest = {
          'name': d['team_name'] ?? d['name'] ?? 'Rescue Team',
          'distance_km': dist,
          'eta_min': ((dist / 40) * 60).round(),
          'count': snap.docs.length,
        };
      }
    }
    return nearest;
  }

  Future<Map<String, dynamic>?> _fetchNearestEvacCenter() async {
    if (_userLat == null || _userLng == null) return null;
    final snap = await FirebaseFirestore.instance
        .collection('evacuation_centers')
        .get();

    if (snap.docs.isEmpty) return null;

    Map<String, dynamic>? nearest;
    double minDist = double.infinity;

    for (final doc in snap.docs) {
      final d = doc.data();
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final dist = _haversine(_userLat!, _userLng!, lat, lng);
      if (dist < minDist) {
        minDist = dist;
        final total = (d['total_slots'] as num?)?.toInt() ?? 0;
        final occupied = (d['occupied_slots'] as num?)?.toInt() ?? 0;
        nearest = {
          'name': d['name'] ?? 'Evacuation Center',
          'distance_km': dist,
          'available_slots': total - occupied,
        };
      }
    }
    return nearest;
  }

  Future<void> _onRefresh() async {
    await _initLocation();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          RefreshIndicator(
            key: _refreshIndicatorKey,
            color: _blue,
            onRefresh: _onRefresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _buildAlertBanners(),
                const SizedBox(height: 16),
                _buildGreeting(auth),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                _buildPostComposer(auth),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Community Feed',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text(
                          'See all',
                          style: TextStyle(color: _blue, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _buildCommunityFeed(),
              ],
            ),
          ),

          // ── Slide-in toast overlay ───────────────────────────────────────
          if (_showingToast && _currentToast != null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: _buildToast(_currentToast!),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildToast(Map<String, dynamic> post) {
    final status = post['status'] as String? ?? '';
    final isApproved = status == 'published';
    final postLabel = (post['title'] as String?)?.isNotEmpty == true
        ? post['title'] as String
        : (post['type'] as String? ?? 'Your post');
    final title = isApproved ? 'Post Approved' : 'Post Not Approved';
    final message = isApproved
        ? '"$postLabel" has been published to the community feed.'
        : '"$postLabel" was not approved. Reason: ${post['rejection_reason'] ?? 'No reason given.'}';

    return _NotifToast(
      title: title,
      message: message,
      isApproved: isApproved,
      onDismiss: _dismissToast,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: false,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'ResQConnect',
            style: TextStyle(
              color: _blue,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: Color(0xFF37474F),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertsScreen()),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF37474F)),
          tooltip: 'Menu',
          onPressed: () => _openHamburgerMenu(context),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _openHamburgerMenu(BuildContext context) {
    showHamburgerMenu(context, role: HamburgerRole.citizen);
  }

  Widget _buildGreeting(AuthProvider auth) {
    final name = auth.user?.displayName?.split(' ').first ?? 'Citizen';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $name 👋',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Stay safe. We\'re here to help.',
            style: TextStyle(fontSize: 14, color: _textSec),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanners() {
    return StreamBuilder<List<AlertModel>>(
      stream: FirestoreService.instance.alertsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final alerts = snapshot.data!
            .where((a) => !_dismissedAlerts.contains(a.id))
            .toList();

        if (alerts.isEmpty) return const SizedBox.shrink();

        return Column(
          children: alerts.map((alert) {
            return _buildSingleAlertBanner(alert);
          }).toList(),
        );
      },
    );
  }

  Widget _buildSingleAlertBanner(AlertModel alert) {
    final isCritical = alert.severity == 'critical';
    final isWeather = alert.type == 'weather';
    final bannerColor = isCritical
        ? _red.withValues(alpha: 0.08)
        : _orange.withValues(alpha: 0.08);
    final borderColor = isCritical ? _red : _orange;
    final iconData = isCritical
        ? Icons.warning_rounded
        : Icons.info_outline_rounded;

    return Dismissible(
      key: Key('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() => _dismissedAlerts.add(alert.id));
      },
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.grey.shade300,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.close, color: Colors.grey),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, color: borderColor, size: 20),
            const SizedBox(width: 10),
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
                            color: borderColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isWeather)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.thunderstorm_outlined,
                                size: 12,
                                color: _blue,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Typhoon Signal',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: borderColor.withValues(alpha: 0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _dismissedAlerts.add(alert.id)),
              child: Icon(
                Icons.close,
                size: 16,
                color: borderColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityFeed() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.communityFeedStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _cardContainer(child: _feedSkeleton()),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.feed_outlined,
            title: 'No community posts yet',
            subtitle: 'Be the first to report something.',
          );
        }

        final items = snapshot.data!;
        return Column(
          children: items
              .map((item) => _buildFeedCard(item, item['id'] as String))
              .toList(),
        );
      },
    );
  }

  Widget _feedSkeleton() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SkeletonBox(width: 40, height: 40, radius: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SkeletonBox(width: 120, height: 12),
              SizedBox(height: 6),
              _SkeletonBox(width: double.infinity, height: 11),
              SizedBox(height: 4),
              _SkeletonBox(width: 200, height: 11),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> data, String id) {
    final name = (data['author_name'] as String?) ?? 'Anonymous';
    final text = (data['text'] as String?) ?? '';
    final likes = (data['likes'] as num?)?.toInt() ?? 0;
    final comments = (data['comments'] as num?)?.toInt() ?? 0;
    final ts = (data['created_at'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? timeago.format(ts) : '';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : '?';
    final avatarColors = [
      const Color(0xFF0D47A1),
      const Color(0xFF1565C0),
      const Color(0xFF283593),
      const Color(0xFF1FAA59),
      const Color(0xFF00838F),
    ];
    final avatarColor = avatarColors[name.hashCode.abs() % avatarColors.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _cardContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: avatarColor,
                  radius: 20,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 11, color: _textSec),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF37474F),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _feedAction(
                  icon: Icons.thumb_up_alt_outlined,
                  label: '$likes',
                  onTap: () {},
                ),
                const SizedBox(width: 16),
                _feedAction(
                  icon: Icons.comment_outlined,
                  label: '$comments',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _etaBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _noDataRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: _textSec,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: _textSec),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPostComposer(AuthProvider auth) {
    final name = auth.user?.displayName?.split(' ').first ?? 'Citizen';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _cardContainer(
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF0D47A1),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _showPostDialog(context, auth),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: const Text(
                    "What's on your mind?",
                    style: TextStyle(fontSize: 14, color: Color(0xFF90A4AE)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _showPostDialog(context, auth),
              child: const Icon(
                Icons.image_outlined,
                color: Color(0xFF546E7A),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostDialog(BuildContext context, AuthProvider auth) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
  }

  Widget _feedAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: _textSec),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: _textSec)),
        ],
      ),
    );
  }
}
