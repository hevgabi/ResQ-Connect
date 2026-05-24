import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';

import '../../services/firestore_service.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';

class ModeratorProfileScreen extends StatefulWidget {
  const ModeratorProfileScreen({super.key});

  @override
  State<ModeratorProfileScreen> createState() => _ModeratorProfileScreenState();
}

class _ModeratorProfileScreenState extends State<ModeratorProfileScreen> {
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  // Stats
  int _totalPublished = 0;
  int _totalRejected = 0;
  int _totalPending = 0;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
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

      // Load stats
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
        _firstNameController.text = uData?['first_name'] ?? '';
        _lastNameController.text = uData?['last_name'] ?? '';
        _phoneController.text = uData?['phone'] ?? '';
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

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D47A1),
          title: const Text(
            'My Profile',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () => showHamburgerMenu(context, role: HamburgerRole.moderator),
            ),
          ], // Inayos na list bracket ng actions
        ), // Inayos na panara ng AppBar
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
              )
            : _buildBody(),
        bottomNavigationBar: const ModeratorBottomNav(currentIndex: 4),
      ),
    );
  }

  Widget _buildBody() {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final firstName = _userData?['first_name'] ?? '';
    final lastName = _userData?['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim();
    final initials = _initials(firstName, lastName, email);
    final memberSince = (_userData?['created_at'] as Timestamp?)?.toDate();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF0D47A1),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Avatar + Name Header ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0D47A1).withAlpha(76),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  fullName.isNotEmpty ? fullName : 'Moderator',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'MODERATOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (memberSince != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Member since ${_formatDate(memberSince)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF90A4AE),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Quick Stats ───────────────────────────────────────────────
          Row(
            children: [
              _StatCard(
                label: 'Published',
                value: '$_totalPublished',
                color: const Color(0xFF1FAA59),
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Rejected',
                value: '$_totalRejected',
                color: const Color(0xFFD7263D),
                icon: Icons.cancel_outlined,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Pending',
                value: '$_totalPending',
                color: const Color(0xFFFF6B00),
                icon: Icons.pending_actions_outlined,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Personal Info Card ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Personal Info',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2B45),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        if (_editing) {
                          _saveProfile();
                        } else {
                          setState(() => _editing = true);
                        }
                      },
                      icon: Icon(
                        _editing ? Icons.save_outlined : Icons.edit_outlined,
                        size: 16,
                      ),
                      label: Text(_editing ? 'Save' : 'Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0D47A1),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                _ProfileField(
                  label: 'First Name',
                  controller: _firstNameController,
                  editing: _editing,
                ),
                const SizedBox(height: 12),
                _ProfileField(
                  label: 'Last Name',
                  controller: _lastNameController,
                  editing: _editing,
                ),
                const SizedBox(height: 12),
                _ProfileField(
                  label: 'Phone',
                  controller: _phoneController,
                  editing: _editing,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                _ReadonlyField(label: 'Email', value: email),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _initials(String firstName, String lastName, String email) {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    if (firstName.isNotEmpty) return firstName[0].toUpperCase();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'M';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Stat Card
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
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
              color: Colors.black.withAlpha(13),
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

// ---------------------------------------------------------------------------
// Profile Field
// ---------------------------------------------------------------------------

class _ProfileField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool editing;
  final TextInputType? keyboardType;

  const _ProfileField({
    required this.label,
    required this.controller,
    required this.editing,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
        ),
        const SizedBox(height: 4),
        editing
            ? TextField(
                controller: controller,
                keyboardType: keyboardType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF6A1B9A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF6A1B9A),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              )
            : Text(
                controller.text.isNotEmpty ? controller.text : 'Not set',
                style: const TextStyle(fontSize: 15, color: Color(0xFF37474F)),
              ),
      ],
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadonlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
        ),
        const SizedBox(height: 4),
        Text(
          value.isNotEmpty ? value : 'N/A',
          style: const TextStyle(fontSize: 15, color: Color(0xFF37474F)),
        ),
      ],
    );
  }
}