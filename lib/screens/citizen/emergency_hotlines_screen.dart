import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_bottom_nav.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyHotlinesScreen extends StatefulWidget {
  const EmergencyHotlinesScreen({super.key});

  @override
  State<EmergencyHotlinesScreen> createState() =>
      _EmergencyHotlinesScreenState();
}

class _EmergencyHotlinesScreenState extends State<EmergencyHotlinesScreen>
    with TickerProviderStateMixin {
  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _green = Color(0xFF1FAA59);
  static const _orange = Color(0xFFFF6B00);
  static const _bg = Color(0xFFF5F7FA);

  static const _hotlines = [
    {
      'category': 'National Emergency',
      'name': 'Emergency Hotline',
      'number': '911',
      'description': 'For all emergencies nationwide',
      'icon': Icons.emergency_rounded,
      'color': _red,
    },
    {
      'category': 'Disaster Response',
      'name': 'NDRRMC',
      'number': '8911-1406',
      'description': 'National Disaster Risk Reduction and Management Council',
      'icon': Icons.flood_rounded,
      'color': _orange,
    },
    {
      'category': 'Medical',
      'name': 'Philippine Red Cross',
      'number': '143',
      'description': 'Ambulance & medical emergency response',
      'icon': Icons.local_hospital_rounded,
      'color': _red,
    },
    {
      'category': 'Police',
      'name': 'PNP Hotline',
      'number': '117',
      'description': 'Philippine National Police',
      'icon': Icons.local_police_rounded,
      'color': _blue,
    },
    {
      'category': 'Fire',
      'name': 'Bureau of Fire Protection',
      'number': '160',
      'description': 'Fire emergency response',
      'icon': Icons.local_fire_department_rounded,
      'color': _orange,
    },
    {
      'category': 'Medical',
      'name': 'DOH Emergency',
      'number': '1555',
      'description': 'Department of Health hotline',
      'icon': Icons.health_and_safety_rounded,
      'color': _green,
    },
  ];

  String? _holdingNumber;
  AnimationController? _holdController;

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _startHold(String number) {
    _holdController?.dispose();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    setState(() => _holdingNumber = number);
    HapticFeedback.lightImpact();

    _holdController!.forward();
    _holdController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _cancelHold();
        _call(number);
      }
    });
  }

  void _cancelHold() {
    _holdController?.stop();
    _holdController?.dispose();
    _holdController = null;
    if (mounted) setState(() => _holdingNumber = null);
  }

  @override
  void dispose() {
    _holdController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final h in _hotlines) {
      final cat = h['category'] as String;
      grouped.putIfAbsent(cat, () => []).add(h);
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Emergency Hotlines',
          style: TextStyle(
            color: _blue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _red, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hold the call button to dial. Only call during real emergencies.',
                    style: TextStyle(fontSize: 12, color: _red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          ...grouped.entries.map(
                (entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF546E7A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...entry.value.map((h) => _buildHotlineCard(h)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotlineCard(Map<String, dynamic> h) {
    final color = h['color'] as Color;
    final icon = h['icon'] as IconData;
    final number = h['number'] as String;
    final isHolding = _holdingNumber == number;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left icon
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h['name'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1A237E),
                  ),
                ),
                Text(
                  h['description'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF546E7A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Hold-to-call button
          GestureDetector(
            onLongPressStart: (_) => _startHold(number),
            onLongPressEnd: (_) => _cancelHold(),
            onLongPressCancel: () => _cancelHold(),
            child: _HoldCallButton(
              number: number,
              color: color,
              isHolding: isHolding,
              controller: isHolding ? _holdController : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Extracted hold-button widget ────────────────────────────────────────────

class _HoldCallButton extends StatelessWidget {
  final String number;
  final Color color;
  final bool isHolding;
  final AnimationController? controller;

  const _HoldCallButton({
    required this.number,
    required this.color,
    required this.isHolding,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pill button with number
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isHolding ? color.withValues(alpha: 0.85) : color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),

          const SizedBox(height: 5),

          // Progress track — always visible as a gray track,
          // fills with color while holding
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              width: 72,
              child: isHolding && controller != null
                  ? AnimatedBuilder(
                animation: controller!,
                builder: (_, __) => LinearProgressIndicator(
                  value: controller!.value,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 4,
                ),
              )
                  : Container(
                color: Colors.grey.shade300,
              ),
            ),
          ),

          const SizedBox(height: 3),

          // "Hold to call" hint label
          Text(
            isHolding ? 'Calling...' : 'Hold to call',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: isHolding ? color : Colors.grey.shade500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}