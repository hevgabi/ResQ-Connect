import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import '../../widgets/loading_overlay.dart';
import '../settings/settings_screen.dart';

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

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  static const int _teamCapacityMax = 5; // default max, can come from Firestore

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final rescuerSnap = await FirebaseFirestore.instance
          .collection('rescuers')
          .doc(uid)
          .get();

      if (!mounted) return;
      final uData = userSnap.data();
      final rData = rescuerSnap.data();

      setState(() {
        _userData = uData;
        _rescuerData = rData;
        _onDuty = rData?['is_on_duty'] ?? false;
        if (!_editingPersonal) {
          _firstNameController.text = uData?['first_name'] ?? '';
          _lastNameController.text = uData?['last_name'] ?? '';
          _phoneController.text = uData?['phone'] ?? '';
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDuty(bool value) async {
    setState(() => _onDuty = value);
    await _firestoreService.updateRescuerDuty(uid, value);
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeMissions = (_rescuerData?['active_mission_count'] ?? 0) as int;
    final teamCapacity =
        (_rescuerData?['team_capacity_max'] ?? _teamCapacityMax) as int;
    final capacityRatio = teamCapacity > 0
        ? activeMissions / teamCapacity
        : 0.0;

    Color capacityColor;
    if (capacityRatio >= 0.8) {
      capacityColor = AppTheme.dangerRed;
    } else if (capacityRatio >= 0.5) {
      capacityColor = AppTheme.warningOrange;
    } else {
      capacityColor = AppTheme.successGreen;
    }

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
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile header
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // On Duty toggle
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  title: Text(
                    _onDuty ? 'On Duty' : 'Off Duty',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _onDuty
                          ? AppTheme.successGreen
                          : AppTheme.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    _onDuty
                        ? 'You are available for missions'
                        : 'You are not receiving missions',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _onDuty,
                  activeThumbColor: AppTheme.successGreen,
                  onChanged: _toggleDuty,
                ),
              ),

              const SizedBox(height: 16),

              // Team Capacity bar
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
                        'Team Capacity',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: capacityRatio.clamp(0.0, 1.0),
                          minHeight: 12,
                          backgroundColor: capacityColor.withValues(
                            alpha: 0.15,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            capacityColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$activeMissions / $teamCapacity missions active',
                            style: TextStyle(
                              color: capacityColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${(capacityRatio * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: capacityColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Personal info card (editable)
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

              // Rescuer info (read-only)
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

              const SizedBox(height: 24),
            ],
          ),
        ),
        bottomNavigationBar: RescuerBottomNav(currentIndex: 3),
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
