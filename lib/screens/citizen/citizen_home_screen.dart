import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../citizen/sos_trigger_screen.dart';
import '../citizen/live_map_screen.dart';
import '../citizen/alerts_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SKELETON HELPERS
// ─────────────────────────────────────────────────────────────────────────────

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
          color: Colors.grey.withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CitizenHomeScreen extends StatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  State<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends State<CitizenHomeScreen> {
  // ── colors ──────────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _green = Color(0xFF1FAA59);
  static const _orange = Color(0xFFFF6B00);
  static const _bg = Color(0xFFF5F7FA);
  static const _textSec = Color(0xFF546E7A);

  // ── state ───────────────────────────────────────────────────────────────────
  final Set<String> _dismissedAlerts = {};
  double? _userLat;
  double? _userLng;
  bool _locationLoaded = false;

  // futures (set after location is ready)
  Future<Map<String, dynamic>?>? _rescuerFuture;
  Future<Map<String, dynamic>?>? _evacFuture;

  final _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  // ── location init ────────────────────────────────────────────────────────────
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

  // ── Haversine distance (km) ───────────────────────────────────────────────
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

  // ── fetch nearest on-duty rescuer ─────────────────────────────────────────
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
          'eta_min': ((dist / 40) * 60).round(), // 40 km/h avg
          'count': snap.docs.length,
        };
      }
    }
    return nearest;
  }

  // ── fetch nearest evacuation center ──────────────────────────────────────
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

  // ── pull-to-refresh ────────────────────────────────────────────────────────
  Future<void> _onRefresh() async {
    await _initLocation();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        color: _blue,
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // ── Alert Banners ──────────────────────────────────────────────
            _buildAlertBanners(),

            const SizedBox(height: 16),

            // ── Greeting + SOS CTA ─────────────────────────────────────────
            _buildGreetingAndSOS(auth),

            const SizedBox(height: 16),

            // ── Rescue Teams Card ──────────────────────────────────────────
            _buildRescueTeamsCard(),

            const SizedBox(height: 12),

            // ── Evacuation Center Card ─────────────────────────────────────
            _buildEvacCenterCard(),

            const SizedBox(height: 20),

            // ── Community Feed header ──────────────────────────────────────
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

            // ── Community Feed ─────────────────────────────────────────────
            _buildCommunityFeed(),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
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
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Greeting + SOS ────────────────────────────────────────────────────────
  Widget _buildGreetingAndSOS(AuthProvider auth) {
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
          const SizedBox(height: 16),
          // SOS Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SOSTriggerScreen()),
              ),
              icon: const Icon(Icons.sos_rounded, size: 22),
              label: const Text(
                'SEND SOS REQUEST',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LiveMapScreen()),
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text(
                'View Live Map',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Alert Banners ─────────────────────────────────────────────────────────
  Widget _buildAlertBanners() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.instance.alertsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data!.docs
            .where((d) => !_dismissedAlerts.contains(d.id))
            .toList();

        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final alert = AlertModel.fromMap(data, doc.id);
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
        ? _red.withOpacity(0.08)
        : _orange.withOpacity(0.08);
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
                            color: _blue.withOpacity(0.15),
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
                      color: borderColor.withOpacity(0.8),
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
                color: borderColor.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rescue Teams Card ─────────────────────────────────────────────────────
  Widget _buildRescueTeamsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _rescuerFuture,
        builder: (context, snapshot) {
          return _cardContainer(
            child:
                _locationLoaded &&
                    snapshot.connectionState == ConnectionState.done
                ? _rescuerCardContent(snapshot.data)
                : _rescuerCardSkeleton(),
          );
        },
      ),
    );
  }

  Widget _rescuerCardSkeleton() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.people_alt_rounded, color: _blue, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SkeletonBox(width: 130, height: 14),
            SizedBox(height: 6),
            _SkeletonBox(width: 90, height: 11),
          ],
        ),
        const Spacer(),
        const _SkeletonBox(width: 60, height: 28, radius: 14),
      ],
    );
  }

  Widget _rescuerCardContent(Map<String, dynamic>? data) {
    if (data == null) {
      return _noDataRow(
        icon: Icons.people_alt_rounded,
        iconColor: _textSec,
        title: 'No rescue teams on duty',
        subtitle: 'Check back during an emergency',
      );
    }

    final count = data['count'] as int? ?? 0;
    final name = data['name'] as String? ?? 'Rescue Team';
    final distKm = (data['distance_km'] as double?)?.toStringAsFixed(1) ?? '—';
    final eta = data['eta_min'] as int? ?? 0;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.people_alt_rounded, color: _blue, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF1A237E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$count team${count != 1 ? 's' : ''} on duty · $distKm km away',
                style: const TextStyle(fontSize: 12, color: _textSec),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _etaBadge('~$eta min', _blue),
      ],
    );
  }

  // ── Evac Center Card ──────────────────────────────────────────────────────
  Widget _buildEvacCenterCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _evacFuture,
        builder: (context, snapshot) {
          return _cardContainer(
            child:
                _locationLoaded &&
                    snapshot.connectionState == ConnectionState.done
                ? _evacCardContent(snapshot.data)
                : _evacCardSkeleton(),
          );
        },
      ),
    );
  }

  Widget _evacCardSkeleton() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.home_work_outlined, color: _green, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SkeletonBox(width: 150, height: 14),
            SizedBox(height: 6),
            _SkeletonBox(width: 100, height: 11),
          ],
        ),
        const Spacer(),
        const _SkeletonBox(width: 72, height: 28, radius: 14),
      ],
    );
  }

  Widget _evacCardContent(Map<String, dynamic>? data) {
    if (data == null) {
      return _noDataRow(
        icon: Icons.home_work_outlined,
        iconColor: _textSec,
        title: 'No evacuation centers found',
        subtitle: 'Data may be unavailable',
      );
    }

    final name = data['name'] as String? ?? 'Evacuation Center';
    final distKm = (data['distance_km'] as double?)?.toStringAsFixed(1) ?? '—';
    final slots = data['available_slots'] as int? ?? 0;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.home_work_outlined, color: _green, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF1A237E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$distKm km away',
                style: const TextStyle(fontSize: 12, color: _textSec),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _slotsBadge(slots),
      ],
    );
  }

  // ── Community Feed ────────────────────────────────────────────────────────
  Widget _buildCommunityFeed() {
    return StreamBuilder<QuerySnapshot>(
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const EmptyState(
            icon: Icons.feed_outlined,
            title: 'No community posts yet',
            subtitle: 'Be the first to report something.',
          );
        }

        final docs = snapshot.data!.docs;
        return Column(
          children: docs
              .map(
                (doc) =>
                    _buildFeedCard(doc.data() as Map<String, dynamic>, doc.id),
              )
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

  // ── Shared card helpers ───────────────────────────────────────────────────
  Widget _cardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
        color: color.withOpacity(0.1),
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

  Widget _slotsBadge(int slots) {
    final color = slots > 20
        ? _green
        : slots > 0
        ? _orange
        : _red;
    final label = slots > 0 ? '$slots slots' : 'Full';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
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
            color: iconColor.withOpacity(0.08),
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
