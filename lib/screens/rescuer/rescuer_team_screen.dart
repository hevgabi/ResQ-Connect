import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/team_model.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import '../../screens/rescuer/rescuer_team_create_screen.dart';
import '../../screens/rescuer/rescuer_invites_screen.dart';
import '../../services/firestore_service.dart';

class RescuerTeamScreen extends StatefulWidget {
  const RescuerTeamScreen({super.key});

  @override
  State<RescuerTeamScreen> createState() => _RescuerTeamScreenState();
}

class _RescuerTeamScreenState extends State<RescuerTeamScreen> {
  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFD32F2F);

  final _db = FirebaseFirestore.instance;
  final _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Dual-path stream: user's own team_id field OR member_ids query
  Stream<TeamModel?> get _teamStream {
    return _db.collection('users').doc(_currentUid).snapshots().asyncMap((
      userSnap,
    ) async {
      final userData = userSnap.data() as Map<String, dynamic>? ?? {};
      final teamId = userData['team_id'] as String?;

      // Path A: user has team_id on their own doc
      if (teamId != null && teamId.isNotEmpty) {
        try {
          final teamDoc = await _db.collection('teams').doc(teamId).get();
          if (teamDoc.exists) {
            final t = TeamModel.fromFirestore(teamDoc);
            if (t.status == 'active') return t;
          }
        } catch (_) {}
      }

      // Path B: fallback — query teams where member_ids contains this user
      try {
        final snap = await _db
            .collection('teams')
            .where('member_ids', arrayContains: _currentUid)
            .get();
        final activeDocs = snap.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return d['status'] == 'active';
        }).toList();
        if (activeDocs.isNotEmpty) {
          return TeamModel.fromFirestore(activeDocs.first);
        }
      } catch (_) {}

      return null;
    });
  }

  // ── Leave Team (Member only) ───────────────────────────────────────────────
  Future<void> _showLeaveDialog(TeamModel team) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to leave this team? '
              'Please provide a reason.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                border: OutlineInputBorder(),
                hintText: 'e.g. Personal reasons, schedule conflict...',
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
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Leave Team',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final reason = reasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a reason for leaving.'),
            backgroundColor: _red,
          ),
        );
        return;
      }
      try {
        // Remove from team member_ids
        await _db.collection('teams').doc(team.id).update({
          'member_ids': FieldValue.arrayRemove([_currentUid]),
        });
        // Clear team_id from own user doc
        await _db.collection('users').doc(_currentUid).update({
          'team_id': FieldValue.delete(),
          'team_joined_at': FieldValue.delete(),
        });
        // Log the leave reason
        await _db.collection('team_leave_logs').add({
          'team_id': team.id,
          'team_name': team.name,
          'rescuer_id': _currentUid,
          'reason': reason,
          'left_at': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have left the team.'),
              backgroundColor: _green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red),
          );
        }
      }
    }
  }

  // ── Disband (Leader only) ─────────────────────────────────────────────────
  Future<void> _showDisbandDialog(TeamModel team) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request to Disband'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Disbanding will remove all members and deactivate the team. '
              'This requires admin approval.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
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
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Request Disband',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _db.collection('teams').doc(team.id).update({
          'disband_status': 'pending',
          'disband_reason': reasonCtrl.text.trim(),
          'disband_requested_at': FieldValue.serverTimestamp(),
          'disband_requested_by': _currentUid,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disband request submitted for admin review.'),
              backgroundColor: _green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red),
          );
        }
      }
    }
  }

  // ── Invite dialog (Leader only) ───────────────────────────────────────────
  Future<void> _showInviteDialog(TeamModel team) async {
    final emailCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Member'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Rescuer email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Send Invite',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final email = emailCtrl.text.trim();
        final userSnap = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .where('role', isEqualTo: 'rescuer')
            .limit(1)
            .get();

        if (userSnap.docs.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No rescuer found with that email.'),
                backgroundColor: _red,
              ),
            );
          }
          return;
        }

        final inviteeDoc = userSnap.docs.first;
        final inviteeId = inviteeDoc.id;

        if (inviteeId == _currentUid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You cannot invite yourself.'),
                backgroundColor: _red,
              ),
            );
          }
          return;
        }

        if (team.memberIds.contains(inviteeId)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This rescuer is already a team member.'),
                backgroundColor: _red,
              ),
            );
          }
          return;
        }

        final meData = await FirestoreService.instance.getUser(_currentUid);
        final meName =
            '${meData?['first_name'] ?? ''} ${meData?['last_name'] ?? ''}'
                .trim();

        await FirestoreService.instance.sendTeamInvite(
          teamId: team.id,
          teamName: team.name,
          inviterId: _currentUid,
          inviterName: meName.isNotEmpty ? meName : 'Leader',
          inviteeId: inviteeId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invite sent!'),
              backgroundColor: _green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: _red),
          );
        }
      }
    }
  }

  // ── Approve mission request (Leader only) ────────────────────────────────
  Future<void> _approveMissionRequest(
    String requestId,
    String missionId,
  ) async {
    try {
      await _db.collection('mission_requests').doc(requestId).update({
        'status': 'approved',
        'approved_by': _currentUid,
        'approved_at': FieldValue.serverTimestamp(),
      });
      // Update the actual mission status to active
      await _db.collection('missions').doc(missionId).update({
        'status': 'en_route',
        'approved_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mission approved!'),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _red),
        );
      }
    }
  }

  Future<void> _rejectMissionRequest(String requestId) async {
    try {
      await _db.collection('mission_requests').doc(requestId).update({
        'status': 'rejected',
        'rejected_by': _currentUid,
        'rejected_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission request rejected.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: _red),
        );
      }
    }
  }

  // ── Sheet helpers ─────────────────────────────────────────────────────────
  Widget _sheetHandle() => Container(
    width: 40,
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.grey[300],
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _sheetTitle(IconData icon, String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        Icon(icon, color: _green),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  void _showMembersSheet(TeamModel team) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            _sheetHandle(),
            _sheetTitle(Icons.group, 'Team Members'),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: team.memberIds.length,
                itemBuilder: (_, i) => _MemberStatusTile(
                  uid: team.memberIds[i],
                  isLeader: team.memberIds[i] == team.leaderId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMissionsSheet(TeamModel team) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            _sheetHandle(),
            _sheetTitle(Icons.assignment, 'Team Missions'),
            const Divider(),
            Expanded(
              child: _TeamMissionsList(
                memberIds: team.memberIds,
                scrollController: controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInvitesSheet(TeamModel team) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, controller) => Column(
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: _green),
                  const SizedBox(width: 8),
                  const Text(
                    'Manage Invites',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (team.leaderId == _currentUid)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showInviteDialog(team);
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Invite'),
                      style: TextButton.styleFrom(foregroundColor: _green),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _TeamInvitesList(
                teamId: team.id,
                scrollController: controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3-dot menu ────────────────────────────────────────────────────────────
  void _showTeamMenu(BuildContext context, TeamModel team) {
    final isLeader = team.leaderId == _currentUid;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            ListTile(
              leading: const Icon(Icons.group, color: _green),
              title: const Text('Members'),
              onTap: () {
                Navigator.pop(ctx);
                _showMembersSheet(team);
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment, color: _green),
              title: const Text('Mission List'),
              onTap: () {
                Navigator.pop(ctx);
                _showMissionsSheet(team);
              },
            ),
            if (isLeader) ...[
              ListTile(
                leading: const Icon(Icons.person_add, color: _green),
                title: const Text('Invites'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showInvitesSheet(team);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.group_remove, color: _red),
                title: const Text(
                  'Disband Team',
                  style: TextStyle(color: _red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDisbandDialog(team);
                },
              ),
            ] else ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: _red),
                title: const Text('Leave Team', style: TextStyle(color: _red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLeaveDialog(team);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TeamModel?>(
      stream: _teamStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final team = snap.data;
        if (team == null) return _NoTeamView(currentUid: _currentUid);

        final isLeader = team.leaderId == _currentUid;

        return Scaffold(
          extendBody: true,
          backgroundColor: const Color(0xFFF5F7FA),
          bottomNavigationBar: const RescuerBottomNav(currentIndex: 2),
          appBar: AppBar(
            backgroundColor: _green,
            title: const Text(
              'My Team',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
              if (isLeader)
                IconButton(
                  icon: const Icon(Icons.mail_outline, color: Colors.white),
                  onPressed: () => _showInvitesSheet(team),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showTeamMenu(context, team),
              ),
            ],
          ),
          body: RefreshIndicator(
            color: _green,
            onRefresh: () async => setState(() {}),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatusBanner(status: team.status, isLeader: isLeader),
                        const SizedBox(height: 12),
                        _TeamInfoCard(team: team),
                        const SizedBox(height: 12),
                        _TeamStatChips(team: team),
                        const SizedBox(height: 16),

                        // ── Leader-only: Pending mission requests ──────────
                        if (isLeader)
                          _PendingMissionRequests(
                            teamId: team.id,
                            memberIds: team.memberIds,
                            onApprove: _approveMissionRequest,
                            onReject: _rejectMissionRequest,
                          ),

                        const Text(
                          'Active Missions',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                _ActiveMissionSliver(memberIds: team.memberIds),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BANNER — shows Leader / Member role
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.isLeader});
  final String status;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    final color = isActive ? const Color(0xFF2E7D32) : const Color(0xFFF57F17);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            isActive
                ? 'Team Active'
                : 'Team ${status[0].toUpperCase()}${status.substring(1)}',
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isLeader ? 'Leader' : 'Member',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEAM INFO CARD
// ─────────────────────────────────────────────────────────────────────────────
class _TeamInfoCard extends StatelessWidget {
  const _TeamInfoCard({required this.team});
  final TeamModel team;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups, size: 28, color: Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (team.description.isNotEmpty)
                  Text(
                    team.description,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 14,
                      color: Colors.black45,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${team.memberIds.length} member${team.memberIds.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEAM STAT CHIPS
// ─────────────────────────────────────────────────────────────────────────────
class _TeamStatChips extends StatelessWidget {
  const _TeamStatChips({required this.team});
  final TeamModel team;

  @override
  Widget build(BuildContext context) {
    final ids = team.memberIds.isEmpty ? ['__none__'] : team.memberIds;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .where('rescuer_id', whereIn: ids)
          .where('status', whereIn: ['en_route', 'on_site'])
          .snapshots(),
      builder: (context, mSnap) {
        final activeMissions = mSnap.data?.docs.length ?? 0;
        return Row(
          children: [
            _Chip(
              icon: Icons.group,
              label: '${team.memberIds.length} Members',
              color: const Color(0xFF1565C0),
              bg: const Color(0xFFE3F2FD),
            ),
            const SizedBox(width: 8),
            _Chip(
              icon: Icons.assignment_late_outlined,
              label: '$activeMissions Active',
              color: activeMissions > 0 ? const Color(0xFFD32F2F) : Colors.grey,
              bg: activeMissions > 0
                  ? const Color(0xFFFFEBEE)
                  : const Color(0xFFF5F5F5),
            ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
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

// ─────────────────────────────────────────────────────────────────────────────
// PENDING MISSION REQUESTS — Leader only
// Shows missions requested by members that need leader approval
// ─────────────────────────────────────────────────────────────────────────────
class _PendingMissionRequests extends StatelessWidget {
  const _PendingMissionRequests({
    required this.teamId,
    required this.memberIds,
    required this.onApprove,
    required this.onReject,
  });
  final String teamId;
  final List<String> memberIds;
  final Function(String requestId, String missionId) onApprove;
  final Function(String requestId) onReject;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mission_requests')
          .where('team_id', isEqualTo: teamId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Pending Approvals',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final missionId = data['mission_id'] as String? ?? '';
              final requesterName =
                  data['requester_name'] as String? ?? 'A member';
              final sosDesc =
                  data['sos_description'] as String? ?? 'No description';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFE65100).withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Awaiting Your Approval',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$requesterName wants to accept a mission',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sosDesc,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onReject(doc.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFD32F2F),
                              side: const BorderSide(color: Color(0xFFD32F2F)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => onApprove(doc.id, missionId),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
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
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVE MISSIONS SLIVER
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveMissionSliver extends StatelessWidget {
  const _ActiveMissionSliver({required this.memberIds});
  final List<String> memberIds;

  @override
  Widget build(BuildContext context) {
    if (memberIds.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Text(
            'No active missions',
            style: TextStyle(color: Colors.black45, fontSize: 13),
          ),
        ),
      );
    }
    final ids = memberIds.isEmpty ? ['__none__'] : memberIds;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .where('rescuer_id', whereIn: ids)
          .where('status', whereIn: ['en_route', 'on_site'])
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text(
                'No active missions right now',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'en_route';
            final isEnRoute = status == 'en_route';
            final statusColor = isEnRoute
                ? const Color(0xFFE65100)
                : const Color(0xFF1565C0);
            final bgColor = isEnRoute
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFE3F2FD);
            final notes = data['notes'] as String? ?? 'No additional notes';
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEnRoute ? Icons.directions_run : Icons.location_on,
                        size: 20,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Mission #${doc.id.substring(0, 6).toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isEnRoute ? 'En Route' : 'On Site',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notes,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          _MissionRescuerRow(
                            rescuerId: data['rescuer_id'] as String? ?? '',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }, childCount: docs.length),
        );
      },
    );
  }
}

class _MissionRescuerRow extends StatelessWidget {
  const _MissionRescuerRow({required this.rescuerId});
  final String rescuerId;

  @override
  Widget build(BuildContext context) {
    if (rescuerId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(rescuerId)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final d = snap.data!.data() as Map<String, dynamic>? ?? {};
        final name = '${d['first_name'] ?? ''} ${d['last_name'] ?? ''}'.trim();
        if (name.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 12, color: Colors.black38),
              const SizedBox(width: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEMBER STATUS TILE
// ─────────────────────────────────────────────────────────────────────────────
class _MemberStatusTile extends StatelessWidget {
  const _MemberStatusTile({required this.uid, required this.isLeader});
  final String uid;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 50,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final name = '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'
            .trim();
        final displayName = name.isNotEmpty
            ? name
            : (data['name'] as String? ?? 'Unknown');
        final availStatus =
            data['availability_status'] as String? ?? 'off_duty';
        final initial = displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : '?';

        Color statusColor;
        String statusLabel;
        IconData statusIcon;
        switch (availStatus) {
          case 'available':
            statusColor = const Color(0xFF2E7D32);
            statusLabel = 'Ready';
            statusIcon = Icons.check_circle;
            break;
          case 'on_mission':
            statusColor = const Color(0xFFE65100);
            statusLabel = 'On The Way';
            statusIcon = Icons.directions_run;
            break;
          case 'on_site':
            statusColor = const Color(0xFF1565C0);
            statusLabel = 'On Site';
            statusIcon = Icons.location_on;
            break;
          default:
            statusColor = Colors.grey;
            statusLabel = 'Off Duty';
            statusIcon = Icons.radio_button_unchecked;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2E7D32).withOpacity(0.15),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLeader) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Leader',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEAM MISSIONS LIST
// ─────────────────────────────────────────────────────────────────────────────
class _TeamMissionsList extends StatelessWidget {
  const _TeamMissionsList({
    required this.memberIds,
    required this.scrollController,
  });
  final List<String> memberIds;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (memberIds.isEmpty) {
      return const Center(
        child: Text('No members', style: TextStyle(color: Colors.black45)),
      );
    }
    final ids = memberIds.isEmpty ? ['__none__'] : memberIds;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .where('rescuer_id', whereIn: ids)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        // Sort newest first in Dart
        final sorted = List.from(docs)
          ..sort((a, b) {
            final aT = (a.data() as Map)['created_at'] as Timestamp?;
            final bT = (b.data() as Map)['created_at'] as Timestamp?;
            if (aT == null || bT == null) return 0;
            return bT.compareTo(aT);
          });
        if (sorted.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No missions yet',
                style: TextStyle(color: Colors.black45),
              ),
            ),
          );
        }
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final data = sorted[i].data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? '';
            Color statusColor;
            String statusLabel;
            IconData statusIcon;
            switch (status) {
              case 'en_route':
                statusColor = const Color(0xFFE65100);
                statusLabel = 'En Route';
                statusIcon = Icons.directions_run;
                break;
              case 'on_site':
                statusColor = const Color(0xFF1565C0);
                statusLabel = 'On Site';
                statusIcon = Icons.location_on;
                break;
              case 'completed':
                statusColor = const Color(0xFF2E7D32);
                statusLabel = 'Completed';
                statusIcon = Icons.check_circle;
                break;
              default:
                statusColor = Colors.grey;
                statusLabel = status;
                statusIcon = Icons.help_outline;
            }
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                backgroundColor: statusColor.withOpacity(0.12),
                child: Icon(statusIcon, color: statusColor, size: 18),
              ),
              title: Text(
                'Mission ${sorted[i].id.substring(0, 6).toUpperCase()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                data['notes'] as String? ?? 'No notes',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEAM INVITES LIST
// ─────────────────────────────────────────────────────────────────────────────
class _TeamInvitesList extends StatelessWidget {
  const _TeamInvitesList({
    required this.teamId,
    required this.scrollController,
  });
  final String teamId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('team_invites')
          .where('team_id', isEqualTo: teamId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No invites sent yet',
                style: TextStyle(color: Colors.black45),
              ),
            ),
          );
        }
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'pending';
            final name =
                data['invitee_name'] as String? ??
                data['invitee_email'] as String? ??
                'Unknown';
            Color statusColor;
            switch (status) {
              case 'accepted':
                statusColor = const Color(0xFF2E7D32);
                break;
              case 'declined':
                statusColor = const Color(0xFFD32F2F);
                break;
              default:
                statusColor = const Color(0xFFF57F17);
            }
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF2E7D32).withOpacity(0.1),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              subtitle: data['invitee_email'] != null
                  ? Text(
                      data['invitee_email'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    )
                  : null,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${status[0].toUpperCase()}${status.substring(1)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NO TEAM VIEW — with Create + View Invites buttons
// ─────────────────────────────────────────────────────────────────────────────
class _NoTeamView extends StatefulWidget {
  final String currentUid;
  const _NoTeamView({required this.currentUid});

  @override
  State<_NoTeamView> createState() => _NoTeamViewState();
}

class _NoTeamViewState extends State<_NoTeamView> {
  static const _green = Color(0xFF2E7D32);
  int _pendingInvites = 0;

  @override
  void initState() {
    super.initState();
    FirestoreService.instance
        .rescuerPendingInvitesStream(widget.currentUid)
        .listen((invites) {
          if (mounted) setState(() => _pendingInvites = invites.length);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      bottomNavigationBar: const RescuerBottomNav(currentIndex: 2),
      appBar: AppBar(
        backgroundColor: _green,
        title: const Text(
          'My Team',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, size: 72, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'No Team Yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You are not part of any team.\nCreate your own or wait for an invite.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RescuerTeamCreateScreen(
                        currentUserId: widget.currentUid,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Create a Team',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RescuerInvitesScreen(rescuerId: widget.currentUid),
                    ),
                  ),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.mail_outline),
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
                            constraints: const BoxConstraints(
                              minWidth: 15,
                              minHeight: 15,
                            ),
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
                  ),
                  label: Text(
                    _pendingInvites > 0
                        ? 'View Invites ($_pendingInvites pending)'
                        : 'View Invites',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
