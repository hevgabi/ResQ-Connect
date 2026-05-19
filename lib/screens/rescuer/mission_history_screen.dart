import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/mission_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';

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
      ),
      body: StreamBuilder<List<MissionModel>>(
        stream: firestoreService.rescuerMissionsStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allMissions = snapshot.data ?? [];
          final completed = allMissions
              .where((m) => m.status == 'arrived' || m.status == 'completed')
              .toList();
          final deferred = allMissions
              .where((m) => m.status == 'deferred')
              .toList();
          final shown = [...completed, ...deferred];

          return Column(
            children: [
              // Summary badges
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
                    const SizedBox(width: 12),
                    _summaryBadge(
                      '${deferred.length} Deferred',
                      AppTheme.warningOrange,
                      Icons.pause_circle_outline,
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
                          return _MissionHistoryCard(
                            mission: mission,
                            firestoreService: firestoreService,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: RescuerBottomNav(currentIndex: 2),
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
            'Completed and deferred missions will appear here.',
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
  final FirestoreService firestoreService;

  const _MissionHistoryCard({
    required this.mission,
    required this.firestoreService,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'arrived':
      case 'completed':
        return AppTheme.successGreen;
      case 'deferred':
        return AppTheme.warningOrange;
      default:
        return AppTheme.primaryBlue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'arrived':
      case 'completed':
        return 'COMPLETED';
      case 'deferred':
        return 'DEFERRED';
      default:
        return status.toUpperCase();
    }
  }

  String? _responseTime() {
    if (mission.acceptedAt == null || mission.arrivedAt == null) return null;
    final diff = mission.arrivedAt!.toDate().difference(
      mission.acceptedAt!.toDate(),
    );
    return '${diff.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(mission.status);
    final responseTime = _responseTime();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    mission.description != null &&
                            mission.description!.isNotEmpty
                        ? mission.description!
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

            // Stats row
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (mission.acceptedAt != null)
                  _statItem(
                    Icons.calendar_today_outlined,
                    timeago.format(mission.acceptedAt!.toDate()),
                  ),
                _statItem(
                  Icons.people_outline,
                  '${mission.personsCount} person${mission.personsCount != 1 ? 's' : ''} rescued',
                ),
                if (responseTime != null)
                  _statItem(Icons.timer_outlined, 'Response: $responseTime'),
                if (mission.evacCenterId != null)
                  _evacCenterInfo(mission.evacCenterId!),
              ],
            ),
          ],
        ),
      ),
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

  Widget _evacCenterInfo(String evacCenterId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: firestoreService.getEvacCenterById(evacCenterId),
      builder: (context, snapshot) {
        final name = snapshot.data?['name'] ?? 'Evac Center';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.home_outlined,
              size: 14,
              color: AppTheme.successGreen,
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: const TextStyle(
                color: AppTheme.successGreen,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}
