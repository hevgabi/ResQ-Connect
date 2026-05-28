import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';

import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/broadcast_alert_overlay.dart';

class ModeratorProfileScreen extends StatefulWidget {
  const ModeratorProfileScreen({super.key});

  @override
  State<ModeratorProfileScreen> createState() => _ModeratorProfileScreenState();
}

class _ModeratorProfileScreenState extends State<ModeratorProfileScreen>
    with SingleTickerProviderStateMixin {
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  late TabController _tabController;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  // Stats
  int _totalPublished = 0;
  int _totalRejected = 0;
  int _totalPending = 0;

  // FB-style palette
  static const _blue = Color(0xFF1877F2);
  static const _surface = Color(0xFFF0F2F5);
  static const _cardBg = Colors.white;
  static const _textPrimary = Color(0xFF050505);
  static const _textSecondary = Color(0xFF65676B);
  static const _divider = Color(0xFFE4E6EA);

  // Moderator accent
  static const _modPurple = Color(0xFF6A1B9A);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final publishedSnap = await FirebaseFirestore.instance
          .collection('reports')
          .where('moderator_id', isEqualTo: uid)
          .where('status', isEqualTo: 'published')
          .count()
          .get();

      final rejectedSnap = await FirebaseFirestore.instance
          .collection('reports')
          .where('reviewed_by', isEqualTo: uid)
          .where('status', isEqualTo: 'rejected')
          .count()
          .get();

      final pendingSnap = await FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();

      if (!mounted) return;
      final uData = userSnap.data();
      setState(() {
        _userData = uData;
        if (!_editing) {
          _firstNameController.text = uData?['first_name'] ?? '';
          _lastNameController.text = uData?['last_name'] ?? '';
          _phoneController.text = uData?['phone'] ?? '';
        }
        _totalPublished = publishedSnap.count ?? 0;
        _totalRejected = rejectedSnap.count ?? 0;
        _totalPending = pendingSnap.count ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await FirestoreService.instance.updateUser(uid, {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'display_name':
            '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                .trim(),
      });
      if (mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated'),
            backgroundColor: Color(0xFF1FAA59),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _initials() {
    final first = _userData?['first_name'] ?? '';
    final last = _userData?['last_name'] ?? '';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first[0].toUpperCase();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'M';
  }

  String _fullName() {
    final first = _userData?['first_name'] ?? '';
    final last = _userData?['last_name'] ?? '';
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : 'Moderator';
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'My Profile',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          automaticallyImplyLeading: false,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () =>
                  showHamburgerMenu(context, role: HamburgerRole.moderator),
            ),
          ],
        ),
        body: Stack(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(child: _buildFbHeader()),
                      SliverToBoxAdapter(child: _buildTabBar()),
                    ],
                    body: TabBarView(
                      controller: _tabController,
                      children: [_buildActivityTab(), _buildAboutTab()],
                    ),
                  ),
            const BroadcastAlertOverlay(topOffset: 12),
          ],
        ),
        bottomNavigationBar: const ModeratorBottomNav(currentIndex: 5),
      ),
    );
  }

  // ─── Facebook-style Header ────────────────────────────────────────────────

  Widget _buildFbHeader() {
    final initials = _initials();
    final name = _fullName();
    final memberSince = (_userData?['created_at'] as Timestamp?)?.toDate();

    return Container(
      color: _cardBg,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomLeft,
            children: [
              // Cover gradient — purple for moderators
              Container(
                height: 140,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A0E78), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: CustomPaint(painter: _WavePainter()),
              ),
              // Avatar
              Positioned(
                bottom: -36,
                left: 16,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _cardBg, width: 4),
                  ),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: _modPurple.withValues(alpha: 0.2),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _modPurple,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _modPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'MODERATOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _modPurple,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (memberSince != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Member since ${_formatDate(memberSince)}',
                    style: const TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Quick stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.check_circle_outline,
                  label: '$_totalPublished Published',
                  color: const Color(0xFF1FAA59),
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: Icons.cancel_outlined,
                  label: '$_totalRejected Rejected',
                  color: const Color(0xFFD7263D),
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: Icons.pending_actions_outlined,
                  label: '$_totalPending Pending',
                  color: const Color(0xFFFF6B00),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _divider),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _cardBg,
      child: TabBar(
        controller: _tabController,
        labelColor: _blue,
        unselectedLabelColor: _textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        indicatorColor: _blue,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Activity'),
          Tab(text: 'About'),
        ],
      ),
    );
  }

  // ─── Activity Tab ─────────────────────────────────────────────────────────

  Widget _buildActivityTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _blue,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .where('reviewed_by', isEqualTo: uid)
            .orderBy('updated_at', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(
              Icons.fact_check_outlined,
              'No reviewed reports yet.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final status = (data['status'] as String?) ?? 'pending';
              final ts = (data['updated_at'] as Timestamp?)?.toDate();
              final timeStr = ts != null ? _formatTimeAgo(ts) : '';
              final title =
                  (data['title'] as String?) ??
                  (data['type'] as String?) ??
                  'Report';

              return Container(
                color: _cardBg,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _reportStatusColor(
                          status,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.article_outlined,
                        color: _reportStatusColor(status),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (timeStr.isNotEmpty)
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _statusPill(status),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ─── About Tab ─────────────────────────────────────────────────────────────

  Widget _buildAboutTab() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Stats cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _FullStatCard(
                label: 'Published',
                value: '$_totalPublished',
                color: const Color(0xFF1FAA59),
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _FullStatCard(
                label: 'Rejected',
                value: '$_totalRejected',
                color: const Color(0xFFD7263D),
                icon: Icons.cancel_outlined,
              ),
              const SizedBox(width: 8),
              _FullStatCard(
                label: 'Pending',
                value: '$_totalPending',
                color: const Color(0xFFFF6B00),
                icon: Icons.pending_actions_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Personal info
        Container(
          color: _cardBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Personal Info',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: _textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (_editing) {
                        _saveProfile();
                      } else {
                        setState(() => _editing = true);
                      }
                    },
                    child: Text(
                      _editing ? 'Save' : 'Edit',
                      style: const TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow(
                Icons.person_outline,
                'First Name',
                _firstNameController,
                _editing,
              ),
              _infoRow(
                Icons.badge_outlined,
                'Last Name',
                _lastNameController,
                _editing,
              ),
              _infoRow(
                Icons.phone_outlined,
                'Phone',
                _phoneController,
                _editing,
                keyboardType: TextInputType.phone,
              ),
              _readonlyRow(Icons.email_outlined, 'Email', email),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Shared helpers ──────────────────────────────────────────────────────

  Widget _emptyState(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: _textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    TextEditingController controller,
    bool editing, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: _textSecondary),
                ),
                const SizedBox(height: 2),
                editing
                    ? TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: _modPurple,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      )
                    : Text(
                        controller.text.isEmpty ? 'Not set' : controller.text,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readonlyRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: _textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : 'Not set',
                  style: const TextStyle(fontSize: 15, color: _textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _reportStatusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: _reportStatusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _reportStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return const Color(0xFF1FAA59);
      case 'rejected':
        return const Color(0xFFD7263D);
      case 'pending':
        return const Color(0xFFFF6B00);
      default:
        return _textSecondary;
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── Stat chip (header row) ──────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Full stat card (About tab) ───────────────────────────────────────────────

class _FullStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _FullStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cover wave painter ───────────────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.4,
        size.width * 0.5,
        size.height * 0.65,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.9,
        size.width,
        size.height * 0.55,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(0, size.height * 0.8)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.6,
        size.width * 0.6,
        size.height * 0.85,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 1.0,
        size.width,
        size.height * 0.75,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, paint..color = Colors.white.withValues(alpha: 0.05));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
