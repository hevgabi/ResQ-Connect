import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../theme/app_theme.dart';
import '../../widgets/broadcast_alert_overlay.dart';
import '../../widgets/moderator_bottom_nav.dart';
import '../settings/hamburger_menu_screen.dart';

/// Moderator screen — Spotted Emergencies & Reassignment
/// Shows all spotted emergencies reported by rescuers mid-mission.
/// Coordinator can review, assign a free rescuer, or dismiss.
class ModeratorSpottedEmergenciesScreen extends StatefulWidget {
  const ModeratorSpottedEmergenciesScreen({super.key});

  @override
  State<ModeratorSpottedEmergenciesScreen> createState() =>
      _ModeratorSpottedEmergenciesScreenState();
}

class _ModeratorSpottedEmergenciesScreenState
    extends State<ModeratorSpottedEmergenciesScreen> {
  String _filterStatus = 'pending'; // pending | assigned | dismissed | all

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Spotted Emergencies',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.moderator),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Filter chips
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: '🕐 Pending',
                        selected: _filterStatus == 'pending',
                        color: AppTheme.warningOrange,
                        onTap: () => setState(() => _filterStatus = 'pending'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '✅ Assigned',
                        selected: _filterStatus == 'assigned',
                        color: AppTheme.successGreen,
                        onTap: () => setState(() => _filterStatus = 'assigned'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '🚫 Dismissed',
                        selected: _filterStatus == 'dismissed',
                        color: AppTheme.textSecondary,
                        onTap: () =>
                            setState(() => _filterStatus = 'dismissed'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'All',
                        selected: _filterStatus == 'all',
                        color: AppTheme.primaryBlue,
                        onTap: () => setState(() => _filterStatus = 'all'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildList()),
            ],
          ),

          // ── Broadcast alert overlay ─────────────────────────────────────
          const BroadcastAlertOverlay(topOffset: 12),
        ],
      ),
      bottomNavigationBar: const ModeratorBottomNav(currentIndex: 4),
    );
  }

  Widget _buildList() {
    Query query = FirebaseFirestore.instance
        .collection('spotted_emergencies')
        .orderBy('created_at', descending: true);

    if (_filterStatus != 'all') {
      query = query.where('status', isEqualTo: _filterStatus);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  _filterStatus == 'pending'
                      ? 'No pending reports'
                      : 'No reports found',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Spotted emergencies from rescuers\nwill appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _SpottedEmergencyCard(docId: doc.id, data: data);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _SpottedEmergencyCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _SpottedEmergencyCard({required this.docId, required this.data});

  Color _statusColor(String status) {
    switch (status) {
      case 'assigned':
        return AppTheme.successGreen;
      case 'dismissed':
        return AppTheme.textSecondary;
      default:
        return AppTheme.warningOrange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':
        return 'ASSIGNED';
      case 'dismissed':
        return 'DISMISSED';
      default:
        return 'PENDING';
    }
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReassignSheet(docId: docId, data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final description = data['description'] as String? ?? '';
    final rescuerId = data['reported_by_rescuer_id'] as String? ?? '';
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final assignedTo = data['assigned_rescuer_name'] as String?;
    final statusColor = _statusColor(status);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: status == 'pending' ? () => _showActionSheet(context) : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Spotted Emergency',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            timeago.format(createdAt),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
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
                      color: statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              // Meta row
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (rescuerId.isNotEmpty)
                    _MetaItem(
                      icon: Icons.person_outline,
                      text: 'Reported by: ${rescuerId.substring(0, 6)}...',
                    ),
                  if (lat != null && lng != null)
                    _MetaItem(
                      icon: Icons.location_on_outlined,
                      text:
                          '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    ),
                  if (assignedTo != null)
                    _MetaItem(
                      icon: Icons.assignment_ind_outlined,
                      text: 'Assigned to: $assignedTo',
                    ),
                ],
              ),
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showActionSheet(context),
                        icon: const Icon(
                          Icons.swap_horiz,
                          size: 16,
                          color: AppTheme.primaryBlue,
                        ),
                        label: const Text(
                          'Assign Rescuer',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('spotted_emergencies')
                            .doc(docId)
                            .update({
                              'status': 'dismissed',
                              'dismissed_at': FieldValue.serverTimestamp(),
                            });
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.textSecondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                      ),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reassign Bottom Sheet
// ---------------------------------------------------------------------------

class _ReassignSheet extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _ReassignSheet({required this.docId, required this.data});

  @override
  State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  String? _selectedRescuerId;
  String? _selectedRescuerName;
  bool _submitting = false;

  Future<void> _assignRescuer() async {
    if (_selectedRescuerId == null) return;
    setState(() => _submitting = true);

    try {
      final db = FirebaseFirestore.instance;

      // 1. Mark the spotted emergency as assigned
      await db.collection('spotted_emergencies').doc(widget.docId).update({
        'status': 'assigned',
        'assigned_rescuer_id': _selectedRescuerId,
        'assigned_rescuer_name': _selectedRescuerName,
        'assigned_at': FieldValue.serverTimestamp(),
      });

      // 2. Create a new open SOS from the spotted emergency data
      //    The rescuer will see it in their mission queue
      final lat = (widget.data['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (widget.data['longitude'] as num?)?.toDouble() ?? 0.0;
      final desc = widget.data['description'] as String? ?? '';
      final reporterMissionId =
          widget.data['reporting_mission_id'] as String? ?? '';

      final sosRef = await db.collection('sos_requests').add({
        'citizen_id': 'spotted_emergency',
        'citizen_name': 'Spotted Emergency',
        'latitude': lat,
        'longitude': lng,
        'status': 'assigned',
        'description':
            'SPOTTED BY RESCUER (Mission: ${reporterMissionId.isNotEmpty ? reporterMissionId.substring(0, 6) : 'N/A'}): $desc',
        'assigned_rescuer_id': _selectedRescuerId,
        'source': 'spotted_emergency',
        'spotted_emergency_id': widget.docId,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 3. Create the mission for the assigned rescuer
      await db.collection('missions').add({
        'sos_id': sosRef.id,
        'rescuer_id': _selectedRescuerId,
        'citizen_id': 'spotted_emergency',
        'status': 'en_route',
        'citizen_latitude': lat,
        'citizen_longitude': lng,
        'notes': 'Spotted emergency — dispatched by coordinator',
        'created_at': FieldValue.serverTimestamp(),
      });

      // 4. Increment active_mission_count for the assigned rescuer
      await db.collection('rescuers').doc(_selectedRescuerId).update({
        'active_mission_count': FieldValue.increment(1),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $_selectedRescuerName dispatched to spotted emergency.',
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Assign Rescuer',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick an available rescuer to dispatch to this spotted emergency.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          // Rescuer list
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rescuers')
                  .where('is_on_duty', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No rescuers on duty',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final rData = doc.data() as Map<String, dynamic>;
                    final firstName = rData['first_name'] as String? ?? '';
                    final lastName = rData['last_name'] as String? ?? '';
                    final fullName = '$firstName $lastName'.trim();
                    final initials = firstName.isNotEmpty && lastName.isNotEmpty
                        ? '${firstName[0]}${lastName[0]}'
                        : (fullName.isNotEmpty ? fullName[0] : 'R');
                    final activeMissions =
                        (rData['active_mission_count'] as int?) ?? 0;
                    final isSelected = _selectedRescuerId == doc.id;

                    return ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: isSelected
                                ? AppTheme.primaryBlue
                                : const Color(0xFFE3ECF8),
                            child: Text(
                              initials.toUpperCase(),
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: AppTheme.successGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        fullName.isNotEmpty ? fullName : 'Unnamed',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '$activeMissions active mission${activeMissions == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: activeMissions > 0
                              ? AppTheme.warningOrange
                              : AppTheme.successGreen,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: AppTheme.primaryBlue,
                            )
                          : null,
                      selected: isSelected,
                      selectedTileColor: AppTheme.primaryBlue.withValues(
                        alpha: 0.06,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedRescuerId = doc.id;
                          _selectedRescuerName = fullName;
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Dispatch button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_selectedRescuerId == null || _submitting)
                  ? null
                  : _assignRescuer,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _submitting
                    ? 'Dispatching...'
                    : _selectedRescuerId == null
                    ? 'Select a rescuer first'
                    : 'Dispatch $_selectedRescuerName',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppTheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppTheme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
