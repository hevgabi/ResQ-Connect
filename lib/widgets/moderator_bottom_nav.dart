import 'package:flutter/material.dart';

import '../screens/moderator/moderator_report_queue_screen.dart';
import '../screens/moderator/moderator_published_feed_screen.dart';
import '../screens/moderator/moderator_statistics_screen.dart';
import '../screens/moderator/moderator_rescuer_list_screen.dart';
import '../screens/moderator/moderator_profile_screen.dart';

class ModeratorBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const ModeratorBottomNav({super.key, required this.currentIndex, this.onTap});

  void _defaultOnTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final screens = [
      const ModeratorReportQueueScreen(),
      const ModeratorPublishedFeedScreen(),
      const ModeratorStatisticsScreen(),
      const ModeratorRescuerListScreen(),
      const ModeratorProfileScreen(),
    ];
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
      (route) => false,
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
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.pending_actions_outlined),
          activeIcon: Icon(Icons.pending_actions),
          label: 'Queue',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.public_outlined),
          activeIcon: Icon(Icons.public),
          label: 'Published',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_outlined),
          activeIcon: Icon(Icons.bar_chart),
          label: 'Statistics',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people),
          label: 'Rescuers',
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
