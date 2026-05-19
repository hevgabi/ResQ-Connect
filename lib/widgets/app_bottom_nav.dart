import 'package:flutter/material.dart';

import '../screens/citizen/citizen_home_screen.dart';
import '../screens/citizen/live_map_screen.dart';
import '../screens/citizen/sos_trigger_screen.dart';
import '../screens/citizen/alerts_screen.dart';
import '../screens/citizen/citizen_profile_screen.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap,
  });

  void _defaultOnTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final screens = [
      const CitizenHomeScreen(),
      const LiveMapScreen(),
      const SosTriggerScreen(),
      const AlertsScreen(),
      const CitizenProfileScreen(),
    ];
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) => onTap != null ? onTap!(i) : _defaultOnTap(context, i),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF0D47A1),
      unselectedItemColor: const Color(0xFF546E7A),
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w400,
        fontSize: 11,
      ),
      elevation: 12,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFD7263D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sos, color: Colors.white, size: 22),
          ),
          label: 'SOS',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.notifications_outlined),
          activeIcon: Icon(Icons.notifications),
          label: 'Alerts',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
