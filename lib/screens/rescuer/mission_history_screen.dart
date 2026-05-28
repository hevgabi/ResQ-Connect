import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
          final shown = allMissions
              .where(
                (m) => m.status == 'completed' || m.status == 'cancelled',
          )
              .toList()
            ..sort(
                  (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                a.createdAt ?? DateTime(0),
              ),
            );

          final completed = shown.where((m) => m.status == 'completed').length;
          final cancelled = shown.where((m) => m.status == 'cancelled').length;

          // Avg duration of completed missions
          final durations = shown
              .where(
                (m) =>
            m.status == 'completed' &&
                m.createdAt != null &&
                m.completedAt != null,
          )
              .map((m) => m.completedAt!.difference(m.createdAt!).inMinutes)
              .toList();
          final avgDuration = durations.isEmpty
              ? null
              : (durations.reduce((a, b) => a + b) / durations.length).round();

          return Column(
            children: [
              // ── Summary bar ─────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    _summaryTile(
                      icon: Icons.check_circle_outline,
                      value: '$completed',
                      label: 'Completed',
                      color: AppTheme.successGreen,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      icon: Icons.cancel_outlined,
                      value: '$cancelled',
                      label: 'Cancelled',
                      color: AppTheme.dangerRed,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      icon: Icons.timer_outlined,
                      value: avgDuration != null ? '${avgDuration}m' : '—',
                      label: 'Avg Duration',
                      color: AppTheme.primaryBlue,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── Mission list ─────────────────────────────────────────────
              Expanded(
                child: shown.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _MissionHistoryCard(mission: shown[index]);
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

  Widget _summaryTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 10,
                fontWeight: FontWeight.w600,
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

// =============================================================================
// MISSION HISTORY CARD
// =============================================================================

// Helper data class for the FutureBuilder
class _MissionCardData {
  final SOSRequestModel? sos;
  final String citizenName;
  const _MissionCardData({required this.sos, required this.citizenName});
}

class _MissionHistoryCard extends StatelessWidget {
  final MissionModel mission;
  const _MissionHistoryCard({required this.mission});

  Color _statusColor(String status) => switch (status) {
    'completed' => AppTheme.successGreen,
    'cancelled' => AppTheme.dangerRed,
    _ => AppTheme.primaryBlue,
  };

  String _statusLabel(String status) => switch (status) {
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => status.toUpperCase(),
  };

  IconData _statusIcon(String status) => switch (status) {
    'completed' => Icons.check_circle_rounded,
    'cancelled' => Icons.cancel_rounded,
    _ => Icons.info_rounded,
  };

  String _formatDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'N/A';
    final diff = end.difference(start);
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes > 0) return '${diff.inMinutes} min';
    return 'Less than a minute';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    return DateFormat('MMM d, yyyy · h:mm a').format(dt);
  }

  Future<_MissionCardData> _fetchCardData(String? sosId) async {
    SOSRequestModel? sos;
    String citizenName = 'Unknown Citizen';
    if (sosId == null || sosId.isEmpty) {
      return _MissionCardData(sos: sos, citizenName: citizenName);
    }
    try {
      final sosDoc = await FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(sosId)
          .get();
      if (sosDoc.exists) {
        sos = SOSRequestModel.fromFirestore(sosDoc);
        final storedName = sos.citizenName.trim();
        if (storedName.isNotEmpty) {
          citizenName = storedName;
        } else if (sos.citizenId.isNotEmpty) {
          // citizenName field is blank — look up from users collection
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(sos.citizenId)
              .get();
          if (userDoc.exists) {
            final uData = userDoc.data() as Map<String, dynamic>;
            final firstName = uData['first_name'] as String? ?? '';
            final lastName = uData['last_name'] as String? ?? '';
            final full = '$firstName $lastName'.trim();
            if (full.isNotEmpty) citizenName = full;
          }
        }
      }
    } catch (_) {}
    return _MissionCardData(sos: sos, citizenName: citizenName);
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(mission.status);

    return FutureBuilder<_MissionCardData>(
      future: _fetchCardData(mission.sosId),
      builder: (context, snapshot) {
        SOSRequestModel? sos = snapshot.data?.sos;
        final citizenName = snapshot.data?.citizenName ?? 'Loading...';

        final description = sos?.description?.trim().isNotEmpty == true
            ? sos!.description!
            : null;

        final address =
        sos?.address?.trim().isNotEmpty == true ? sos!.address! : null;

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
                // ── Header: Status icon + Citizen name + Badge ────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _statusIcon(mission.status),
                        color: color,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            citizenName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatDate(mission.createdAt),
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withAlpha(80)),
                      ),
                      child: Text(
                        _statusLabel(mission.status),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Description ───────────────────────────────────────────
                if (description != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // ── Category chip ──────────────────────────────────────────
                if (sos?.category != null) ...[
                  const SizedBox(height: 8),
                  _HistoryCategoryChip(category: sos!.category!),
                ],

                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // ── Info row: Location + Duration ─────────────────────────
                Row(
                  children: [
                    // Location
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address ??
                                  '${mission.citizenLatitude.toStringAsFixed(4)}, '
                                      '${mission.citizenLongitude.toStringAsFixed(4)}',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Duration
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(
                            mission.createdAt,
                            mission.completedAt,
                          ),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Notes if any ──────────────────────────────────────────
                if (mission.notes != null &&
                    mission.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mission.notes!,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryCategoryChip extends StatelessWidget {
  final String category;
  const _HistoryCategoryChip({required this.category});

  static const _labels = <String, String>{
    'natural_disaster': 'Natural Disaster',
    'accident': 'Accident',
    'medical': 'Medical',
    'fire': 'Fire',
    'crime': 'Crime',
    'rescue': 'Rescue / Trapped',
  };

  static const _icons = <String, IconData>{
    'natural_disaster': Icons.storm_rounded,
    'accident': Icons.car_crash_rounded,
    'medical': Icons.medical_services_rounded,
    'fire': Icons.local_fire_department_rounded,
    'crime': Icons.security_rounded,
    'rescue': Icons.warning_amber_rounded,
  };

  static const _colors = <String, Color>{
    'natural_disaster': Color(0xFF1565C0),
    'accident': Color(0xFFFF6D00),
    'medical': Color(0xFFE53935),
    'fire': Color(0xFFFF8F00),
    'crime': Color(0xFF6A1B9A),
    'rescue': Color(0xFFF9A825),
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[category] ?? category;
    final icon = _icons[category] ?? Icons.help_outline_rounded;
    final color = _colors[category] ?? AppTheme.primaryBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
