import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/sos_request_model.dart';
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
  final LocationService _locationService = LocationService();

  final String uid = FirebaseAuth.instance.currentUser!.uid;

  bool _onDuty = false;
  int _activeMissionCount = 0;
  double? _rescuerLat;
  double? _rescuerLng;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _loadRescuerState();
    _captureLocation();
  }

  Future<void> _loadRescuerState() async {
    final doc = await _firestoreService.getRescuerById(uid);
    if (!mounted || doc == null) return;
    setState(() {
      _onDuty = doc['on_duty'] ?? false;
      _activeMissionCount = doc['active_mission_count'] ?? 0;
    });
  }

  Future<void> _captureLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _rescuerLat = pos.latitude;
        _rescuerLng = pos.longitude;
      });
    } catch (_) {}
  }

  Future<void> _toggleDuty(bool value) async {
    setState(() => _onDuty = value);
    await _firestoreService.updateRescuerDuty(uid, value);
  }

  String _priorityLabel(SosRequestModel sos) {
    if (sos.createdAt == null) return 'MODERATE';
    final minutes = DateTime.now()
        .difference(sos.createdAt!.toDate())
        .inMinutes;
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

  String _timeElapsed(Timestamp? createdAt) {
    if (createdAt == null) return 'Unknown';
    final diff = DateTime.now().difference(createdAt.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  double _distanceKm(SosRequestModel sos) {
    if (_rescuerLat == null || _rescuerLng == null) return 0;
    return _locationService.calculateDistance(
      _rescuerLat!,
      _rescuerLng!,
      sos.latitude,
      sos.longitude,
    );
  }

  Future<void> _acceptMission(SosRequestModel sos) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      final missionRef = await _firestoreService.createMission({
        'sos_id': sos.id,
        'rescuer_id': uid,
        'status': 'accepted',
        'accepted_at': FieldValue.serverTimestamp(),
        'persons_count': 1,
      });

      await Future.wait([
        _firestoreService.updateSosRequest(sos.id, {
          'status': 'assigned',
          'assigned_rescuer_id': uid,
        }),
        _firestoreService.updateRescuer(uid, {
          'active_mission_count': FieldValue.increment(1),
        }),
      ]);

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
            content: Text('Failed to accept: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _deferMission(SosRequestModel sos) async {
    try {
      await _firestoreService.createMission({
        'sos_id': sos.id,
        'rescuer_id': uid,
        'status': 'deferred',
        'deferred_at': FieldValue.serverTimestamp(),
        'persons_count': 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Mission deferred.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Defer failed: $e')));
      }
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
      ),
      body: Column(
        children: [
          // Duty toggle + active count
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

          // Mission list
          Expanded(
            child: StreamBuilder<List<SosRequestModel>>(
              stream: _firestoreService.openSOSStream(),
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
                    return _MissionCard(
                      sos: sos,
                      priority: _priorityLabel(sos),
                      priorityColor: _priorityColor(_priorityLabel(sos)),
                      timeElapsed: _timeElapsed(sos.createdAt),
                      distanceKm: _distanceKm(sos),
                      firestoreService: _firestoreService,
                      onAccept: () => _acceptMission(sos),
                      onDefer: () => _deferMission(sos),
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
}

class _MissionCard extends StatelessWidget {
  final SosRequestModel sos;
  final String priority;
  final Color priorityColor;
  final String timeElapsed;
  final double distanceKm;
  final FirestoreService firestoreService;
  final VoidCallback onAccept;
  final VoidCallback onDefer;
  final bool accepting;

  const _MissionCard({
    required this.sos,
    required this.priority,
    required this.priorityColor,
    required this.timeElapsed,
    required this.distanceKm,
    required this.firestoreService,
    required this.onAccept,
    required this.onDefer,
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
              // Header strip
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
                    bottom: BorderSide(color: priorityColor.withValues(alpha: 0.3)),
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
                    // Citizen name + blood type
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
                                color: AppTheme.dangerRed.withValues(alpha: 0.3),
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

                    // Distance
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

                    // Description
                    Text(
                      sos.description ?? 'No description provided.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 14),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
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
                                : const Text('Accept'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onDefer,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Defer'),
                          ),
                        ),
                      ],
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
