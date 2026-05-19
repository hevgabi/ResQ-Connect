import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/user_model.dart';
import '../../models/sos_request_model.dart';
import '../../models/report_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/role_badge.dart';

class CitizenProfileScreen extends StatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  State<CitizenProfileScreen> createState() => _CitizenProfileScreenState();
}

class _CitizenProfileScreenState extends State<CitizenProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

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

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _allergiesController = TextEditingController();
  }

  @override
  void dispose() {
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

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
      case 'published':
        return AppTheme.successGreen;
      case 'pending':
        return AppTheme.warningOrange;
      case 'rejected':
        return AppTheme.dangerRed;
      default:
        return AppTheme.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null)
      return const Scaffold(body: Center(child: Text('Not logged in')));

    return StreamBuilder<UserModel?>(
      stream: _firestoreService.userStream(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user != null) _populateControllers(user);

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
            ),
            body: user == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildProfileHeader(user),
                        const SizedBox(height: 16),
                        _buildPersonalInfoCard(user),
                        const SizedBox(height: 16),
                        _buildMedicalInfoCard(user),
                        const SizedBox(height: 16),
                        _buildSosHistory(uid),
                        const SizedBox(height: 16),
                        _buildReportHistory(uid),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
            bottomNavigationBar: AppBottomNav(currentIndex: 4),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(UserModel user) {
    final initials =
        ((user.firstName?.isNotEmpty == true ? user.firstName![0] : '') +
                (user.lastName?.isNotEmpty == true ? user.lastName![0] : ''))
            .toUpperCase();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => _pickAndUploadAvatar(user),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    backgroundImage: user.photoUrl != null
                        ? CachedNetworkImageProvider(user.photoUrl!)
                        : null,
                    child: user.photoUrl == null
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user.displayName ??
                  '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            RoleBadge(role: user.role),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard(UserModel user) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (_editingPersonal) {
                      _savePersonalInfo(user);
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
            _editableField('Last Name', _lastNameController, _editingPersonal),
            const SizedBox(height: 10),
            _editableField(
              'Phone',
              _phoneController,
              _editingPersonal,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicalInfoCard(UserModel user) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Medical Info',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (_editingMedical) {
                      _saveMedicalInfo(user);
                    } else {
                      setState(() => _editingMedical = true);
                    }
                  },
                  icon: Icon(
                    _editingMedical ? Icons.save : Icons.edit,
                    size: 16,
                  ),
                  label: Text(_editingMedical ? 'Save' : 'Edit'),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text(
              'Blood Type',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            _editingMedical
                ? DropdownButtonFormField<String>(
                    value: _selectedBloodType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _bloodTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBloodType = v),
                  )
                : Text(
                    _selectedBloodType ?? 'Not set',
                    style: const TextStyle(fontSize: 15),
                  ),
            const SizedBox(height: 12),
            _editableField(
              'Allergies',
              _allergiesController,
              _editingMedical,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editableField(
    String label,
    TextEditingController controller,
    bool editing, {
    TextInputType? keyboardType,
    int maxLines = 1,
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
                maxLines: maxLines,
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
                controller.text.isEmpty ? 'Not set' : controller.text,
                style: const TextStyle(fontSize: 15),
              ),
      ],
    );
  }

  Widget _buildSosHistory(String uid) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SOS History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 16),
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
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: list.map((sos) {
                    final date = sos.createdAt != null
                        ? timeago.format(sos.createdAt!.toDate())
                        : '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.sos_outlined,
                        color: AppTheme.dangerRed,
                      ),
                      title: Text(
                        'SOS Request',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      trailing: _statusChip(sos.status),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHistory(String uid) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Report History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 16),
            FutureBuilder<List<ReportModel>>(
              future: _firestoreService.getRecentReportsByUser(uid, limit: 5),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Text(
                    'No reports submitted yet.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  );
                }
                return Column(
                  children: list.map((r) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.report_outlined,
                        color: AppTheme.warningOrange,
                      ),
                      title: Text(
                        r.title ?? r.type ?? 'Incident Report',
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _statusChip(r.status),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
