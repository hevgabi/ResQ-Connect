import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'
    hide AuthProvider; // FIX: Inawasan ang clash sa pangalan
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
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _agencyNameCtrl = TextEditingController();
  final _badgeNumberCtrl = TextEditingController();

  String _selectedRole = 'citizen';
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isLoading = false;
  File? _govIdFile;

  late final AnimationController _rescuerFieldsController;
  late final Animation<double> _rescuerFieldsAnimation;

  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _successGreen = Color(0xFF1FAA59);
  static const _textSecondary = Color(0xFF546E7A);
  static const _background = Color(0xFFF5F7FA);

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

  void _selectRole(String role) {
    if (_selectedRole == role || _isLoading) return;
    setState(() => _selectedRole = role);
    if (role == 'rescuer') {
      _rescuerFieldsController.forward();
    } else {
      _rescuerFieldsController.reverse();
    }
  }

  Future<void> _pickGovId() async {
    if (_isLoading) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _govIdFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    setState(() => _isLoading = true);
    User? createdUser;

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      createdUser = credential.user;
      final uid = createdUser!.uid;

      String? govIdUrl;
      if (_govIdFile != null) {
        // FIX: Ginamit ang .instance imbes na constructor
        govIdUrl = await StorageService.instance.uploadGovId(uid, _govIdFile!);
      }

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

      if (mounted) {
        authProvider.refreshRole();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showAuthError(e);
    } catch (e) {
      if (createdUser != null) {
        try {
          await createdUser.delete();
        } catch (rollbackError) {
          debugPrint('Atomic rollback failed: $rollbackError');
        }
      }
      if (mounted)
        _showSnack('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAuthError(FirebaseAuthException e) {
    final msg = switch (e.code) {
      'email-already-in-use' => 'An account with this email already exists.',
      'invalid-email' => 'Please enter a valid email address.',
      'weak-password' => 'Password is too weak.',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                sliver: SliverToBoxAdapter(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _firstNameCtrl,
                                label: 'First Name',
                                icon: Icons.person_outline,
                                validator: (v) =>
                                    v!.isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildField(
                                controller: _lastNameCtrl,
                                label: 'Last Name',
                                icon: Icons.person_outline,
                                validator: (v) =>
                                    v!.isEmpty ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _emailCtrl,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _phoneCtrl,
                          label: 'Phone',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: !_showPassword,
                        ),
                        const SizedBox(height: 24),
                        _buildRoleSelector(),
                        const SizedBox(height: 16),
                        SizeTransition(
                          sizeFactor: _rescuerFieldsAnimation,
                          child: Column(
                            children: [
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
                            ),
                            child: const Text(
                              'Create Account',
                              style: TextStyle(color: Colors.white),
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

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(24),
    color: _primaryBlue,
    child: const Text(
      'Registration',
      style: TextStyle(color: Colors.white, fontSize: 24),
    ),
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
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Widget _buildRoleSelector() => Row(
    children: [
      Expanded(
        child: ElevatedButton(
          onPressed: () => _selectRole('citizen'),
          child: const Text('Citizen'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: () => _selectRole('rescuer'),
          child: const Text('Rescuer'),
        ),
      ),
    ],
  );
}
