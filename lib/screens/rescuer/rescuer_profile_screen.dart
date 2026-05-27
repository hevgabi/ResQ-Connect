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

class RescuerProfileScreen extends StatefulWidget {
  const RescuerProfileScreen({super.key});

  @override
  State<RescuerProfileScreen> createState() => _RescuerProfileScreenState();
}

class _RescuerProfileScreenState extends State<RescuerProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _rescuerData;

  bool _onDuty = false;
  bool _editingPersonal = false;
  bool _loading = false;
  bool _togglingDuty = false;

  StreamSubscription? _rescuerStreamSub;
  StreamSubscription? _userStreamSub;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
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
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          title: const Text(
            'My Profile',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () =>
                  showHamburgerMenu(context, role: HamburgerRole.rescuer),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Profile header ─────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: AppTheme.primaryBlue.withValues(
                          alpha: 0.15,
                        ),
                        child: Text(
                          _initials().isNotEmpty ? _initials() : '?',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_userData?['first_name'] ?? ''} ${_userData?['last_name'] ?? ''}'
                                .trim()
                                .isNotEmpty
                            ? '${_userData?['first_name'] ?? ''} ${_userData?['last_name'] ?? ''}'
                                  .trim()
                            : 'Rescuer',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _rescuerData?['badge_number'] ?? '',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _rescuerData?['agency_name'] ?? '',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Inline rating summary ──────────────────────────
                      _RatingSummaryWidget(rescuerId: uid),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── On Duty toggle ─────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  title: Row(
                    children: [
                      Text(
                        _onDuty ? 'On Duty' : 'Off Duty',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _onDuty
                              ? AppTheme.successGreen
                              : AppTheme.textSecondary,
                        ),
                      ),
                      if (_togglingDuty) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    _onDuty
                        ? 'You are available for missions'
                        : 'You are not receiving missions',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _onDuty,
                  activeThumbColor: AppTheme.successGreen,
                  onChanged: _togglingDuty ? null : _toggleDuty,
                ),
              ),

              const SizedBox(height: 16),

              // ── Team card ──────────────────────────────────────────────
              StreamBuilder<TeamModel?>(
                stream: _firestoreService.rescuerTeamStream(uid),
                builder: (context, snap) {
                  final team = snap.data;
                  final isLeader = team?.leaderId == uid;

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.groups_outlined,
                                size: 18,
                                color: AppTheme.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'My Team',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
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
                                    color: AppTheme.successGreen.withAlpha(25),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppTheme.successGreen.withAlpha(
                                        80,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    isLeader ? 'Leader' : 'Member',
                                    style: const TextStyle(
                                      color: AppTheme.successGreen,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (snap.connectionState == ConnectionState.waiting)
                            const Center(child: CircularProgressIndicator())
                          else if (team == null)
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Not assigned to any team yet.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _readonlyField('Team Name', team.name),
                            const SizedBox(height: 10),
                            _readonlyField(
                              'Members',
                              '${team.memberIds.length} member${team.memberIds.length == 1 ? '' : 's'}',
                            ),
                            if (team.description.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _readonlyField('Description', team.description),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── Personal info card ─────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
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
                              fontSize: 15,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              if (_editingPersonal) {
                                _savePersonalInfo();
                              } else {
                                setState(() => _editingPersonal = true);
                              }
                            },
                            icon: Icon(
                              _editingPersonal ? Icons.save : Icons.edit,
                              size: 16,
                            ),
                            label: Text(_editingPersonal ? 'Save' : 'Edit'),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      _editableField(
                        'First Name',
                        _firstNameController,
                        _editingPersonal,
                      ),
                      const SizedBox(height: 10),
                      _editableField(
                        'Last Name',
                        _lastNameController,
                        _editingPersonal,
                      ),
                      const SizedBox(height: 10),
                      _editableField(
                        'Phone',
                        _phoneController,
                        _editingPersonal,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      _readonlyField(
                        'Email',
                        FirebaseAuth.instance.currentUser?.email ?? '',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Rescuer info (read-only) ────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rescuer Info',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Divider(height: 16),
                      _readonlyField(
                        'Badge Number',
                        _rescuerData?['badge_number'] ?? 'N/A',
                      ),
                      const SizedBox(height: 10),
                      _readonlyField(
                        'Agency',
                        _rescuerData?['agency_name'] ?? 'N/A',
                      ),
                      const SizedBox(height: 10),
                      _readonlyField(
                        'Team ID',
                        _rescuerData?['team_id'] != null
                            ? _rescuerData!['team_id'].toString()
                            : 'N/A',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Reviews section ────────────────────────────────────────
              _ReviewsSection(rescuerId: uid),

              const SizedBox(height: 24),
            ],
          ),
        ),
        bottomNavigationBar: RescuerBottomNav(currentIndex: 4),
      ),
    );
  }

  Widget _editableField(
    String label,
    TextEditingController controller,
    bool editing, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        editing
            ? TextField(
                controller: controller,
                keyboardType: keyboardType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              )
            : Text(
                controller.text.isNotEmpty ? controller.text : 'Not set',
                style: const TextStyle(fontSize: 15),
              ),
      ],
    );
  }

  Widget _readonlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value.isNotEmpty ? value : 'N/A',
          style: const TextStyle(fontSize: 15),
        ),
      ],
    );
  }
}

// ── Rating summary widget (shows avg stars + count) ───────────────────────────
class _RatingSummaryWidget extends StatelessWidget {
  final String rescuerId;
  const _RatingSummaryWidget({required this.rescuerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: rescuerId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Text(
            'No reviews yet',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          );
        }
        final docs = snap.data!.docs;
        final total = docs.fold<int>(
          0,
          (sum, d) => sum + ((d.data() as Map)['stars'] as int? ?? 0),
        );
        final avg = total / docs.length;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...List.generate(5, (i) {
              return Icon(
                i < avg.round()
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: const Color(0xFFFFC107),
                size: 22,
              );
            }),
            const SizedBox(width: 8),
            Text(
              '${avg.toStringAsFixed(1)} (${docs.length} review${docs.length == 1 ? '' : 's'})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        );
      },
    );
  }
}

// ── Reviews list section ───────────────────────────────────────────────────────
class _ReviewsSection extends StatelessWidget {
  final String rescuerId;
  const _ReviewsSection({required this.rescuerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: rescuerId)
          .orderBy('created_at', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.reviews_outlined,
                      size: 18,
                      color: AppTheme.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Citizen Reviews',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${docs.length} total',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                if (docs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No reviews yet.\nThey\'ll appear here after completing missions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final stars = (data['stars'] as int?) ?? 0;
                    final comment = (data['comment'] as String?)?.trim() ?? '';
                    final ts = data['created_at'] as Timestamp?;
                    final date = ts != null
                        ? _formatDate(ts.toDate())
                        : 'Unknown date';
                    return _ReviewTile(
                      stars: stars,
                      comment: comment,
                      date: date,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ReviewTile extends StatelessWidget {
  final int stars;
  final String comment;
  final String date;

  const _ReviewTile({
    required this.stars,
    required this.comment,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
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
                  i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFFFC107),
                ),
              ),
              const Spacer(),
              Text(
                date,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              comment,
              style: const TextStyle(fontSize: 13, color: Color(0xFF37474F)),
            ),
          ],
          const Divider(height: 14, thickness: 0.5),
        ],
      ),
    );
  }
}
