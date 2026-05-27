import 'package:flutter/material.dart';

import '../screens/moderator/moderator_report_queue_screen.dart';
import '../screens/moderator/moderator_published_feed_screen.dart';
import '../screens/moderator/moderator_statistics_screen.dart';
import '../screens/moderator/moderator_rescuer_list_screen.dart';
import '../screens/moderator/moderator_spotted_emergencies_screen.dart';
import '../screens/moderator/moderator_profile_screen.dart';
import '../services/firestore_service.dart';

class ModeratorBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const ModeratorBottomNav({super.key, required this.currentIndex, this.onTap});

  @override
  State<ModeratorBottomNav> createState() => _ModeratorBottomNavState();
}

class _ModeratorBottomNavState extends State<ModeratorBottomNav> {
  int _pendingReports = 0;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance.pendingReportsStream().listen((reports) {
      if (mounted) setState(() => _pendingReports = reports.length);
    });
  }

  void _defaultOnTap(BuildContext context, int index) {
    if (index == widget.currentIndex) return;
    final screens = [
      const ModeratorReportQueueScreen(),
      const ModeratorPublishedFeedScreen(),
      const ModeratorStatisticsScreen(),
      const ModeratorRescuerListScreen(),
      const ModeratorSpottedEmergenciesScreen(),
      const ModeratorProfileScreen(),
    ];
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
      (route) => false,
    );
  }

  Widget _queueIcon({bool active = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(active ? Icons.pending_actions : Icons.pending_actions_outlined),
        if (_pendingReports > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFFD7263D),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              child: Text(
                _pendingReports > 9 ? '9+' : '$_pendingReports',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      onTap: (i) =>
          widget.onTap != null ? widget.onTap!(i) : _defaultOnTap(context, i),
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
        BottomNavigationBarItem(
          icon: _queueIcon(active: false),
          activeIcon: _queueIcon(active: true),
          label: 'Queue',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.public_outlined),
          activeIcon: Icon(Icons.public),
          label: 'Published',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_outlined),
          activeIcon: Icon(Icons.bar_chart),
          label: 'Statistics',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people),
          label: 'Rescuers',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.warning_amber_outlined),
          activeIcon: Icon(Icons.warning_amber_rounded),
          label: 'Spotted',
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
