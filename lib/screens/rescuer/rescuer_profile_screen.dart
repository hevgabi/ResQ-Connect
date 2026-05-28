import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../settings/hamburger_menu_screen.dart';

import '../../models/team_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/broadcast_alert_overlay.dart';

class RescuerProfileScreen extends StatefulWidget {
  const RescuerProfileScreen({super.key});

  @override
  State<RescuerProfileScreen> createState() => _RescuerProfileScreenState();
}

class _RescuerProfileScreenState extends State<RescuerProfileScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _rescuerData;

  bool _onDuty = false;
  bool _editingPersonal = false;
  bool _loading = false;
  bool _togglingDuty = false;

  late TabController _tabController;
  StreamSubscription? _rescuerStreamSub;
  StreamSubscription? _userStreamSub;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  // FB-style palette
  static const _blue = Color(0xFF1877F2);
  static const _surface = Color(0xFFF0F2F5);
  static const _cardBg = Colors.white;
  static const _textPrimary = Color(0xFF050505);
  static const _textSecondary = Color(0xFF65676B);
  static const _divider = Color(0xFFE4E6EA);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    _rescuerStreamSub = FirebaseFirestore.instance
        .collection('rescuers')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!mounted || !doc.exists) return;
          final rData = doc.data();
          setState(() {
            _rescuerData = rData;
            if (!_togglingDuty) {
              _onDuty = rData?['is_on_duty'] ?? false;
            }
          });
        });

    _userStreamSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!mounted || !doc.exists) return;
          final uData = doc.data();
          setState(() {
            _userData = uData;
            if (!_editingPersonal) {
              _firstNameController.text = uData?['first_name'] ?? '';
              _lastNameController.text = uData?['last_name'] ?? '';
              _phoneController.text = uData?['phone'] ?? '';
            }
          });
        });
  }

  Future<void> _toggleDuty(bool value) async {
    if (_togglingDuty) return;
    setState(() {
      _togglingDuty = true;
      _onDuty = value;
    });
    try {
      await _firestoreService.updateRescuerDuty(uid, value);
    } catch (e) {
      if (mounted) {
        setState(() => _onDuty = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update duty status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingDuty = false);
    }
  }

  Future<void> _savePersonalInfo() async {
    setState(() => _loading = true);
    try {
      await _firestoreService.updateUser(uid, {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
      });
      setState(() => _editingPersonal = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Info saved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _initials() {
    final first = _userData?['first_name'] ?? '';
    final last = _userData?['last_name'] ?? '';
    return ((first.isNotEmpty ? first[0] : '') +
            (last.isNotEmpty ? last[0] : ''))
        .toUpperCase();
  }

  String _fullName() {
    final first = _userData?['first_name'] ?? '';
    final last = _userData?['last_name'] ?? '';
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : 'Rescuer';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rescuerStreamSub?.cancel();
    _userStreamSub?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _loading,
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
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () =>
                  showHamburgerMenu(context, role: HamburgerRole.rescuer),
            ),
          ],
        ),
        body: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(child: _buildFbHeader()),
                SliverToBoxAdapter(child: _buildTabBar()),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [_buildMissionsTab(), _buildAboutTab()],
              ),
            ),
            const BroadcastAlertOverlay(topOffset: 12),
          ],
        ),
        bottomNavigationBar: RescuerBottomNav(currentIndex: 4),
      ),
    );
  }

  // ─── Facebook-style Header ────────────────────────────────────────────────

  Widget _buildFbHeader() {
    final initials = _initials();
    final name = _fullName();

    return Container(
      color: _cardBg,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomLeft,
            children: [
              // Cover gradient — green tint for rescuers
              Container(
                height: 140,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D6B3E), Color(0xFF1FAA59)],
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
                    backgroundColor: const Color(
                      0xFF1FAA59,
                    ).withValues(alpha: 0.2),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1FAA59),
                      ),
                    ),
                  ),
                ),
              ),
              // Duty badge top-right
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => _toggleDuty(!_onDuty),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _onDuty
                          ? AppTheme.successGreen
                          : Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_togglingDuty)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            _onDuty
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 12,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 5),
                        Text(
                          _onDuty ? 'On Duty' : 'Off Duty',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'RESCUER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.successGreen,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if ((_rescuerData?['badge_number'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${_rescuerData!['badge_number']}',
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
                if ((_rescuerData?['agency_name'] ?? '')
                    .toString()
                    .isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _rescuerData!['agency_name'],
                    style: const TextStyle(color: _textSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Quick stats row
          _buildStatsRow(),
          const SizedBox(height: 8),
          const Divider(height: 1, color: _divider),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        double avg = 0;
        if (docs.isNotEmpty) {
          final total = docs.fold<int>(
            0,
            (sum, d) => sum + ((d.data() as Map)['stars'] as int? ?? 0),
          );
          avg = total / docs.length;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _StatChip(
                icon: Icons.star_rounded,
                label: docs.isEmpty
                    ? 'No reviews'
                    : '${avg.toStringAsFixed(1)} (${docs.length})',
                color: const Color(0xFFFFC107),
              ),
              const SizedBox(width: 12),
              StreamBuilder<TeamModel?>(
                stream: _firestoreService.rescuerTeamStream(uid),
                builder: (context, teamSnap) {
                  final team = teamSnap.data;
                  return _StatChip(
                    icon: Icons.groups_outlined,
                    label: team != null ? team.name : 'No team',
                    color: _blue,
                  );
                },
              ),
            ],
          ),
        );
      },
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
          Tab(text: 'Missions'),
          Tab(text: 'About'),
        ],
      ),
    );
  }

  // ─── Missions Tab ─────────────────────────────────────────────────────────

  Widget _buildMissionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .where('rescuer_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(Icons.assignment_outlined, 'No missions yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final status = (data['status'] as String?) ?? 'pending';
            final ts = (data['created_at'] as Timestamp?)?.toDate();
            final timeStr = ts != null ? _formatTimeAgo(ts) : '';
            final type = (data['type'] as String?) ?? 'Mission';

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
                      color: _missionStatusColor(
                        status,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_fire_department_outlined,
                      color: _missionStatusColor(status),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _textPrimary,
                          ),
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
    );
  }

  // ─── About Tab ─────────────────────────────────────────────────────────────

  Widget _buildAboutTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildPersonalInfoSection(),
        const SizedBox(height: 8),
        _buildRescuerInfoSection(),
        const SizedBox(height: 8),
        _buildTeamSection(),
        const SizedBox(height: 8),
        _buildReviewsSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPersonalInfoSection() {
    return Container(
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
                  if (_editingPersonal) {
                    _savePersonalInfo();
                  } else {
                    setState(() => _editingPersonal = true);
                  }
                },
                child: Text(
                  _editingPersonal ? 'Save' : 'Edit',
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
            _editingPersonal,
          ),
          _infoRow(
            Icons.badge_outlined,
            'Last Name',
            _lastNameController,
            _editingPersonal,
          ),
          _infoRow(
            Icons.phone_outlined,
            'Phone',
            _phoneController,
            _editingPersonal,
            keyboardType: TextInputType.phone,
          ),
          _readonlyRow(
            Icons.email_outlined,
            'Email',
            FirebaseAuth.instance.currentUser?.email ?? '',
          ),
        ],
      ),
    );
  }

  Widget _buildRescuerInfoSection() {
    return Container(
      color: _cardBg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rescuer Info',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _readonlyRow(
            Icons.badge_outlined,
            'Badge Number',
            _rescuerData?['badge_number'] ?? 'N/A',
          ),
          _readonlyRow(
            Icons.business_outlined,
            'Agency',
            _rescuerData?['agency_name'] ?? 'N/A',
          ),
        ],
      ),
    );
  }

  Widget _buildTeamSection() {
    return StreamBuilder<TeamModel?>(
      stream: _firestoreService.rescuerTeamStream(uid),
      builder: (context, snap) {
        final team = snap.data;
        final isLeader = team?.leaderId == uid;

        return Container(
          color: _cardBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'My Team',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: _textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (team != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isLeader ? 'Leader' : 'Member',
                        style: const TextStyle(
                          color: AppTheme.successGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (team == null)
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: _textSecondary),
                    const SizedBox(width: 8),
                    const Text(
                      'Not assigned to any team yet.',
                      style: TextStyle(color: _textSecondary, fontSize: 14),
                    ),
                  ],
                )
              else ...[
                _readonlyRow(Icons.groups_outlined, 'Team Name', team.name),
                _readonlyRow(
                  Icons.people_outline,
                  'Members',
                  '${team.memberIds.length} member${team.memberIds.length == 1 ? '' : 's'}',
                ),
                if (team.description.isNotEmpty)
                  _readonlyRow(
                    Icons.description_outlined,
                    'Description',
                    team.description,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return Container(
          color: _cardBg,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Citizen Reviews',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: _textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${docs.length} total',
                    style: const TextStyle(color: _textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (docs.isEmpty)
                const Text(
                  'No reviews yet.\nThey\'ll appear here after completing missions.',
                  style: TextStyle(color: _textSecondary, fontSize: 14),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final stars = (data['stars'] as int?) ?? 0;
                  final comment = (data['comment'] as String?)?.trim() ?? '';
                  final ts = data['created_at'] as Timestamp?;
                  final date = ts != null ? _formatTimeAgo(ts.toDate()) : '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < stars
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 16,
                                color: const Color(0xFFFFC107),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              date,
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            comment,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF37474F),
                            ),
                          ),
                        ],
                        const Divider(
                          height: 14,
                          thickness: 0.5,
                          color: _divider,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
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
        color: _missionStatusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: _missionStatusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _missionStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppTheme.successGreen;
      case 'active':
        return _blue;
      case 'pending':
        return AppTheme.warningOrange;
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
}

// ─── Stat chip ───────────────────────────────────────────────────────────────

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
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
