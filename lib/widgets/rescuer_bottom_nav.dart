import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/rescuer/mission_queue_screen.dart';
import '../screens/rescuer/rescuer_team_screen.dart';
import '../screens/rescuer/rescuer_map_screen.dart';
import '../screens/rescuer/mission_history_screen.dart';
import '../screens/rescuer/rescuer_profile_screen.dart';
import '../services/firestore_service.dart';

class RescuerBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const RescuerBottomNav({super.key, required this.currentIndex, this.onTap});

  @override
  State<RescuerBottomNav> createState() => _RescuerBottomNavState();
}

class _RescuerBottomNavState extends State<RescuerBottomNav> {
  int _pendingInvites = 0;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.rescuerPendingInvitesStream(uid).listen((
        invites,
      ) {
        if (mounted) setState(() => _pendingInvites = invites.length);
      });
    }
  }

  void _defaultOnTap(BuildContext context, int index) {
    if (index == widget.currentIndex) return;
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
      (route) => false,
    );
  }

  Widget _teamIcon({bool active = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(active ? Icons.groups : Icons.groups_outlined),
        if (_pendingInvites > 0)
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
                _pendingInvites > 9 ? '9+' : '$_pendingInvites',
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
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.queue_outlined),
          activeIcon: Icon(Icons.queue),
          label: 'Queue',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: _teamIcon(active: false),
          activeIcon: _teamIcon(active: true),
          label: 'Team',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.history_outlined),
          activeIcon: Icon(Icons.history),
          label: 'History',
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
