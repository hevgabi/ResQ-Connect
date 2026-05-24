import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/storage_service.dart';
import '../../widgets/loading_overlay.dart';
import 'register_screen.dart' show VerifyEmailScreen;

class GoogleCompleteProfileScreen extends StatefulWidget {
  final User googleUser;

  const GoogleCompleteProfileScreen({super.key, required this.googleUser});

  @override
  State<GoogleCompleteProfileScreen> createState() =>
      _GoogleCompleteProfileScreenState();
}

class _GoogleCompleteProfileScreenState
    extends State<GoogleCompleteProfileScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _badgeNumberCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  String _selectedRole = 'citizen';
  String _selectedGender = 'Male';
  bool _isLoading = false;
  File? _govIdFile;

  late final AnimationController _rescuerFieldsController;
  late final Animation<double> _rescuerFieldsAnimation;

  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _successGreen = Color(0xFF1FAA59);
  static const _background = Color(0xFFF5F7FA);
  static const _textSecondary = Color(0xFF546E7A);

  @override
  void initState() {
    super.initState();

    // Pre-fill name from Google account
    final displayName = widget.googleUser.displayName ?? '';
    final parts = displayName.split(' ');
    _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
    _lastNameCtrl.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    _rescuerFieldsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _rescuerFieldsAnimation = CurvedAnimation(
      parent: _rescuerFieldsController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _rescuerFieldsController.dispose();
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _phoneCtrl,
      _agencyNameCtrl,
      _badgeNumberCtrl,
      _streetCtrl,
      _cityCtrl,
      _provinceCtrl,
      _zipCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectRole(String role) {
    if (_selectedRole == role || _isLoading) return;
    setState(() => _selectedRole = role);
    if (role == 'rescuer') {
      _rescuerFieldsController.forward();
    } else {
      _rescuerFieldsController.reverse();
    }
  }

  Future<void> _pickGovId(ImageSource source) async {
    if (_isLoading) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _govIdFile = File(picked.path));
  }

  void _showGovIdOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Upload Government ID',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF263238),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: _primaryBlue,
                ),
              ),
              title: const Text('Take a Photo'),
              subtitle: const Text('Scan your ID using camera'),
              onTap: () {
                Navigator.pop(context);
                _pickGovId(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: _primaryBlue,
                ),
              ),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select an existing photo'),
              onTap: () {
                Navigator.pop(context);
                _pickGovId(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final uid = widget.googleUser.uid;
      final email = widget.googleUser.email ?? '';

      String? govIdUrl;
      if (_govIdFile != null) {
        govIdUrl = await StorageService.instance.uploadGovId(uid, _govIdFile!);
      }

      final userDoc = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'email': email,
        'phone': _phoneCtrl.text.trim(),
        'gender': _selectedGender,
        'address': {
          'street': _streetCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'province': _provinceCtrl.text.trim(),
          'zip': _zipCtrl.text.trim(),
        },
        'role': _selectedRole,
        'blood_type': '',
        'allergies': '',
        'is_active': false,
        'is_email_verified': true, // Google accounts are pre-verified
        'approval_status': 'pending',
        'sign_in_method': 'google',
        'created_at': FieldValue.serverTimestamp(),
      };
      if (govIdUrl != null) userDoc['gov_id_url'] = govIdUrl;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userDoc);

      if (_selectedRole == 'rescuer') {
        await FirebaseFirestore.instance.collection('rescuers').doc(uid).set({
          'user_id': uid,
          'agency_name': _agencyNameCtrl.text.trim(),
          'badge_number': _badgeNumberCtrl.text.trim(),
          'is_on_duty': false,
          'team_capacity_max': 5,
          'active_mission_count': 0,
        });
      }

      // Sign out — wait for admin approval
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        // Google accounts are already email-verified, so go straight to pending screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => _GooglePendingScreen(email: email)),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: _dangerRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.googleUser.email ?? '';
    final photoUrl = widget.googleUser.photoURL;

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(email, photoUrl)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                sliver: SliverToBoxAdapter(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Personal Info ─────────────────────────────────
                        _sectionLabel('Personal Information'),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _firstNameCtrl,
                                label: 'First Name',
                                icon: Icons.person_outline,
                                validator: (v) =>
                                    v!.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildField(
                                controller: _lastNameCtrl,
                                label: 'Last Name',
                                icon: Icons.person_outline,
                                validator: (v) =>
                                    v!.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Email (read-only, from Google) ────────────────
                        _buildReadOnlyEmail(email),
                        const SizedBox(height: 16),

                        // ── Gender ────────────────────────────────────────
                        _buildGenderSelector(),
                        const SizedBox(height: 16),

                        // ── Phone ─────────────────────────────────────────
                        _buildField(
                          controller: _phoneCtrl,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 24),

                        // ── Address ───────────────────────────────────────
                        _sectionLabel('Address'),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _streetCtrl,
                          label: 'Street / Barangay',
                          icon: Icons.home_outlined,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _cityCtrl,
                                label: 'City / Municipality',
                                icon: Icons.location_city_outlined,
                                validator: (v) =>
                                    v!.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildField(
                                controller: _provinceCtrl,
                                label: 'Province',
                                icon: Icons.map_outlined,
                                validator: (v) =>
                                    v!.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 140,
                          child: _buildField(
                            controller: _zipCtrl,
                            label: 'ZIP Code',
                            icon: Icons.markunread_mailbox_outlined,
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Gov ID ────────────────────────────────────────
                        _buildGovIdUploader(),
                        const SizedBox(height: 24),

                        // ── Role ──────────────────────────────────────────
                        _sectionLabel('I am registering as'),
                        const SizedBox(height: 12),
                        _buildRoleSelector(),

                        // ── Rescuer-only fields ───────────────────────────
                        SizeTransition(
                          sizeFactor: _rescuerFieldsAnimation,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _agencyNameCtrl,
                                label: 'Agency Name',
                                icon: Icons.business_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _badgeNumberCtrl,
                                label: 'Badge Number',
                                icon: Icons.badge_outlined,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Complete Registration',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    await FirebaseAuth.instance.signOut();
                                    if (context.mounted) Navigator.pop(context);
                                  },
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String email, String? photoUrl) => Container(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    color: _primaryBlue,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        const Text(
          'Complete Your Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A few more details to finish your account',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // Google account badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (photoUrl != null)
                CircleAvatar(
                  backgroundImage: NetworkImage(photoUrl),
                  radius: 14,
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _successGreen,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Google',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildReadOnlyEmail(String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Email Address',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFECEFF1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCFD8DC)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.email_outlined,
              size: 20,
              color: Color(0xFF90A4AE),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                email,
                style: const TextStyle(fontSize: 15, color: Color(0xFF546E7A)),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _successGreen.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Verified',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _successGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: _primaryBlue,
    ),
  );

  Widget _buildGenderSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Gender',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: ['Male', 'Female', 'Other'].map((g) {
          final isSelected = _selectedGender == g;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: g != 'Other' ? 10 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _selectedGender = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryBlue : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? _primaryBlue
                          : const Color(0xFFCFD8DC),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    g,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF37474F),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );

  Widget _buildRoleSelector() => Row(
    children: [
      Expanded(child: _roleCard('citizen', 'Citizen', Icons.person_outline)),
      const SizedBox(width: 12),
      Expanded(child: _roleCard('rescuer', 'Rescuer', Icons.shield_outlined)),
    ],
  );

  Widget _roleCard(String role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => _selectRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _primaryBlue : const Color(0xFFCFD8DC),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF546E7A),
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF37474F),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGovIdUploader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Government ID',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _showGovIdOptions,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: _govIdFile != null ? 180 : 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _govIdFile != null
                  ? _primaryBlue
                  : const Color(0xFFCFD8DC),
              width: _govIdFile != null ? 2 : 1.5,
            ),
          ),
          child: _govIdFile != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        _govIdFile!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _showGovIdOptions,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(150),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Change',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _successGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'ID Uploaded',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.credit_card_outlined,
                      color: _primaryBlue.withAlpha(180),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to upload Government ID',
                      style: TextStyle(
                        color: _primaryBlue.withAlpha(200),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Camera or Gallery',
                      style: TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCFD8DC), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCFD8DC), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryBlue, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerRed, width: 1.8),
        ),
      ),
    );
  }
}

// =============================================================================
// GOOGLE PENDING SCREEN
// Shown after Google user completes profile — skips email verify step
// since Google accounts are already verified
// =============================================================================

class _GooglePendingScreen extends StatelessWidget {
  final String email;
  const _GooglePendingScreen({required this.email});

  static const _primaryBlue = Color(0xFF0D47A1);
  static const _warningOrange = Color(0xFFFF6B00);
  static const _successGreen = Color(0xFF1FAA59);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _warningOrange.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_empty_rounded,
                  color: _warningOrange,
                  size: 50,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Account Pending Approval',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your Google account ($email) has been registered and is now under admin review.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF546E7A),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(20),
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
                  children: [
                    _step(
                      Icons.check_circle,
                      _successGreen,
                      'Registration Complete',
                      'Profile submitted successfully',
                      done: true,
                    ),
                    _divider(done: true),
                    _step(
                      Icons.verified_outlined,
                      _successGreen,
                      'Email Verified',
                      'Verified via Google account',
                      done: true,
                    ),
                    _divider(done: false),
                    _step(
                      Icons.admin_panel_settings_outlined,
                      _warningOrange,
                      'Admin Review',
                      'Estimated: 1–3 business days',
                      active: true,
                    ),
                    _divider(done: false),
                    _step(
                      Icons.login_outlined,
                      const Color(0xFF90A4AE),
                      'Account Activated',
                      'You can start using ResQConnect',
                      done: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _primaryBlue.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _primaryBlue.withAlpha(40)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      color: _primaryBlue,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You will receive an email once your account is approved.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryBlue,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (r) => false,
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Back to Sign In'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF546E7A),
                    side: const BorderSide(
                      color: Color(0xFFCFD8DC),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(
    IconData icon,
    Color color,
    String title,
    String subtitle, {
    bool done = false,
    bool active = false,
  }) {
    final on = done || active;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(on ? 30 : 15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: on ? color : const Color(0xFFB0BEC5),
            size: 18,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? const Color(0xFF263238) : const Color(0xFFB0BEC5),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: on ? const Color(0xFF546E7A) : const Color(0xFFCFD8DC),
                ),
              ),
            ],
          ),
        ),
        if (active)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B00).withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'In Progress',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6B00),
              ),
            ),
          ),
      ],
    );
  }

  Widget _divider({required bool done}) => Padding(
    padding: const EdgeInsets.only(left: 17),
    child: Container(
      width: 2,
      height: 20,
      color: done
          ? const Color(0xFF1FAA59).withAlpha(80)
          : const Color(0xFFCFD8DC),
    ),
  );
}
