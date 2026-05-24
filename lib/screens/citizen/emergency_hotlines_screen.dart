import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyHotlinesScreen extends StatelessWidget {
  const EmergencyHotlinesScreen({super.key});

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

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group by category
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _blue),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
                    'Tap the call button to dial directly. Only call during real emergencies.',
                    style: TextStyle(fontSize: 12, color: _red),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Grouped hotlines
          ...grouped.entries.map((entry) => Column(
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
          )),
        ],
      ),
    );
  }

  Widget _buildHotlineCard(Map<String, dynamic> h) {
    final color = h['color'] as Color;
    final icon = h['icon'] as IconData;

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
          GestureDetector(
            onTap: () => _call(h['number'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                h['number'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}