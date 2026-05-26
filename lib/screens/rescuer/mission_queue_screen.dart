import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../screens/settings/hamburger_menu_screen.dart';

import '../../models/sos_request_model.dart'; // Tiyaking itong model file ang naglalaman ng SOSRequestModel class mo
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import 'active_navigation_screen.dart';

class MissionQueueScreen extends StatefulWidget {
  const MissionQueueScreen({super.key});

  @override
  State<MissionQueueScreen> createState() => _MissionQueueScreenState();
}

class _MissionQueueScreenState extends State<MissionQueueScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  bool _onDuty = false;
  int _activeMissionCount = 0;
  double? _rescuerLat;
  double? _rescuerLng;
  bool _accepting = false;

  // Guard flag: while toggling duty, ignore Firestore stream updates
  // so the switch doesn't flip back immediately after being tapped.
  bool _togglingDuty = false;

  @override
  void initState() {
    super.initState();
    _subscribeToRescuerState();
    _captureLocation();
  }

  // FIXED: Binago mula 'users' patungong 'rescuers' para mag-match sa iyong Firestore architecture
  void _subscribeToRescuerState() {
    FirebaseFirestore.instance.collection('rescuers').doc(uid).snapshots().listen((
      doc,
    ) {
      if (!mounted || !doc.exists) return;
      setState(() {
        _activeMissionCount = doc.data()?['active_mission_count'] ?? 0;
        // Only sync duty status when we are NOT in the middle of a local toggle.
        // Without this guard, the Firestore write confirmation triggers the
        // listener which immediately overwrites the local switch value, making
        // the toggle appear to snap back.
        if (!_togglingDuty) {
          _onDuty = doc.data()?['is_on_duty'] ?? false;
        }
      });
    });
  }

  // FIXED: Dinagdagan ng null check sa 'pos' parameter bago kuhanin ang lat/lng para iwas crash
  Future<void> _captureLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted || pos == null) return;
      setState(() {
        _rescuerLat = pos.latitude;
        _rescuerLng = pos.longitude;
      });
    } catch (_) {}
  }

  Future<void> _toggleDuty(bool value) async {
    if (_togglingDuty) return;
    setState(() {
      _togglingDuty = true;
      _onDuty = value;
    });
    try {
      await _firestoreService.updateRescuerDuty(uid, value);
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() => _onDuty = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update duty status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingDuty = false);
    }
  }

  // FIXED: Pinalitan ang SosRequestModel patungong SOSRequestModel
  String _priorityLabel(SOSRequestModel sos) {
    if (sos.createdAt == null) return 'MODERATE';
    final minutes = DateTime.now().difference(sos.createdAt!).inMinutes;
    if (minutes > 30) return 'CRITICAL';
    if (minutes > 15) return 'HIGH';
    return 'MODERATE';
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'CRITICAL':
        return AppTheme.dangerRed;
      case 'HIGH':
        return AppTheme.warningOrange;
      default:
        return AppTheme.successGreen;
    }
  }

  String _timeElapsed(DateTime? createdAt) {
    if (createdAt == null) return 'Unknown';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  // FIXED: Pinalitan ang SosRequestModel patungong SOSRequestModel
  double _distanceKm(SOSRequestModel sos) {
    if (_rescuerLat == null || _rescuerLng == null) return 0;
    return _locationService.calculateDistance(
      _rescuerLat!,
      _rescuerLng!,
      sos.latitude,
      sos.longitude,
    );
  }

  // FIXED: Pinalitan ang references mula 'users' patungong 'rescuers' para sa transactional state changes
  Future<void> _acceptMission(SOSRequestModel sos) async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final firestore = FirebaseFirestore.instance;
    final sosRef = firestore.collection('sos_requests').doc(sos.id);
    final rescuerRef = firestore
        .collection('rescuers')
        .doc(uid); // <--- Inayos dito mula 'users'
    final missionRef = firestore.collection('missions').doc();

    try {
      await firestore.runTransaction((transaction) async {
        final sosDoc = await transaction.get(sosRef);

        if (!sosDoc.exists) {
          throw Exception('SOS Request no longer exists.');
        }

        final currentStatus = sosDoc.data()?['status'] ?? 'open';
        if (currentStatus != 'open') {
          throw Exception(
            'This emergency has already been taken by another responder.',
          );
        }

        // Isabay ang pagsulat sa lahat ng apektadong document parameters
        transaction.set(missionRef, {
          'id': missionRef.id,
          'sos_id': sos.id,
          'rescuer_id': uid,
          'status': 'en_route',
          'created_at': FieldValue.serverTimestamp(),
          'completed_at': null,
          'notes': '',
        });

        transaction.update(sosRef, {
          'status': 'assigned',
          'assigned_rescuer_id': uid,
        });

        transaction.update(rescuerRef, {
          'active_mission_count': FieldValue.increment(1),
        });
      });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveNavigationScreen(missionId: missionRef.id),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Mission Queue',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.rescuer),
          ),
        ],
      ),
      body: Column(
        children: [
          // Duty banner controller UI
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _onDuty ? 'On Duty' : 'Off Duty',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _onDuty
                            ? AppTheme.successGreen
                            : AppTheme.textSecondary,
                      ),
                    ),
                    subtitle: Text(
                      _onDuty ? 'Accepting missions' : 'Not accepting missions',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _onDuty,
                    activeThumbColor: AppTheme.successGreen,
                    onChanged: _toggleDuty,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_activeMissionCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const Text(
                        'Active',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // StreamBuilder Engine para sa Open SOS Feed
          Expanded(
            child: !_onDuty
                ? _buildOffDutyState()
                : StreamBuilder<List<SOSRequestModel>>(
                    // <--- FIXED: SOSRequestModel name alignment
                    stream: _firestoreService.openSOSStream(
                      excludeRescuerId: uid,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final sosList = snapshot.data ?? [];

                      if (sosList.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: sosList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final sos = sosList[index];
                          final priorityStr = _priorityLabel(sos);

                          return _MissionCard(
                            sos: sos,
                            priority: priorityStr,
                            priorityColor: _priorityColor(priorityStr),
                            timeElapsed: _timeElapsed(sos.createdAt),
                            distanceKm: _distanceKm(sos),
                            firestoreService: _firestoreService,
                            onAccept: () => _acceptMission(sos),
                            accepting: _accepting,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: RescuerBottomNav(currentIndex: 0),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppTheme.successGreen,
          ),
          const SizedBox(height: 12),
          const Text(
            'No open missions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'All SOS requests have been handled.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildOffDutyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'You are Off Duty',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Toggle "On Duty" above to start receiving emergency cues.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final SOSRequestModel sos; // <--- FIXED: SOSRequestModel name alignment
  final String priority;
  final Color priorityColor;
  final String timeElapsed;
  final double distanceKm;
  final FirestoreService firestoreService;
  final VoidCallback onAccept;
  final bool accepting;

  const _MissionCard({
    required this.sos,
    required this.priority,
    required this.priorityColor,
    required this.timeElapsed,
    required this.distanceKm,
    required this.firestoreService,
    required this.onAccept,
    required this.accepting,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: firestoreService.getUserById(sos.citizenId),
      builder: (context, snapshot) {
        final citizen = snapshot.data;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: priorityColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        priority,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeElapsed,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          citizen != null
                              ? '${citizen.firstName ?? ''} ${citizen.lastName ?? ''}'
                                    .trim()
                              : 'Loading...',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        if (citizen?.bloodType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.dangerRed.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.bloodtype,
                                  size: 12,
                                  color: AppTheme.dangerRed,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  citizen!.bloodType!,
                                  style: const TextStyle(
                                    color: AppTheme.dangerRed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${distanceKm.toStringAsFixed(1)} km away',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sos.description ?? 'No description provided.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: accepting ? null : onAccept,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: accepting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept Mission'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
