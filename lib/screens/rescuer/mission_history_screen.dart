import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/mission_model.dart';
import '../../models/sos_request_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import '../../screens/settings/hamburger_menu_screen.dart';

class MissionHistoryScreen extends StatelessWidget {
  const MissionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestoreService = FirestoreService.instance;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Mission History',
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
      body: StreamBuilder<List<MissionModel>>(
        stream: firestoreService.rescuerMissionsStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Failed to load missions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final allMissions = snapshot.data ?? [];

          final completed = allMissions
              .where((m) => m.status == 'completed')
              .toList();
          final shown =
              allMissions
                  .where(
                    (m) => m.status == 'completed' || m.status == 'cancelled',
                  )
                  .toList()
                ..sort(
                  (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                    a.createdAt ?? DateTime(0),
                  ),
                );

          return Column(
            children: [
              // Summary badge
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    _summaryBadge(
                      '${completed.length} Completed',
                      AppTheme.successGreen,
                      Icons.check_circle_outline,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Mission list
              Expanded(
                child: shown.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final mission = shown[index];
                          return _MissionHistoryCard(mission: mission);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const RescuerBottomNav(currentIndex: 3),
    );
  }

  Widget _summaryBadge(String label, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No missions yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Your finished missions will appear right here.',
            style: TextStyle(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MissionHistoryCard extends StatelessWidget {
  final MissionModel mission;

  const _MissionHistoryCard({required this.mission});

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppTheme.successGreen;
      case 'cancelled':
        return AppTheme.dangerRed;
      default:
        return AppTheme.primaryBlue;
    }
  }

  String _statusLabel(String status) {
    if (status == 'completed') return 'COMPLETED';
    if (status == 'cancelled') return 'CANCELLED';
    return status.toUpperCase();
  }

  String? _responseTime() {
    if (mission.createdAt == null || mission.completedAt == null) return null;
    final diff = mission.completedAt!.difference(mission.createdAt!);
    return '${diff.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(mission.status);
    final responseTime = _responseTime();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(mission.sosId)
          .get(),
      builder: (context, snapshot) {
        SOSRequestModel? sosDetails;
        if (snapshot.hasData && snapshot.data!.exists) {
          sosDetails = SOSRequestModel.fromFirestore(snapshot.data!);
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Citizen Name/ID + Status Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        sosDetails != null
                            ? 'Rescue: ${sosDetails.citizenName}'
                            : 'Mission #${mission.id.substring(0, 6)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusLabel(mission.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Description
                if (sosDetails != null && sosDetails.description != null) ...[
                  Text(
                    sosDetails.description!,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                ],

                // Stats row
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (mission.createdAt != null)
                      _statItem(
                        Icons.calendar_today_outlined,
                        timeago.format(mission.createdAt!),
                      ),
                    if (responseTime != null)
                      _statItem(
                        Icons.timer_outlined,
                        'Duration: $responseTime',
                      ),
                    if (mission.notes != null && mission.notes!.isNotEmpty)
                      _statItem(Icons.sticky_note_2_outlined, mission.notes!),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
