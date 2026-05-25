import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/storage_service.dart';

// ─── Pending Registration Data (passed from register screen) ─────────────────

class PendingRegistrationData {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String phone;
  final String gender;
  final String street;
  final String city;
  final String province;
  final String zip;
  final String role;
  final File? govIdFile;
  final String? agencyName;
  final String? badgeNumber;

  const PendingRegistrationData({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.gender,
    required this.street,
    required this.city,
    required this.province,
    required this.zip,
    required this.role,
    this.govIdFile,
    this.agencyName,
    this.badgeNumber,
  });
}

// ─── OTP Purpose Enum ────────────────────────────────────────────────────────

enum OtpPurpose { registration, forgotPassword }

// ─── OTP Helper (generate + send via Firestore → Trigger Email extension) ───

class OtpHelper {
  static final _firestore = FirebaseFirestore.instance;

  /// Generates a 6-digit OTP, stores it in Firestore (expires in 5 mins),
  /// and triggers the Firebase "Trigger Email" extension to send the email.
  static Future<String> generateAndSend({
    required String email,
    required OtpPurpose purpose,
  }) async {
    final otp = (100000 + Random.secure().nextInt(900000)).toString();
    final expiry = DateTime.now().add(const Duration(minutes: 5));

    // Store OTP in Firestore
    await _firestore.collection('otps').doc(email).set({
      'otp': otp,
      'purpose': purpose.name,
      'expires_at': Timestamp.fromDate(expiry),
      'verified': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    // Trigger email via Firebase Extension (writes to 'mail' collection)
    final subject = purpose == OtpPurpose.registration
        ? 'ResQConnect – Verify Your Email'
        : 'ResQConnect – Password Reset OTP';

    final bodyHtml = purpose == OtpPurpose.registration
        ? _registrationEmailHtml(otp)
        : _forgotPasswordEmailHtml(otp);

    await _firestore.collection('mail').add({
      'to': email,
      'message': {'subject': subject, 'html': bodyHtml},
    });

    return otp;
  }

  /// Verifies the OTP entered by the user against the stored one.
  /// Returns null if valid, or an error message string if invalid.
  static Future<String?> verify({
    required String email,
    required String enteredOtp,
    required OtpPurpose purpose,
  }) async {
    final doc = await _firestore.collection('otps').doc(email).get();
    if (!doc.exists) return 'OTP not found. Please request a new one.';

    final data = doc.data()!;
    final storedOtp = data['otp'] as String?;
    final expiresAt = (data['expires_at'] as Timestamp).toDate();
    final verified = data['verified'] as bool? ?? false;
    final storedPurpose = data['purpose'] as String?;

    if (verified) return 'This OTP has already been used.';
    if (storedPurpose != purpose.name) return 'Invalid OTP. Please try again.';
    if (DateTime.now().isAfter(expiresAt)) {
      return 'OTP has expired. Please request a new one.';
    }
    if (storedOtp != enteredOtp) return 'Incorrect OTP. Please try again.';

    // Mark as verified
    await _firestore.collection('otps').doc(email).update({'verified': true});
    return null; // success
  }

  static String _registrationEmailHtml(String otp) =>
      '''
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#F5F7FA;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center" style="padding:40px 16px;">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
        <tr><td style="background:#0D47A1;padding:32px;text-align:center;">
          <div style="font-size:28px;font-weight:800;color:#fff;letter-spacing:-0.5px;">ResQConnect</div>
          <div style="font-size:13px;color:rgba(255,255,255,0.7);margin-top:4px;">Disaster Response Network · Philippines</div>
        </td></tr>
        <tr><td style="padding:40px 32px;text-align:center;">
          <div style="font-size:20px;font-weight:700;color:#263238;margin-bottom:8px;">Verify Your Email Address</div>
          <div style="font-size:14px;color:#546E7A;line-height:1.6;margin-bottom:32px;">
            Use the code below to verify your email and complete your registration.
          </div>
          <div style="background:#F5F7FA;border:2px dashed #0D47A1;border-radius:12px;padding:24px;margin-bottom:32px;">
            <div style="font-size:42px;font-weight:800;color:#0D47A1;letter-spacing:12px;">$otp</div>
            <div style="font-size:12px;color:#90A4AE;margin-top:8px;">Expires in 5 minutes</div>
          </div>
          <div style="font-size:12px;color:#90A4AE;line-height:1.6;">
            If you did not create a ResQConnect account, you can safely ignore this email.
          </div>
        </td></tr>
        <tr><td style="background:#F5F7FA;padding:20px 32px;text-align:center;">
          <div style="font-size:11px;color:#B0BEC5;">© 2025 ResQConnect · Philippines</div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
''';

  static String _forgotPasswordEmailHtml(String otp) =>
      '''
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#F5F7FA;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center" style="padding:40px 16px;">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
        <tr><td style="background:#0D47A1;padding:32px;text-align:center;">
          <div style="font-size:28px;font-weight:800;color:#fff;letter-spacing:-0.5px;">ResQConnect</div>
          <div style="font-size:13px;color:rgba(255,255,255,0.7);margin-top:4px;">Disaster Response Network · Philippines</div>
        </td></tr>
        <tr><td style="padding:40px 32px;text-align:center;">
          <div style="font-size:20px;font-weight:700;color:#263238;margin-bottom:8px;">Password Reset Request</div>
          <div style="font-size:14px;color:#546E7A;line-height:1.6;margin-bottom:32px;">
            Enter the code below in the app to reset your password.
          </div>
          <div style="background:#F5F7FA;border:2px dashed #D7263D;border-radius:12px;padding:24px;margin-bottom:32px;">
            <div style="font-size:42px;font-weight:800;color:#D7263D;letter-spacing:12px;">$otp</div>
            <div style="font-size:12px;color:#90A4AE;margin-top:8px;">Expires in 5 minutes</div>
          </div>
          <div style="font-size:12px;color:#90A4AE;line-height:1.6;">
            If you did not request a password reset, please ignore this email.<br/>Your password will remain unchanged.
          </div>
        </td></tr>
        <tr><td style="background:#F5F7FA;padding:20px 32px;text-align:center;">
          <div style="font-size:11px;color:#B0BEC5;">© 2025 ResQConnect · Philippines</div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
''';
}

// ─── OTP Verification Screen ─────────────────────────────────────────────────

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final OtpPurpose purpose;

  /// Only required when purpose == OtpPurpose.forgotPassword
  /// After OTP verified, we navigate to reset password screen
  final VoidCallback? onVerified;

  /// Only required when purpose == OtpPurpose.registration
  /// Contains all user data to create the account after OTP is verified
  final PendingRegistrationData? pendingRegistration;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.purpose,
    this.onVerified,
    this.pendingRegistration,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with SingleTickerProviderStateMixin {
  // ─── OTP input (6 separate fields) ───────────────────────────────────────
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  // ─── State ────────────────────────────────────────────────────────────────
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  // ─── Countdown timer (5 min = 300s) ──────────────────────────────────────
  int _secondsLeft = 300;
  Timer? _timer;

  // ─── Colors ───────────────────────────────────────────────────────────────
  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _successGreen = Color(0xFF1FAA59);
  static const _background = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  // ─── Timer ────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 300);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  String get _timerText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isExpired => _secondsLeft <= 0;

  // ─── OTP input handling ───────────────────────────────────────────────────

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste — distribute across fields
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      final nextEmpty = _controllers.indexWhere((c) => c.text.isEmpty);
      if (nextEmpty != -1) {
        _focusNodes[nextEmpty].requestFocus();
      } else {
        _focusNodes[5].requestFocus();
        _verifyOtp();
      }
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Auto-submit when all 6 filled
    if (_enteredOtp.length == 6 && !_controllers.any((c) => c.text.isEmpty)) {
      Future.delayed(const Duration(milliseconds: 100), _verifyOtp);
    }

    setState(() => _errorMessage = null);
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  void _clearOtp() {
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
    setState(() => _errorMessage = null);
  }

  // ─── Verify ───────────────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    if (_isVerifying || _isExpired) return;
    final otp = _enteredOtp;
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final error = await OtpHelper.verify(
        email: widget.email,
        enteredOtp: otp,
        purpose: widget.purpose,
      );

      if (!mounted) return;

      if (error != null) {
        setState(() => _errorMessage = error);
        _clearOtp();
      } else {
        _timer?.cancel();
        // Success
        if (widget.purpose == OtpPurpose.registration) {
          // ── OTP verified — NOW create the Firebase Auth account + Firestore ──
          final pending = widget.pendingRegistration;
          if (pending == null) {
            setState(
              () => _errorMessage =
                  'Registration data missing. Please register again.',
            );
            return;
          }

          try {
            // 1. Create the Firebase Auth account
            final credential = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(
                  email: pending.email,
                  password: pending.password,
                );
            final uid = credential.user!.uid;

            // 2. Upload gov ID if present (user is now authenticated)
            String? govIdUrl;
            if (pending.govIdFile != null) {
              govIdUrl = await StorageService.instance.uploadGovId(
                uid,
                pending.govIdFile!,
              );
            }

            // 3. Write Firestore user doc
            final userDoc = <String, dynamic>{
              'first_name': pending.firstName,
              'last_name': pending.lastName,
              'email': pending.email,
              'phone': pending.phone,
              'gender': pending.gender,
              'address': {
                'street': pending.street,
                'city': pending.city,
                'province': pending.province,
                'zip': pending.zip,
              },
              'role': pending.role,
              'blood_type': '',
              'allergies': '',
              'is_active': false,
              'is_email_verified': true,
              // OTP already verified — go straight to 'pending' for admin review
              'approval_status': 'pending',
              'created_at': FieldValue.serverTimestamp(),
            };
            if (govIdUrl != null) userDoc['gov_id_url'] = govIdUrl;

            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .set(userDoc);

            // 4. Write rescuer doc if applicable
            if (pending.role == 'rescuer') {
              await FirebaseFirestore.instance
                  .collection('rescuers')
                  .doc(uid)
                  .set({
                    'user_id': uid,
                    'agency_name': pending.agencyName ?? '',
                    'badge_number': pending.badgeNumber ?? '',
                    'is_on_duty': false,
                    'team_capacity_max': 5,
                    'active_mission_count': 0,
                  });
            }

            // 5. Sign out — account needs admin approval before login
            await FirebaseAuth.instance.signOut();

            if (mounted) _showSuccessAndPop();
          } on FirebaseAuthException catch (e) {
            final msg = e.code == 'email-already-in-use'
                ? 'An account with this email already exists.'
                : 'Account creation failed: ${e.message ?? e.code}';
            setState(() => _errorMessage = msg);
          } catch (_) {
            setState(
              () =>
                  _errorMessage = 'Account creation failed. Please try again.',
            );
          }
        } else {
          // Forgot password — callback to show reset screen
          widget.onVerified?.call();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showSuccessAndPop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _successGreen.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: _successGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Email Verified!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF263238),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your account is now pending admin approval. You\'ll be notified once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF546E7A),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  Navigator.of(context).pushReplacementNamed('/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _successGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to Sign In',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Resend ───────────────────────────────────────────────────────────────

  Future<void> _resendOtp() async {
    if (_isResending) return;
    setState(() => _isResending = true);
    try {
      await OtpHelper.generateAndSend(
        email: widget.email,
        purpose: widget.purpose,
      );
      _clearOtp();
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('New OTP sent to your email.'),
              ],
            ),
            backgroundColor: _successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Failed to resend OTP. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isRegistration = widget.purpose == OtpPurpose.registration;
    final accentColor = isRegistration ? _primaryBlue : _dangerRed;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (widget.purpose == OtpPurpose.registration) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Icon(
                    isRegistration
                        ? Icons.mark_email_unread_outlined
                        : Icons.lock_reset_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isRegistration ? 'Verify Your Email' : 'Enter OTP Code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We sent a 6-digit code to\n${widget.email}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Timer ────────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _isExpired
                            ? _dangerRed.withAlpha(15)
                            : accentColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isExpired
                              ? _dangerRed.withAlpha(60)
                              : accentColor.withAlpha(40),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isExpired
                                ? Icons.timer_off_outlined
                                : Icons.timer_outlined,
                            size: 18,
                            color: _isExpired ? _dangerRed : accentColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isExpired
                                ? 'OTP expired — request a new one'
                                : 'Code expires in $_timerText',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _isExpired ? _dangerRed : accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── OTP Fields ───────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        6,
                        (i) => _buildOtpBox(i, accentColor),
                      ),
                    ),

                    // ── Error message ────────────────────────────────────────
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _dangerRed.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _dangerRed.withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: _dangerRed,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _dangerRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // ── Verify Button ────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isVerifying || _isExpired)
                            ? null
                            : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          disabledBackgroundColor: accentColor.withAlpha(100),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Verify Code',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Resend ───────────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Didn't receive the code? ",
                          style: TextStyle(
                            color: Color(0xFF546E7A),
                            fontSize: 13,
                          ),
                        ),
                        TextButton(
                          onPressed: _isResending ? null : _resendOtp,
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _isResending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _primaryBlue,
                                  ),
                                )
                              : Text(
                                  'Resend OTP',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Info note ────────────────────────────────────────────
                    if (widget.purpose == OtpPurpose.registration)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _successGreen.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _successGreen.withAlpha(50),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: _successGreen,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'After verifying your email, your account will be reviewed by an admin within 1–3 business days.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2E7D32),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index, Color accentColor) {
    return SizedBox(
      width: 46,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (e) => _onKeyEvent(index, e),
        child: TextFormField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6, // allows paste
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: accentColor,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: _controllers[index].text.isNotEmpty
                ? accentColor.withAlpha(15)
                : Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFFCFD8DC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _controllers[index].text.isNotEmpty
                    ? accentColor
                    : const Color(0xFFCFD8DC),
                width: _controllers[index].text.isNotEmpty ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _dangerRed, width: 2),
            ),
          ),
          onChanged: (v) => _onOtpChanged(index, v),
        ),
      ),
    );
  }
}
