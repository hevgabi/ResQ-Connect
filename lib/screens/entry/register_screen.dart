import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/loading_overlay.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _badgeNumberCtrl = TextEditingController();

  // ── State ────────────────────────────────────────────────────────────────────
  String _selectedRole = 'citizen'; // 'citizen' | 'rescuer'
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isLoading = false;
  File? _govIdFile;

  // ── Animation ────────────────────────────────────────────────────────────────
  late final AnimationController _rescuerFieldsController;
  late final Animation<double> _rescuerFieldsAnimation;

  // ── Colors (from project spec) ────────────────────────────────────────────────
  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _successGreen = Color(0xFF1FAA59);
  static const _warningOrange = Color(0xFFFF6B00);
  static const _background = Color(0xFFF5F7FA);
  static const _textSecondary = Color(0xFF546E7A);

  @override
  void initState() {
    super.initState();
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
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _agencyNameCtrl.dispose();
    _badgeNumberCtrl.dispose();
    super.dispose();
  }

  // ── Role selection ────────────────────────────────────────────────────────────
  void _selectRole(String role) {
    if (_selectedRole == role) return;
    setState(() => _selectedRole = role);
    if (role == 'rescuer') {
      _rescuerFieldsController.forward();
    } else {
      _rescuerFieldsController.reverse();
    }
  }

  // ── Image picker ─────────────────────────────────────────────────────────────
  Future<void> _pickGovId() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _govIdFile = File(picked.path));
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Create Firebase Auth user
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      final uid = credential.user!.uid;

      // 2. Upload gov ID if provided
      String? govIdUrl;
      if (_govIdFile != null) {
        govIdUrl = await StorageService().uploadGovId(uid, _govIdFile!);
      }

      // 3. Write users/{uid}
      final userDoc = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': _selectedRole,
        'blood_type': '',
        'allergies': '',
        'is_active': true,
        'created_at': FieldValue.serverTimestamp(),
      };
      if (govIdUrl != null) userDoc['gov_id_url'] = govIdUrl;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userDoc);

      // 4. If rescuer → write rescuers/{uid}
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

      // 5. AuthProvider auto-routes via StreamBuilder in main app
      if (mounted) {
        context.read<AppAuthProvider>().refreshUser();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showAuthError(e);
    } catch (e) {
      if (mounted) {
        _showSnack('Something went wrong. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAuthError(FirebaseAuthException e) {
    final msg = switch (e.code) {
      'email-already-in-use' => 'An account with this email already exists.',
      'invalid-email' => 'Please enter a valid email address.',
      'weak-password' => 'Password is too weak. Use at least 8 characters.',
      'network-request-failed' => 'No internet connection. Please try again.',
      _ => 'Registration failed: ${e.message ?? e.code}',
    };
    _showSnack(msg, isError: true);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _dangerRed : _successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader()),

              // ── Form ────────────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                sliver: SliverToBoxAdapter(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name row
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _firstNameCtrl,
                                label: 'First Name',
                                icon: Icons.person_outline,
                                validator: _requiredValidator,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildField(
                                controller: _lastNameCtrl,
                                label: 'Last Name',
                                icon: Icons.person_outline,
                                validator: _requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Email
                        _buildField(
                          controller: _emailCtrl,
                          label: 'Email Address',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _emailValidator,
                        ),
                        const SizedBox(height: 16),

                        // Phone
                        _buildField(
                          controller: _phoneCtrl,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: _requiredValidator,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: !_showPassword,
                          suffix: _toggleVisibilityButton(
                            visible: _showPassword,
                            onTap: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                          validator: _passwordValidator,
                        ),
                        const SizedBox(height: 16),

                        // Confirm Password
                        _buildField(
                          controller: _confirmPasswordCtrl,
                          label: 'Confirm Password',
                          icon: Icons.lock_outline,
                          obscureText: !_showConfirmPassword,
                          suffix: _toggleVisibilityButton(
                            visible: _showConfirmPassword,
                            onTap: () => setState(
                              () =>
                                  _showConfirmPassword = !_showConfirmPassword,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (v != _passwordCtrl.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Role selector
                        _buildSectionLabel('I am registering as…'),
                        const SizedBox(height: 10),
                        _buildRoleSelector(),
                        const SizedBox(height: 16),

                        // Rescuer extra fields (animated)
                        SizeTransition(
                          sizeFactor: _rescuerFieldsAnimation,
                          axisAlignment: -1,
                          child: Column(
                            children: [
                              _buildField(
                                controller: _agencyNameCtrl,
                                label: 'Agency / Organization Name',
                                icon: Icons.business_outlined,
                                validator: _selectedRole == 'rescuer'
                                    ? _requiredValidator
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _badgeNumberCtrl,
                                label: 'Badge / ID Number',
                                icon: Icons.badge_outlined,
                                validator: _selectedRole == 'rescuer'
                                    ? _requiredValidator
                                    : null,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),

                        // Gov ID upload
                        _buildSectionLabel('Government ID'),
                        const SizedBox(height: 10),
                        _buildGovIdUploader(),
                        const SizedBox(height: 32),

                        // Submit button
                        _buildSubmitButton(),
                        const SizedBox(height: 20),

                        // Login link
                        _buildLoginLink(),
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

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Logo row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.health_and_safety,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ResQConnect',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    'Disaster Response Network',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            'Create Account',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Join the network. Save lives.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }

  // ── Text field ───────────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: _primaryBlue, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerRed, width: 2),
        ),
      ),
    );
  }

  Widget _toggleVisibilityButton({
    required bool visible,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: _textSecondary,
        size: 20,
      ),
    );
  }

  // ── Role selector ─────────────────────────────────────────────────────────────
  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(child: _buildRoleCard('citizen', 'Citizen', Icons.person)),
        const SizedBox(width: 12),
        Expanded(
          child: _buildRoleCard(
            'rescuer',
            'Rescuer',
            Icons.emergency_share_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(String role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    final color = role == 'rescuer' ? _dangerRed : _primaryBlue;

    return GestureDetector(
      onTap: () => _selectRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFDDE3EA),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? color : const Color(0xFFF0F4F8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : _textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected ? color : _textSecondary,
              ),
            ),
            if (role == 'rescuer') ...[
              const SizedBox(height: 2),
              Text(
                'NDRRMC / LGU',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? color.withOpacity(0.7) : _textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Gov ID uploader ───────────────────────────────────────────────────────────
  Widget _buildGovIdUploader() {
    if (_govIdFile != null) {
      return _buildGovIdPreview();
    }

    return InkWell(
      onTap: _pickGovId,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFB0BEC5),
            width: 1.5,
            // Dashed border via custom painter below
          ),
        ),
        child: Stack(
          children: [
            // Dashed border overlay
            Positioned.fill(
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: const Color(0xFFB0BEC5),
                  radius: 14,
                  dashWidth: 6,
                  dashSpace: 4,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.upload_file_outlined,
                      color: _primaryBlue,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tap to upload Government ID',
                    style: TextStyle(
                      color: _primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UMID, PhilSys, Driver\'s License, Passport',
                    style: TextStyle(
                      color: _textSecondary.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGovIdPreview() {
    return Stack(
      children: [
        Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _successGreen, width: 2),
            boxShadow: [
              BoxShadow(
                color: _successGreen.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            _govIdFile!,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        // Change/remove button
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _iconAction(
                icon: Icons.edit_outlined,
                color: _primaryBlue,
                onTap: _pickGovId,
              ),
              const SizedBox(width: 6),
              _iconAction(
                icon: Icons.close,
                color: _dangerRed,
                onTap: () => setState(() => _govIdFile = null),
              ),
            ],
          ),
        ),
        // Verified badge
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _successGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 13),
                SizedBox(width: 4),
                Text(
                  'ID Selected',
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
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              shadowColor: _primaryBlue.withOpacity(0.4),
            ).copyWith(
              elevation: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return 0;
                return 6;
              }),
            ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.how_to_reg_outlined, size: 20),
            SizedBox(width: 10),
            Text(
              'Create Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Login link ────────────────────────────────────────────────────────────────
  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Already have an account? ',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Text(
            'Sign In',
            style: TextStyle(
              color: _primaryBlue,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ── Validators ────────────────────────────────────────────────────────────────
  String? _requiredValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'This field is required';
    return null;
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email address';
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final dashPath = _createDashedPath(path, dashWidth, dashSpace);
    canvas.drawPath(dashPath, paint);
  }

  Path _createDashedPath(Path source, double dashLen, double gapLen) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) {
          dest.addPath(
            metric.extractPath(distance, distance + len),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
