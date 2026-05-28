import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import 'citizen_home_screen.dart';
import 'rescuer_assigned_screen.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _navy = Color(0xFF080E1E);
const _navyCard = Color(0xFF0F1A2E);
const _red = Color(0xFFD7263D);
const _redGlow = Color(0xFFFF1744);
const _white = Colors.white;
const _muted = Color(0xFF8899AA);

const _holdDuration = Duration(seconds: 3);

// ─── Emergency category model ─────────────────────────────────────────────────

class _Category {
  final String key;
  final IconData icon;
  final String label;
  final Color accent;
  const _Category({
    required this.key,
    required this.icon,
    required this.label,
    required this.accent,
  });
}

const _categories = <_Category>[
  _Category(
    key: 'natural_disaster',
    icon: Icons.storm_rounded,
    label: 'Natural Disaster',
    accent: Color(0xFF1565C0),
  ),
  _Category(
    key: 'accident',
    icon: Icons.car_crash_rounded,
    label: 'Accident',
    accent: Color(0xFFFF6D00),
  ),
  _Category(
    key: 'medical',
    icon: Icons.medical_services_rounded,
    label: 'Medical',
    accent: Color(0xFFE53935),
  ),
  _Category(
    key: 'fire',
    icon: Icons.local_fire_department_rounded,
    label: 'Fire',
    accent: Color(0xFFFF8F00),
  ),
  _Category(
    key: 'crime',
    icon: Icons.security_rounded,
    label: 'Crime',
    accent: Color(0xFF6A1B9A),
  ),
  _Category(
    key: 'rescue',
    icon: Icons.warning_amber_rounded,
    label: 'Rescue / Trapped',
    accent: Color(0xFFF9A825),
  ),
];

// ─── Screen step enum ─────────────────────────────────────────────────────────

enum _SosStep { category, hold, submitting }

// ─── SOS Trigger Screen ───────────────────────────────────────────────────────

class SosTriggerScreen extends StatefulWidget {
  const SosTriggerScreen({super.key});

  @override
  State<SosTriggerScreen> createState() => _SosTriggerScreenState();
}

class _SosTriggerScreenState extends State<SosTriggerScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  _SosStep _step = _SosStep.category;

  // ── Location ───────────────────────────────────────────────────────────────
  double? _lat;
  double? _lng;
  bool _locationReady = false;
  String? _locationError;

  // ── Hold / progress ────────────────────────────────────────────────────────
  Timer? _holdTimer;
  Timer? _countdownTimer;
  bool _isHolding = false;
  int _countdownSeconds = 3;

  // ── Form data ──────────────────────────────────────────────────────────────
  String? _selectedCategory;
  String? _bloodType;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _progressCtrl;
  late final Animation<double> _progressAnim;
  late final AnimationController _slideCtrl;
  late final Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _progressCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _progressAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.linear));

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeOutCubic,
    );

    _initLocation();
    _loadBloodType();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    _slideCtrl.dispose();
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ─── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;
      if (pos != null) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _locationReady = true;
          _locationError = null;
        });
      } else {
        setState(() {
          _locationReady = false;
          _locationError = 'GPS is disabled. Turn it on to proceed.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationReady = false;
        _locationError =
            'Location access denied.\nEnable location to send SOS.';
      });
    }
  }

  // ─── Load blood type ────────────────────────────────────────────────────────

  Future<void> _loadBloodType() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirestoreService.instance.userStream(uid).first;
      if (!mounted) return;
      if (snap != null &&
          snap.bloodType != null &&
          snap.bloodType!.isNotEmpty) {
        setState(() => _bloodType = snap.bloodType);
      }
    } catch (_) {}
  }

  // ─── Navigation between steps ─────────────────────────────────────────────

  void _goToHold() {
    if (_selectedCategory == null) return;
    setState(() => _step = _SosStep.hold);
    _slideCtrl.forward(from: 0);
    _pulseCtrl.repeat(reverse: true);
  }

  void _goBackToCategory() {
    _cancelHold();
    _slideCtrl.reverse();
    Future.delayed(const Duration(milliseconds: 340), () {
      if (!mounted) return;
      setState(() => _step = _SosStep.category);
    });
  }

  // ─── Hold Logic ────────────────────────────────────────────────────────────

  void _onHoldStart(LongPressStartDetails _) {
    if (!_locationReady || _step != _SosStep.hold) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isHolding = true;
      _countdownSeconds = 3;
    });
    _pulseCtrl.stop();
    _progressCtrl.forward(from: 0);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_countdownSeconds > 1) _countdownSeconds--;
      });
      HapticFeedback.lightImpact();
    });
    _holdTimer = Timer(_holdDuration, _onHoldCompleted);
  }

  void _onHoldEnd(LongPressEndDetails _) => _cancelHold();

  void _cancelHold() {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    _progressCtrl.stop();
    _progressCtrl.reset();
    if (_step == _SosStep.hold) _pulseCtrl.repeat(reverse: true);
    if (mounted) {
      setState(() {
        _isHolding = false;
        _countdownSeconds = 3;
      });
    }
  }

  void _onHoldCompleted() {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() {
      _isHolding = false;
      _step = _SosStep.submitting;
    });
    _submitSos();
  }

  // ─── Submit SOS ────────────────────────────────────────────────────────────

  Future<void> _submitSos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _lat == null || _lng == null) {
      setState(() => _step = _SosStep.hold);
      _showError('Authentication error. Please log in again.');
      return;
    }

    // ── Security: block if user already has an active SOS ──────────────────
    try {
      final existing = await FirebaseFirestore.instance
          .collection('sos_requests')
          .where('citizen_id', isEqualTo: uid)
          .where('status', whereIn: ['open', 'assigned'])
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => _step = _SosStep.hold);
        _showError(
          'You already have an active SOS request. '
          'It must be resolved or completed before sending a new one.',
        );
        return;
      }
    } catch (_) {
      // If the check fails, still allow submission — fail open for safety
    }

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('sos_requests')
          .add({
            'citizen_id': uid,
            'latitude': _lat,
            'longitude': _lng,
            'status': 'open',
            'category': _selectedCategory,
            if (_bloodType != null && _bloodType!.isNotEmpty)
              'blood_type': _bloodType,
            'created_at': FieldValue.serverTimestamp(),
            'assigned_rescuer_id': null,
          });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RescuerAssignedScreen(sosId: docRef.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _SosStep.hold);
      _showError('Failed to send SOS. Check your connection and try again.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: _red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  // ─── Cancel ────────────────────────────────────────────────────────────────

  void _onCancel() {
    if (_step == _SosStep.submitting) return;
    _cancelHold();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CitizenHomeScreen()),
      (route) => false,
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background glow during hold
          if (_step == _SosStep.hold)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _progressAnim,
                builder: (_, __) {
                  final g = _isHolding ? _progressAnim.value : 0.0;
                  return CustomPaint(painter: _BgGlowPainter(g));
                },
              ),
            ),

          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildCurrentStep(),
            ),
          ),

          if (_step == _SosStep.submitting) const _SubmittingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _SosStep.category:
        return _buildCategoryStep();
      case _SosStep.hold:
        return _buildHoldStep();
      case _SosStep.submitting:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1 — Category selection
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryStep() {
    return Column(
      key: const ValueKey('category'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(onBack: _onCancel),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                const Text(
                  'EMERGENCY SOS',
                  style: TextStyle(
                    color: _white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'What type of emergency?',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: _categories
                      .map((cat) => _buildCategoryTile(cat))
                      .toList(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _selectedCategory != null ? _goToHold : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedCategory != null
                          ? _red
                          : _navyCard,
                      disabledBackgroundColor: _navyCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: _selectedCategory != null ? 4 : 0,
                      shadowColor: _red.withValues(alpha: 0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sos_rounded,
                          size: 20,
                          color: _selectedCategory != null ? _white : _muted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Next',
                          style: TextStyle(
                            color: _selectedCategory != null ? _white : _muted,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (_selectedCategory != null) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: _white,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildCancelButton(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTile(_Category cat) {
    final isSelected = _selectedCategory == cat.key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedCategory = cat.key);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? cat.accent.withValues(alpha: 0.18) : _navyCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? cat.accent
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cat.accent.withValues(alpha: 0.22),
                    blurRadius: 10,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(cat.icon, size: 28, color: isSelected ? cat.accent : _muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cat.label,
                style: TextStyle(
                  color: isSelected ? cat.accent : _muted,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — Hold SOS button
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHoldStep() {
    final cat = _categories.firstWhere((c) => c.key == _selectedCategory!);

    return AnimatedBuilder(
      key: const ValueKey('hold'),
      animation: _slideAnim,
      builder: (_, child) => FractionalTranslation(
        translation: Offset(0, 1 - _slideAnim.value),
        child: child,
      ),
      child: Column(
        children: [
          _buildTopBar(onBack: _goBackToCategory),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Category summary pill
                _SummaryPill(
                  icon: cat.icon,
                  label: cat.label,
                  color: cat.accent,
                ),

                const SizedBox(height: 40),
                AnimatedOpacity(
                  opacity: _isHolding ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Text(
                    'EMERGENCY SOS',
                    style: TextStyle(
                      color: _white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedOpacity(
                  opacity: _isHolding ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _locationError != null
                        ? 'Enable location to send SOS'
                        : 'Hold for 3 seconds to send',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 48),

                // Hold button
                GestureDetector(
                  onLongPressStart: _locationReady ? _onHoldStart : null,
                  onLongPressEnd: _locationReady ? _onHoldEnd : null,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulseAnim, _progressAnim]),
                    builder: (_, __) {
                      final scale = _isHolding ? 0.95 : _pulseAnim.value;
                      return Transform.scale(
                        scale: scale,
                        child: _SosButtonWithRing(
                          progress: _progressAnim.value,
                          isHolding: _isHolding,
                          countdownSeconds: _countdownSeconds,
                          isDisabled: !_locationReady,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 40),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isHolding
                      ? Text(
                          key: const ValueKey('holding'),
                          'Sending in $_countdownSeconds…',
                          style: const TextStyle(
                            color: _redGlow,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        )
                      : Text(
                          key: const ValueKey('idle'),
                          _locationReady
                              ? 'Press and hold the button above'
                              : 'Location required',
                          style: const TextStyle(color: _muted, fontSize: 14),
                        ),
                ),
              ],
            ),
          ),
          _buildCancelButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Shared widgets ────────────────────────────────────────────────────────

  Widget _buildTopBar({required VoidCallback onBack}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: _white,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _locationError != null
                ? _LocationPill(
                    key: const ValueKey('err'),
                    icon: Icons.location_off_rounded,
                    label: 'Location Off',
                    color: _red,
                  )
                : _locationReady
                ? _LocationPill(
                    key: const ValueKey('ok'),
                    icon: Icons.location_on_rounded,
                    label: 'Location Ready',
                    color: const Color(0xFF1FAA59),
                  )
                : _LocationPill(
                    key: const ValueKey('loading'),
                    icon: Icons.gps_not_fixed_rounded,
                    label: 'Getting Location…',
                    color: const Color(0xFFFF6B00),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return Center(
      child: TextButton(
        onPressed: _step == _SosStep.submitting ? null : _onCancel,
        style: TextButton.styleFrom(foregroundColor: _muted),
        child: const Text(
          'Cancel',
          style: TextStyle(fontSize: 15, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

// ─── Summary Pill ─────────────────────────────────────────────────────────────

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SOS Button + Progress Ring ───────────────────────────────────────────────

class _SosButtonWithRing extends StatelessWidget {
  final double progress;
  final bool isHolding;
  final int countdownSeconds;
  final bool isDisabled;

  const _SosButtonWithRing({
    required this.progress,
    required this.isHolding,
    required this.countdownSeconds,
    required this.isDisabled,
  });

  @override
  Widget build(BuildContext context) {
    const outerSize = 220.0;
    const innerSize = 172.0;

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(outerSize, outerSize),
            painter: _RingPainter(progress: progress, isDisabled: isDisabled),
          ),
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDisabled
                  ? const Color(0xFF3A3A4A)
                  : isHolding
                  ? _redGlow
                  : _red,
              boxShadow: isDisabled
                  ? []
                  : [
                      BoxShadow(
                        color: _red.withValues(alpha: isHolding ? 0.7 : 0.45),
                        blurRadius: isHolding ? 48 : 28,
                        spreadRadius: isHolding ? 8 : 2,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sos_rounded,
                  color: isDisabled ? Colors.white30 : Colors.white,
                  size: 52,
                ),
                if (isHolding) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$countdownSeconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final bool isDisabled;
  const _RingPainter({required this.progress, required this.isDisabled});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const sw = 5.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0 || isDisabled) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: const [_red, _redGlow, _red],
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final dotAngle = -math.pi / 2 + 2 * math.pi * progress;
    canvas.drawCircle(
      Offset(
        center.dx + radius * math.cos(dotAngle),
        center.dy + radius * math.sin(dotAngle),
      ),
      sw / 2 + 1,
      Paint()..color = _redGlow,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─── Background Glow ──────────────────────────────────────────────────────────

class _BgGlowPainter extends CustomPainter {
  final double intensity;
  const _BgGlowPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            _red.withValues(alpha: 0.18 * intensity),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_BgGlowPainter old) => old.intensity != intensity;
}

// ─── Location Pill ────────────────────────────────────────────────────────────

class _LocationPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _LocationPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Submitting Overlay ───────────────────────────────────────────────────────

class _SubmittingOverlay extends StatelessWidget {
  const _SubmittingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navy.withValues(alpha: 0.85),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(strokeWidth: 3, color: _redGlow),
            ),
            SizedBox(height: 20),
            Text(
              'Sending SOS…',
              style: TextStyle(
                color: _white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Alerting nearby rescuers',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
