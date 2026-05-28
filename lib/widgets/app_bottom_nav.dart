import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/citizen/citizen_home_screen.dart';
import '../screens/citizen/live_map_screen.dart';
import '../screens/citizen/sos_trigger_screen.dart';
import '../screens/citizen/rescuer_assigned_screen.dart';
import '../screens/citizen/emergency_hotlines_screen.dart';
import '../screens/citizen/citizen_profile_screen.dart';

// =============================================================================
// SOS STATUS BANNER
// A persistent banner shown above the bottom nav whenever the user has an
// active SOS request (status: 'open' or 'assigned'). Tapping it navigates
// back to RescuerAssignedScreen so the user never loses their SOS status.
// =============================================================================

class _SosBanner extends StatelessWidget {
  final String sosId;
  final String status;
  final String? assignedRescuerName;
  final VoidCallback onTap;
  final bool onActiveScreen;

  const _SosBanner({
    required this.sosId,
    required this.status,
    required this.onTap,
    this.assignedRescuerName,
    this.onActiveScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAssigned = status == 'assigned';
    final Color bgColor = isAssigned
        ? const Color(0xFF1FAA59)
        : const Color(0xFFD7263D);
    final IconData icon = isAssigned ? Icons.directions_run : Icons.sos;
    final String label = isAssigned
        ? (assignedRescuerName != null
              ? 'Rescuer on the way — $assignedRescuerName'
              : 'Rescuer assigned — tap for details')
        : 'SOS Active — waiting for rescuer';

    return GestureDetector(
      onTap: onActiveScreen ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: bgColor.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsing icon
            _PulsingIcon(icon: icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!onActiveScreen) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.chevron_right, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  const _PulsingIcon({required this.icon});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.9,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(widget.icon, color: Colors.white, size: 20),
    );
  }
}

// =============================================================================
// APP BOTTOM NAV
// =============================================================================

class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  /// Set to true only on RescuerAssignedScreen to hide the View button
  /// and disable the banner tap (user is already on that screen).
  final bool hideViewButton;
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap,
    this.hideViewButton = false,
  });

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  bool _navigating = false;

  // Active SOS data streamed from Firestore
  Stream<QuerySnapshot>? _sosStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _sosStream = FirebaseFirestore.instance
          .collection('sos_requests')
          .where('citizen_id', isEqualTo: uid)
          .where('status', whereIn: ['open', 'assigned'])
          .limit(1)
          .snapshots();
    }
  }

  Future<void> _handleTap(int index) async {
    if (_navigating) return;
    if (index == widget.currentIndex) return;

    if (widget.onTap != null) {
      widget.onTap!(index);
      return;
    }

    // SOS tab — check for an active SOS first
    if (index == 2) {
      setState(() => _navigating = true);
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final snap = await FirebaseFirestore.instance
              .collection('sos_requests')
              .where('citizen_id', isEqualTo: uid)
              .where('status', whereIn: ['open', 'assigned'])
              .limit(1)
              .get();

          if (!mounted) return;

          if (snap.docs.isNotEmpty) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RescuerAssignedScreen(sosId: snap.docs.first.id),
              ),
              (route) => false,
            );
            return;
          }
        }

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SosTriggerScreen()),
          (route) => false,
        );
      } catch (_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const SosTriggerScreen()),
            (route) => false,
          );
        }
      } finally {
        if (mounted) setState(() => _navigating = false);
      }
      return;
    }

    final screens = <Widget>[
      const CitizenHomeScreen(),
      const LiveMapScreen(),
      const SosTriggerScreen(),
      const EmergencyHotlinesScreen(),
      const CitizenProfileScreen(),
    ];

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
      (route) => false,
    );
  }

  void _goToSosStatus(String sosId) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => RescuerAssignedScreen(sosId: sosId)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navBar = BottomNavigationBar(
      currentIndex: widget.currentIndex,
      onTap: _handleTap,
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
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(icon: _SosIcon(), label: 'SOS'),
        BottomNavigationBarItem(
          icon: Icon(Icons.phone_outlined),
          activeIcon: Icon(Icons.phone),
          label: 'Hotlines',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );

    // If no active SOS stream, just return the nav bar
    if (_sosStream == null) return navBar;

    // Wrap nav bar with a StreamBuilder that shows the SOS banner above it
    return StreamBuilder<QuerySnapshot>(
      stream: _sosStream,
      builder: (context, snapshot) {
        // While waiting or on error, don't hide a potentially active banner —
        // only hide it when we have a confirmed empty result.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return navBar;
        }
        if (snapshot.hasError || !snapshot.hasData) return navBar;

        final hasSos = snapshot.data!.docs.isNotEmpty;
        if (!hasSos) return navBar;

        final doc = snapshot.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'open';
        final assignedName = data['assigned_rescuer_name'] as String?;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SosBanner(
              sosId: doc.id,
              status: status,
              assignedRescuerName: assignedName,
              onTap: () => _goToSosStatus(doc.id),
              onActiveScreen: widget.hideViewButton,
            ),
            navBar,
          ],
        );
      },
    );
  }
}

// Separate const widget so the BottomNavigationBar can render it without
// the Container intercepting pointer events.
class _SosIcon extends StatelessWidget {
  const _SosIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFFD7263D),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.sos, color: Colors.white, size: 22),
    );
  }
}
