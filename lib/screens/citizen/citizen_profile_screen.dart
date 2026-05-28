import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/user_model.dart';
import '../../models/sos_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/broadcast_alert_overlay.dart';

class CitizenProfileScreen extends StatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  State<CitizenProfileScreen> createState() => _CitizenProfileScreenState();
}

class _CitizenProfileScreenState extends State<CitizenProfileScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final StorageService _storageService = StorageService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;

  bool _editingPersonal = false;
  bool _editingMedical = false;
  bool _loading = false;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _allergiesController;

  String? _selectedBloodType;

  static const List<String> _bloodTypes = [
    'A+',
    'A-',
    'B+',
    'B-',
    'O+',
    'O-',
    'AB+',
    'AB-',
  ];

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
    _allergiesController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  void _populateControllers(UserModel user) {
    if (!_editingPersonal) {
      _firstNameController.text = user.firstName ?? '';
      _lastNameController.text = user.lastName ?? '';
      _phoneController.text = user.phone ?? '';
    }
    if (!_editingMedical) {
      _selectedBloodType = user.bloodType;
      _allergiesController.text = user.allergies ?? '';
    }
  }

  Future<void> _pickAndUploadAvatar(UserModel user) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      final file = File(picked.path);
      final url = await _storageService.uploadProfilePhoto(user.uid, file);
      await _firestoreService.updateUserField(user.uid, 'photo_url', url);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePersonalInfo(UserModel user) async {
    setState(() => _loading = true);
    try {
      await _firestoreService.updateUser(user.uid, {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
      });
      setState(() => _editingPersonal = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Personal info saved!')));
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

  Future<void> _saveMedicalInfo(UserModel user) async {
    setState(() => _loading = true);
    try {
      await _firestoreService.updateUser(user.uid, {
        'blood_type': _selectedBloodType,
        'allergies': _allergiesController.text.trim(),
      });
      setState(() => _editingMedical = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Medical info saved!')));
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

  Future<void> _deleteCommunityPost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Post'),
        content: const Text(
          'Are you sure you want to delete this post? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await _firestoreService.deleteCommunityPost(postId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  UserRole _mapStringToUserRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'rescuer':
        return UserRole.rescuer;
      case 'moderator':
        return UserRole.moderator;
      default:
        return UserRole.citizen;
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'resolved':
      case 'published':
        return AppTheme.successGreen;
      case 'pending':
        return AppTheme.warningOrange;
      default:
        return AppTheme.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<UserModel?>(
      stream: _firestoreService.userStream(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null) _populateControllers(user);

        return LoadingOverlay(
          isLoading: _loading,
          child: Scaffold(
            backgroundColor: _surface,
            appBar: AppBar(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              elevation: 0,
              title: const Text(
                'Profile',
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
                      showHamburgerMenu(context, role: HamburgerRole.citizen),
                ),
              ],
            ),
            body: Stack(
              children: [
                user == null
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBody(user, uid),
                const BroadcastAlertOverlay(topOffset: 12),
              ],
            ),
            bottomNavigationBar: AppBottomNav(currentIndex: 4),
          ),
        );
      },
    );
  }

  Widget _buildBody(UserModel user, String uid) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(child: _buildFbHeader(user)),
        SliverToBoxAdapter(child: _buildTabBar()),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [_buildPostsTab(user, uid), _buildAboutTab(user, uid)],
      ),
    );
  }

  // ─── Facebook-style Header ────────────────────────────────────────────────

  Widget _buildFbHeader(UserModel user) {
    final name =
        '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim().isNotEmpty
        ? '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim()
        : user.displayName ?? 'User';
    final initials =
        ((user.firstName?.isNotEmpty == true ? user.firstName![0] : '') +
                (user.lastName?.isNotEmpty == true ? user.lastName![0] : ''))
            .toUpperCase();

    return Container(
      color: _cardBg,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomLeft,
            children: [
              // Cover gradient
              Container(
                height: 140,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1877F2), Color(0xFF0D3480)],
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
                child: GestureDetector(
                  onTap: () => _pickAndUploadAvatar(user),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardBg, width: 4),
                        ),
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: _blue.withValues(alpha: 0.2),
                          backgroundImage: user.photoUrl != null
                              ? CachedNetworkImageProvider(user.photoUrl!)
                              : null,
                          child: user.photoUrl == null
                              ? Text(
                                  initials.isEmpty ? '?' : initials,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: _blue,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4E6EA),
                            shape: BoxShape.circle,
                            border: Border.all(color: _cardBg, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                    ],
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
                RoleBadge(role: _mapStringToUserRole(user.role)),
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
          Tab(text: 'Community Posts'),
          Tab(text: 'About'),
        ],
      ),
    );
  }

  // ─── Community Posts Tab ──────────────────────────────────────────────────

  Widget _buildPostsTab(UserModel user, String uid) {
    final name =
        '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim().isNotEmpty
        ? '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim()
        : user.displayName ?? 'User';
    final initials =
        ((user.firstName?.isNotEmpty == true ? user.firstName![0] : '') +
                (user.lastName?.isNotEmpty == true ? user.lastName![0] : ''))
            .toUpperCase();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.userCommunityPostsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildPostsFallback(uid, name, initials);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return _emptyPosts();
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: posts.length,
          itemBuilder: (_, i) => _postCard(posts[i], name, initials),
        );
      },
    );
  }

  Widget _buildPostsFallback(String uid, String name, String initials) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _firestoreService
          .userCommunityPostsStream(uid)
          .first
          .catchError((_) => <Map<String, dynamic>>[]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) return _emptyPosts();
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: posts.length,
          itemBuilder: (_, i) => _postCard(posts[i], name, initials),
        );
      },
    );
  }

  Widget _emptyPosts() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.feed_outlined,
              size: 56,
              color: _textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No community posts yet.',
              style: TextStyle(color: _textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> data, String name, String initials) {
    final postId = data['id'] as String? ?? '';
    final text = (data['text'] as String?) ?? '';
    final ts = (data['created_at'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? timeago.format(ts) : '';
    final status = (data['status'] as String?) ?? 'pending';

    final rawMediaUrls = data['media_urls'];
    final List<String> mediaUrls = rawMediaUrls is List
        ? rawMediaUrls.whereType<String>().toList()
        : [];

    final avatarColors = [
      const Color(0xFF0D47A1),
      const Color(0xFF1565C0),
      const Color(0xFF283593),
      const Color(0xFF1FAA59),
      const Color(0xFF00838F),
    ];
    final avatarColor = avatarColors[name.hashCode.abs() % avatarColors.length];

    return Container(
      color: _cardBg,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: avatar + name + time + 3-dot menu ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: avatarColor,
                radius: 20,
                child: Text(
                  initials.isEmpty ? '?' : initials,
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
                    Row(
                      children: [
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        if (timeStr.isNotEmpty) const SizedBox(width: 6),
                        _statusPill(status),
                      ],
                    ),
                  ],
                ),
              ),
              // 3-dot delete menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz,
                  color: _textSecondary,
                  size: 22,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  if (value == 'delete' && postId.isNotEmpty) {
                    _deleteCommunityPost(postId);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Post text ──
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF37474F),
                height: 1.45,
              ),
            ),
          ],

          // ── Media grid ──
          if (mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildMediaGrid(mediaUrls),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<String> urls) {
    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          urls[0],
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : Container(
                  height: 200,
                  color: Colors.grey.shade100,
                  child: const Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => Container(
            height: 100,
            color: Colors.grey.shade100,
            child: const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length > 4 ? 4 : urls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final isLast = i == 3 && urls.length > 4;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                urls[i],
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(color: Colors.grey.shade100),
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade100,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                  ),
                ),
              ),
              if (isLast)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Text(
                      '+${urls.length - 3}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── About Tab ─────────────────────────────────────────────────────────────

  Widget _buildAboutTab(UserModel user, String uid) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildInfoSection(user),
        const SizedBox(height: 8),
        _buildMedicalSection(user),
        const SizedBox(height: 8),
        _buildSosHistorySection(uid),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInfoSection(UserModel user) {
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
                    _savePersonalInfo(user);
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
        ],
      ),
    );
  }

  Widget _buildMedicalSection(UserModel user) {
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
                'Medical Info',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: _textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  if (_editingMedical) {
                    _saveMedicalInfo(user);
                  } else {
                    setState(() => _editingMedical = true);
                  }
                },
                child: Text(
                  _editingMedical ? 'Save' : 'Edit',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.bloodtype_outlined,
                  color: _textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blood Type',
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                      const SizedBox(height: 2),
                      _editingMedical
                          ? DropdownButtonFormField<String>(
                              value: _selectedBloodType,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              items: _bloodTypes
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedBloodType = v),
                            )
                          : Text(
                              _selectedBloodType ?? 'Not set',
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
          ),
          _infoRow(
            Icons.medical_information_outlined,
            'Allergies',
            _allergiesController,
            _editingMedical,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildSosHistorySection(String uid) {
    return Container(
      color: _cardBg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SOS History',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<SosRequestModel>>(
            future: _firestoreService.getRecentSosByUser(uid, limit: 5),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return const Text(
                  'No SOS history.',
                  style: TextStyle(color: _textSecondary),
                );
              }
              return Column(
                children: list.map((sos) {
                  final date = sos.createdAt != null
                      ? timeago.format(sos.createdAt!)
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sos_outlined,
                          color: AppTheme.dangerRed,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SOS Request',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _textPrimary,
                                ),
                              ),
                              if (date.isNotEmpty)
                                Text(
                                  date,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _statusPill(sos.status ?? ''),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    TextEditingController controller,
    bool editing, {
    TextInputType? keyboardType,
    int maxLines = 1,
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
                        maxLines: maxLines,
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
}

// ─── Cover wave painter ────────────────────────────────────────────────────────

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
