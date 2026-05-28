import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/team_model.dart';
import '../../services/firestore_service.dart';

class AdminTeamsScreen extends StatefulWidget {
  const AdminTeamsScreen({super.key});

  @override
  State<AdminTeamsScreen> createState() => _AdminTeamsScreenState();
}

class _AdminTeamsScreenState extends State<AdminTeamsScreen> {
  String _filter = 'pending';

  static const _filters = [
    ('pending', 'Pending'),
    ('active', 'Active'),
    ('disband', 'Disband'),
    ('rejected', 'Rejected'),
  ];

  List<TeamModel> _applyFilter(List<TeamModel> teams) {
    if (_filter == 'disband') {
      return teams.where((t) => t.disbandStatus == 'pending').toList();
    }
    return teams.where((t) => t.status == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<int>(
          stream: FirestoreService.instance.pendingTeamsCountStream(),
          builder: (context, snap) {
            final count = snap.data ?? 0;
            return Row(
              children: [
                const Text(
                  'Teams',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7263D),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: Colors.white,
            child: Row(
              children: _filters.map((f) {
                final isSelected = _filter == f.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isSelected
                                ? const Color(0xFF0D47A1)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        f.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? const Color(0xFF0D47A1)
                              : const Color(0xFF546E7A),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // Team list
          Expanded(
            child: StreamBuilder<List<TeamModel>>(
              stream: FirestoreService.instance.allTeamsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snap.data ?? [];
                final teams = _applyFilter(all);

                if (teams.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 56,
                            color: const Color(0xFF546E7A).withOpacity(0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filter == 'pending'
                                ? 'No pending team applications'
                                : _filter == 'active'
                                ? 'No active teams'
                                : _filter == 'disband'
                                ? 'No pending disband requests'
                                : 'No rejected teams',
                            style: const TextStyle(
                              color: Color(0xFF546E7A),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: teams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final team = teams[index];
                    if (_filter == 'disband') {
                      return _TeamCard(
                        team: team,
                        onApproveDisband: () => _approveDisband(team),
                        onRejectDisband: () => _rejectDisband(team),
                      );
                    }
                    return _TeamCard(
                      team: team,
                      onApprove: _filter == 'pending'
                          ? () => _approve(team)
                          : null,
                      onReject: _filter == 'pending'
                          ? () => _reject(team)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(TeamModel team) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Team'),
        content: Text('Approve "${team.name}"? This will activate the team.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1FAA59),
            ),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirestoreService.instance.approveTeam(team.id, adminId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${team.name}" approved!'),
            backgroundColor: const Color(0xFF1FAA59),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to approve team.')),
        );
      }
    }
  }

  Future<void> _reject(TeamModel team) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rejecting "${team.name}". Provide a reason:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason for rejection...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD7263D),
            ),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirestoreService.instance.rejectTeam(
        team.id,
        adminId,
        reasonCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${team.name}" rejected.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to reject team.')));
      }
    }
  }

  Future<void> _approveDisband(TeamModel team) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Disband'),
        content: Text(
          'Approving this will permanently disband "${team.name}" and remove all members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD7263D),
            ),
            child: const Text(
              'Approve Disband',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirestoreService.instance.approveDisbandTeam(team.id, adminId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${team.name}" has been disbanded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to disband team.')),
        );
      }
    }
  }

  Future<void> _rejectDisband(TeamModel team) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Disband Request'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Provide a reason for rejecting the disband of "${team.name}":',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Reason...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
            ),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirestoreService.instance.rejectDisbandTeam(
        team.id,
        adminId,
        reasonCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disband request for "${team.name}" rejected.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reject disband request.')),
        );
      }
    }
  }
}

class _TeamCard extends StatelessWidget {
  final TeamModel team;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onApproveDisband;
  final VoidCallback? onRejectDisband;

  const _TeamCard({
    required this.team,
    this.onApprove,
    this.onReject,
    this.onApproveDisband,
    this.onRejectDisband,
  });

  @override
  Widget build(BuildContext context) {
    final isDisbandView = onApproveDisband != null;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isDisbandView) {
      statusColor = const Color(0xFFD7263D);
      statusLabel = 'Disband Requested';
      statusIcon = Icons.group_remove_outlined;
    } else {
      switch (team.status) {
        case 'active':
          statusColor = const Color(0xFF1FAA59);
          statusLabel = 'Active';
          statusIcon = Icons.check_circle;
          break;
        case 'rejected':
          statusColor = const Color(0xFFD7263D);
          statusLabel = 'Rejected';
          statusIcon = Icons.cancel;
          break;
        default:
          statusColor = const Color(0xFFFF6B00);
          statusLabel = 'Pending';
          statusIcon = Icons.hourglass_top_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.groups, color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A2B45),
                      ),
                    ),
                    if (team.description.isNotEmpty)
                      Text(
                        team.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF546E7A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Stats row
          Row(
            children: [
              _InfoChip(
                icon: Icons.people_outline,
                label: '${team.memberIds.length} members',
              ),
              const SizedBox(width: 8),
              _InfoChip(icon: Icons.shield_outlined, label: 'Leader assigned'),
            ],
          ),

          // Leader requirements — shown to admin on pending teams
          if (team.status == 'pending' &&
              team.leaderRequirements != null &&
              team.leaderRequirements!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1).withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D47A1).withOpacity(0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: Color(0xFF0D47A1),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Leader Qualifications',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ReqRow(
                    label: 'Experience',
                    value:
                        '${team.leaderRequirements!['years_experience'] ?? '-'} year(s)',
                  ),
                  if ((team.leaderRequirements!['certifications'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _ReqRow(
                      label: 'Certifications',
                      value: team.leaderRequirements!['certifications']
                          .toString(),
                    ),
                  if ((team.leaderRequirements!['training'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _ReqRow(
                      label: 'Training',
                      value: team.leaderRequirements!['training'].toString(),
                    ),
                  if ((team.leaderRequirements!['motivation'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _ReqRow(
                      label: 'Motivation',
                      value: team.leaderRequirements!['motivation'].toString(),
                    ),
                ],
              ),
            ),
          ],

          // Disband reason — shown on disband tab
          if (isDisbandView &&
              team.disbandReason != null &&
              team.disbandReason!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD7263D).withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFD7263D).withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Color(0xFFD7263D),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Reason for Disbanding',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD7263D),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    team.disbandReason!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1A2B45),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Rejection reason
          if (team.status == 'rejected' &&
              team.rejectionReason != null &&
              team.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD7263D).withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFFD7263D),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      team.rejectionReason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD7263D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons — team approval
          if (onApprove != null && onReject != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD7263D),
                      side: const BorderSide(color: Color(0xFFD7263D)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1FAA59),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],

          // Action buttons — disband approval
          if (onApproveDisband != null && onRejectDisband != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRejectDisband,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D47A1),
                      side: const BorderSide(color: Color(0xFF0D47A1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Keep Team'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApproveDisband,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD7263D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Disband'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDE3EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF546E7A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
          ),
        ],
      ),
    );
  }
}

class _ReqRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReqRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF546E7A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: Color(0xFF1A2B45)),
            ),
          ),
        ],
      ),
    );
  }
}
