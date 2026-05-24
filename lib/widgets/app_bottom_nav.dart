import 'package:flutter/material.dart';
import '../screens/citizen/citizen_home_screen.dart';
import '../screens/citizen/live_map_screen.dart';
import '../screens/citizen/sos_trigger_screen.dart';
import '../screens/citizen/emergency_hotlines_screen.dart';
import '../screens/citizen/citizen_profile_screen.dart';
import '../screens/citizen/alerts_screen.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;
  const AppBottomNav({super.key, required this.currentIndex, this.onTap});

  void _defaultOnTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    if (index == 4) {
      _openMore(context);
      return;
    }
    final screens = [
      const CitizenHomeScreen(),
      const LiveMapScreen(),
      const SosTriggerScreen(),
      const EmergencyHotlinesScreen(),
    ];
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
          (route) => false,
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MoreMenu(),
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
          icon: Icon(Icons.phone_outlined),
          activeIcon: Icon(Icons.phone),
          label: 'Hotlines',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.menu),
          label: 'More',
        ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'More',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: Color(0xFF0D47A1)),
              title: const Text('Alerts',
                  style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline,
                  color: Color(0xFF0D47A1)),
              title: const Text('Profile',
                  style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CitizenProfileScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}