import 'package:flutter/material.dart';

import '../screens/moderator/moderator_report_queue_screen.dart';
import '../screens/moderator/moderator_published_feed_screen.dart';

class ModeratorBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const ModeratorBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap,
  });

  void _defaultOnTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final screens = [
      const ModeratorReportQueueScreen(),
      const ModeratorPublishedFeedScreen(),
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
      selectedItemColor: const Color(0xFF6A1B9A),
      unselectedItemColor: const Color(0xFF546E7A),
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w400,
        fontSize: 12,
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
      ],
    );
  }
}
