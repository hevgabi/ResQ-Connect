import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/auth_provider.dart';
import '../../main.dart' show RootRouter;
import 'forgot_password_screen.dart';
import 'google_complete_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ─── Controllers ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ─── UI State ────────────────────────────────────────────────────────────────
  bool _obscurePassword = true;
  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;

  // ─── Animation ───────────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ─── Colors (mirror app_theme.dart) ──────────────────────────────────────────
  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _background = Color(0xFFF5F7FA);
  static const _textSecondary = Color(0xFF546E7A);
  static const _cardWhite = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  bool get _anyLoading => _isEmailLoading || _isGoogleLoading;

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _dangerRed : const Color(0xFF1FAA59),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'user-not-found':
        return 'No account found with that email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return 'Sign-in failed. Please try again. (${e.code})';
    }
  }

  // ─── Auth Actions ─────────────────────────────────────────────────────────────

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isEmailLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Replace the entire stack with RootRouter so it can route to the
      // correct home screen based on the user's role. This handles both
      // normal login and login-after-logout correctly.
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RootRouter()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_friendlyError(e));
    } catch (_) {
      _showSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isEmailLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await GoogleSignIn(
        scopes: ['email', 'profile'],
      ).signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final firebaseUser = result.user;
      if (firebaseUser == null) {
        _showSnackBar('Google sign-in failed. Please try again.');
        return;
      }

      // Check if this Google user already has a Firestore doc (existing user)
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        // Existing user — let RootRouter handle routing (pending / approved / etc.)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RootRouter()),
          (route) => false,
        );
      } else {
        // New Google user — complete profile first
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                GoogleCompleteProfileScreen(googleUser: firebaseUser),
          ),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_friendlyError(e));
    } catch (_) {
      _showSnackBar('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _forgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 52),

                  // ── Branding ──────────────────────────────────────────────
                  _BrandingHeader(),

                  const SizedBox(height: 40),

                  // ── Form Card ─────────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: _cardWhite,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Email
                          _buildLabel('Email Address'),
                          const SizedBox(height: 6),
                          _EmailField(controller: _emailController),

                          const SizedBox(height: 18),

                          // Password
                          _buildLabel('Password'),
                          const SizedBox(height: 6),
                          _PasswordField(
                            controller: _passwordController,
                            obscure: _obscurePassword,
                            onToggle: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),

                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _anyLoading ? null : _forgotPassword,
                              style: TextButton.styleFrom(
                                foregroundColor: _primaryBlue,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Sign In button
                          _SignInButton(
                            isLoading: _isEmailLoading,
                            disabled: _anyLoading,
                            onPressed: _signInWithEmail,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Divider ───────────────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFFCFD8DC))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(color: _textSecondary, fontSize: 13),
                        ),
                      ),
                      const Expanded(child: Divider(color: Color(0xFFCFD8DC))),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Google Sign-In ────────────────────────────────────────
                  _GoogleButton(
                    isLoading: _isGoogleLoading,
                    disabled: _anyLoading,
                    onPressed: _signInWithGoogle,
                  ),

                  const SizedBox(height: 32),

                  // ── Sign Up link ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(color: _textSecondary, fontSize: 14),
                      ),
                      TextButton(
                        onPressed: _anyLoading
                            ? null
                            : () => Navigator.pushNamed(context, '/register'),
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryBlue,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF37474F),
        letterSpacing: 0.1,
      ),
    );
  }
}

// ─── Branding Header ──────────────────────────────────────────────────────────

class _BrandingHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo mark
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF0D47A1),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D47A1).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'ResQConnect',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0D47A1),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Disaster Response Network · Philippines',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF546E7A),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ─── Email Field ──────────────────────────────────────────────────────────────

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  const _EmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      style: const TextStyle(fontSize: 15),
      decoration: _inputDecoration(
        hint: 'you@example.com',
        prefixIcon: Icons.email_outlined,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email is required.';
        final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
        if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email.';
        return null;
      },
    );
  }
}

// ─── Password Field ───────────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 15),
      decoration: _inputDecoration(
        hint: '••••••••',
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
            color: const Color(0xFF546E7A),
          ),
          onPressed: onToggle,
          splashRadius: 20,
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required.';
        if (v.length < 6) return 'Password must be at least 6 characters.';
        return null;
      },
    );
  }
}

// ─── Sign In Button ───────────────────────────────────────────────────────────

class _SignInButton extends StatelessWidget {
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const _SignInButton({
    required this.isLoading,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(
            0xFF0D47A1,
          ).withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

// ─── Google Button ────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final bool disabled;
  final VoidCallback onPressed;

  const _GoogleButton({
    required this.isLoading,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: disabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF37474F),
          side: const BorderSide(color: Color(0xFFCFD8DC), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF546E7A)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google "G" logo — painted with Canvas for zero dependency
                  _GoogleLogoIcon(),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Draws Google's four-color "G" logo with CustomPaint — no image asset needed.
class _GoogleLogoIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(22, 22), painter: _GoogleLogoPainter());
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    // Background circle
    paint.color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Red (top-left arc)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
      _deg(-225),
      _deg(120),
      true,
      paint,
    );

    // Blue (bottom arc)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
      _deg(-105),
      _deg(140),
      true,
      paint,
    );

    // Green (top-right arc)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
      _deg(35),
      _deg(82),
      true,
      paint,
    );

    // Yellow (small arc)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
      _deg(-225),
      _deg(-38),
      true,
      paint,
    );

    // Inner white circle to carve out ring
    paint.color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r * 0.50, paint);

    // Horizontal bar of the "G"
    paint.color = const Color(0xFF4285F4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 0.5, cy - r * 0.14, r * 0.90, r * 0.28),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  double _deg(double degrees) => degrees * (3.14159265 / 180);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Shared Input Decoration ──────────────────────────────────────────────────

InputDecoration _inputDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14),
    prefixIcon: Icon(prefixIcon, size: 20, color: const Color(0xFF90A4AE)),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF5F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD7263D), width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD7263D), width: 1.8),
    ),
    errorStyle: const TextStyle(fontSize: 12, color: Color(0xFFD7263D)),
  );
}
