import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/location_service.dart';
import 'rescuer_assigned_screen.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _navy = Color(0xFF080E1E);
const _navyLight = Color(0xFF0F1A2E);
const _dangerRed = Color(0xFFD7263D);
const _dangerRedGlow = Color(0xFFFF1744);
const _textWhite = Colors.white;
const _textMuted = Color(0xFF8899AA);

const _holdDuration = Duration(seconds: 3);

// ─── SOS Trigger Screen ───────────────────────────────────────────────────────

class SosTriggerScreen extends StatefulWidget {
  const SosTriggerScreen({super.key});

  @override
  State<SosTriggerScreen> createState() => _SosTriggerScreenState();
}

class _SosTriggerScreenState extends State<SosTriggerScreen>
    with TickerProviderStateMixin {
  // ── Location ──────────────────────────────────────────────────────────────
  double? _lat;
  double? _lng;
  bool _locationReady = false;
  String? _locationError;

  // ── Hold / progress ───────────────────────────────────────────────────────
  Timer? _holdTimer;
  bool _isHolding = false;
  bool _isSubmitting = false;

  // ── Animations ────────────────────────────────────────────────────────────

  // Continuous idle pulse on the red button
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Progress ring fills over 3 s during hold
  late final AnimationController _progressCtrl;
  late final Animation<double> _progressAnim;

  // Countdown integer displayed inside the ring (3 → 2 → 1)
  int _countdownSeconds = 3;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    // Idle pulse: scale 1.0 → 1.06 → 1.0, repeat
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Progress ring
    _progressCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _progressAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.linear));

    _initLocation();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ─── Location ─────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;

      // FIX: Nilagyan ng null check para siguradong may maipasang coordinates
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

  // ─── Hold Logic ───────────────────────────────────────────────────────────

  void _onHoldStart(LongPressStartDetails _) {
    if (!_locationReady || _isSubmitting) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isHolding = true;
      _countdownSeconds = 3;
    });

    // Pause idle pulse while holding
    _pulseCtrl.stop();
    _progressCtrl.forward(from: 0);

    // Tick countdown every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_countdownSeconds > 1) {
          _countdownSeconds--;
        }
      });
      HapticFeedback.lightImpact();
    });

    // Fire after full hold duration
    _holdTimer = Timer(_holdDuration, _onHoldCompleted);
  }

  void _onHoldEnd(LongPressEndDetails _) {
    if (_isSubmitting) return;
    _cancelHold();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    _progressCtrl.stop();
    _progressCtrl.reset();
    _pulseCtrl.repeat(reverse: true);

    if (mounted) {
      setState(() {
        _isHolding = false;
        _countdownSeconds = 3;
      });
    }
  }

  Future<void> _onHoldCompleted() async {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    HapticFeedback.heavyImpact();

    if (!mounted) return;
    setState(() {
      _isHolding = false;
      _isSubmitting = true;
    });

    await _submitSos();
  }

  // ─── Submit SOS ───────────────────────────────────────────────────────────

  Future<void> _submitSos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _lat == null || _lng == null) {
      setState(() => _isSubmitting = false);
      _showError('Authentication error. Please log in again.');
      return;
    }

    try {
      // Sinisigurado na tugma ang field names sa tinatanggap ng RescuerAssignedScreen
      final docRef = await FirebaseFirestore.instance
          .collection('sos_requests')
          .add({
            'citizen_id': uid,
            'latitude': _lat, // database model compatible
            'longitude': _lng, // database model compatible
            'status': 'open',
            'created_at': FieldValue.serverTimestamp(),
            'assigned_rescuer_id': null,
          });

      if (!mounted) return;

      // Replace route — hindi na pwedeng bumalik sa hold trigger screen kapag nasend na
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RescuerAssignedScreen(sosId: docRef.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _pulseCtrl.repeat(reverse: true);
      _showError('Failed to send SOS. Check your connection and try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _dangerRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  // ─── Cancel / Back ────────────────────────────────────────────────────────

  void _onCancel() {
    if (_isSubmitting) return;
    _cancelHold();
    Navigator.pop(context);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        children: [
          // ── Radial background glow ──────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (_, __) {
                final glow = _isHolding ? _progressAnim.value : 0.0;
                return CustomPaint(painter: _BackgroundGlowPainter(glow));
              },
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
                _buildBottomBar(),
              ],
            ),
          ),

          // ── Loading overlay ────────────────────────────────────────────
          if (_isSubmitting) const _SubmittingOverlay(),
        ],
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Back arrow (only if not submitting)
          if (!_isSubmitting)
            GestureDetector(
              onTap: _onCancel,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: _textWhite,
                  size: 20,
                ),
              ),
            ),
          const Spacer(),
          // Location status pill
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _locationError != null
                ? _LocationPill(
                    key: const ValueKey('err'),
                    icon: Icons.location_off_rounded,
                    label: 'Location Off',
                    color: _dangerRed,
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

  // ── Body ────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Instruction text
        AnimatedOpacity(
          opacity: _isHolding ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: const Text(
            'EMERGENCY SOS',
            style: TextStyle(
              color: _textWhite,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
            ),
          ),
        ),

        const SizedBox(height: 8),

        AnimatedOpacity(
          opacity: _isHolding ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Text(
            _locationError != null
                ? 'Enable location to send SOS'
                : 'Hold button for 3 seconds to send SOS',
            style: const TextStyle(
              color: _textMuted,
              fontSize: 14,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 56),

        // SOS Button with progress ring
        GestureDetector(
          onLongPressStart: _locationReady ? _onHoldStart : null,
          onLongPressEnd: _locationReady ? _onHoldEnd : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseAnim, _progressAnim]),
            builder: (_, child) {
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

        const SizedBox(height: 48),

        // Hold progress label
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isHolding
              ? Text(
                  key: const ValueKey('holding'),
                  'Sending in $_countdownSeconds…',
                  style: const TextStyle(
                    color: _dangerRedGlow,
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
                  style: const TextStyle(color: _textMuted, fontSize: 14),
                ),
        ),
      ],
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          if (_locationError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton.icon(
                onPressed: _initLocation,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: Color(0xFFFF6B00),
                ),
                label: const Text(
                  'Retry Location',
                  style: TextStyle(color: Color(0xFFFF6B00)),
                ),
              ),
            ),
          TextButton(
            onPressed: _isSubmitting ? null : _onCancel,
            style: TextButton.styleFrom(foregroundColor: _textMuted),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 15, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SOS Button + Ring ────────────────────────────────────────────────────────

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
          // Progress ring
          CustomPaint(
            size: const Size(outerSize, outerSize),
            painter: _RingPainter(progress: progress, isDisabled: isDisabled),
          ),

          // Core button
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDisabled
                  ? const Color(0xFF3A3A4A)
                  : isHolding
                  ? _dangerRedGlow
                  : _dangerRed,
              boxShadow: isDisabled
                  ? []
                  : [
                      BoxShadow(
                        color: _dangerRed.withValues(
                          alpha: isHolding ? 0.7 : 0.45,
                        ),
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
    const strokeWidth = 5.0;

    // Track ring (dim)
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0 || isDisabled) return;

    // Progress arc
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: const [_dangerRed, _dangerRedGlow, _dangerRed],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );

    // Leading dot
    final dotAngle = -math.pi / 2 + 2 * math.pi * progress;
    final dotX = center.dx + radius * math.cos(dotAngle);
    final dotY = center.dy + radius * math.sin(dotAngle);

    canvas.drawCircle(
      Offset(dotX, dotY),
      strokeWidth / 2 + 1,
      Paint()..color = _dangerRedGlow,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─── Background Glow Painter ──────────────────────────────────────────────────

class _BackgroundGlowPainter extends CustomPainter {
  final double intensity; // 0.0 → 1.0

  const _BackgroundGlowPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          _dangerRed.withValues(alpha: 0.18 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_BackgroundGlowPainter old) => old.intensity != intensity;
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
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _dangerRedGlow,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Sending SOS…',
              style: TextStyle(
                color: _textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Alerting nearby rescuers',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
