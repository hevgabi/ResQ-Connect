import 'package:flutter/material.dart';

import '../screens/rescuer/mission_queue_screen.dart';
import '../screens/rescuer/rescuer_team_screen.dart';
import '../screens/rescuer/rescuer_map_screen.dart';
import '../screens/rescuer/mission_history_screen.dart';
import '../screens/rescuer/rescuer_profile_screen.dart';

class RescuerBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const RescuerBottomNav({super.key, required this.currentIndex, this.onTap});

  void _defaultOnTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final screens = [
      const MissionQueueScreen(),
      const RescuerMapScreen(),
      const RescuerTeamScreen(),
      const MissionHistoryScreen(),
      const RescuerProfileScreen(),
    ];
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
      (route) =>
          false, // clear stack so _RootRouter can regain control on logout
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) => onTap != null ? onTap!(i) : _defaultOnTap(context, i),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF1FAA59),
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
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.queue_outlined),
          activeIcon: Icon(Icons.queue),
          label: 'Queue',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.groups_outlined),
          activeIcon: Icon(Icons.groups),
          label: 'Team',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_outlined),
          activeIcon: Icon(Icons.history),
          label: 'History',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}
