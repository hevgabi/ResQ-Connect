import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../models/team_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../widgets/rescuer_bottom_nav.dart';
import 'rescuer_team_create_screen.dart';
import 'rescuer_invites_screen.dart';

class RescuerTeamScreen extends StatelessWidget {
  const RescuerTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1FAA59),
        automaticallyImplyLeading: false,
        title: const Text(
          'My Team',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          // Invite badge
          StreamBuilder<List<TeamInviteModel>>(
            stream: FirestoreService.instance.rescuerPendingInvitesStream(uid),
            builder: (context, snap) {
              final count = snap.data?.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline, color: Colors.white),
                    tooltip: 'Team Invites',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RescuerInvitesScreen(rescuerId: uid),
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFFD7263D),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          count > 9 ? '9+' : count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<TeamModel?>(
        stream: FirestoreService.instance.rescuerTeamStream(uid),
        builder: (context, activeSnap) {
          if (activeSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeTeam = activeSnap.data;

          if (activeTeam != null) {
            return _ActiveTeamView(team: activeTeam, currentUserId: uid);
          }

          // Check for pending team
          return StreamBuilder<TeamModel?>(
            stream: FirestoreService.instance.rescuerPendingTeamStream(uid),
            builder: (context, pendingSnap) {
              final pendingTeam = pendingSnap.data;

              if (pendingTeam != null) {
                return _PendingTeamView(team: pendingTeam, currentUserId: uid);
              }

              return _NoTeamView(currentUserId: uid);
            },
          );
        },
      ),
      bottomNavigationBar: const RescuerBottomNav(currentIndex: 2),
    );
  }
}

// ─── No Team View ─────────────────────────────────────────────────────────────

class _NoTeamView extends StatelessWidget {
  final String currentUserId;
  const _NoTeamView({required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1FAA59).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 40,
                color: Color(0xFF1FAA59),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "You're not in a team yet",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2B45),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a team, invite fellow rescuers, and submit for admin approval.',
              style: TextStyle(fontSize: 14, color: Color(0xFF546E7A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RescuerTeamCreateScreen(currentUserId: currentUserId),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Create a Team'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FAA59),
                  foregroundColor: Colors.white,
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
                        RescuerInvitesScreen(rescuerId: currentUserId),
                  ),
                ),
                icon: const Icon(Icons.mail_outline),
                label: const Text('View Invites'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1FAA59),
                  side: const BorderSide(color: Color(0xFF1FAA59)),
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
    );
  }
}

// ─── Pending Approval View ─────────────────────────────────────────────────────

class _PendingTeamView extends StatelessWidget {
  final TeamModel team;
  final String currentUserId;
  const _PendingTeamView({required this.team, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final isLeader = team.leaderId == currentUserId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFCC00).withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: Color(0xFFE65100),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Waiting for Admin Approval',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFFE65100),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your team "${team.name}" has been submitted. An admin will review it shortly.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5D4037),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Team info card
          _TeamInfoCard(team: team),
          const SizedBox(height: 16),

          // Members list
          if (isLeader)
            _TeamMembersCard(team: team, currentUserId: currentUserId),
        ],
      ),
    );
  }
}

// ─── Active Team View ─────────────────────────────────────────────────────────

class _ActiveTeamView extends StatelessWidget {
  final TeamModel team;
  final String currentUserId;
  const _ActiveTeamView({required this.team, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final isLeader = team.leaderId == currentUserId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1FAA59).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1FAA59).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1FAA59),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Team Active',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1FAA59),
                  ),
                ),
                const Spacer(),
                if (isLeader)
                  Text(
                    'Leader',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF1FAA59).withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _TeamInfoCard(team: team),
          const SizedBox(height: 16),

          _MemberStatusCard(team: team, currentUserId: currentUserId),

          if (isLeader) ...[
            const SizedBox(height: 16),
            _TeamMembersCard(team: team, currentUserId: currentUserId),
          ],
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _TeamInfoCard extends StatelessWidget {
  final TeamModel team;
  const _TeamInfoCard({required this.team});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          Row(
            children: [
              const Icon(Icons.groups, color: Color(0xFF1FAA59), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  team.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
              ),
            ],
          ),
          if (team.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              team.description,
              style: const TextStyle(fontSize: 13, color: Color(0xFF546E7A)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.people_outline,
                size: 14,
                color: Color(0xFF546E7A),
              ),
              const SizedBox(width: 4),
              Text(
                '${team.memberIds.length} member${team.memberIds.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF546E7A)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Member Status Card (read-only awareness) ─────────────────────────────────

class _MemberStatusCard extends StatelessWidget {
  final TeamModel team;
  final String currentUserId;
  const _MemberStatusCard({required this.team, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          const Text(
            'Team Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A2B45),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Live mission awareness for your team',
            style: TextStyle(fontSize: 12, color: Color(0xFF546E7A)),
          ),
          const SizedBox(height: 12),
          StreamBuilder<Map<String, String?>>(
            stream: FirestoreService.instance.teamMemberMissionStatusStream(
              team.memberIds,
            ),
            builder: (context, snap) {
              final statusMap = snap.data ?? {};
              final members = team.memberIds;

              return Column(
                children: members.map((memberId) {
                  final status = statusMap[memberId];
                  final isMe = memberId == currentUserId;
                  return FutureBuilder<Map<String, dynamic>?>(
                    future: FirestoreService.instance.getUser(memberId),
                    builder: (context, userSnap) {
                      final name =
                          userSnap.data?['display_name'] ??
                          userSnap.data?['first_name'] ??
                          'Rescuer';
                      return _MemberStatusTile(
                        name: isMe ? '$name (You)' : name,
                        isLeader: memberId == team.leaderId,
                        missionStatus: status,
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemberStatusTile extends StatelessWidget {
  final String name;
  final bool isLeader;
  final String? missionStatus;

  const _MemberStatusTile({
    required this.name,
    required this.isLeader,
    this.missionStatus,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (missionStatus == 'en_route') {
      statusColor = const Color(0xFFFF6B00);
      statusLabel = 'En Route';
      statusIcon = Icons.directions_run;
    } else if (missionStatus == 'on_site') {
      statusColor = const Color(0xFFD7263D);
      statusLabel = 'On Site';
      statusIcon = Icons.place;
    } else {
      statusColor = const Color(0xFF1FAA59);
      statusLabel = 'Available';
      statusIcon = Icons.check_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withOpacity(0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
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
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2B45),
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
                          color: const Color(0xFF1FAA59).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Leader',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF1FAA59),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
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
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Team Members Management Card (leader only) ───────────────────────────────

class _TeamMembersCard extends StatelessWidget {
  final TeamModel team;
  final String currentUserId;

  const _TeamMembersCard({required this.team, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          Row(
            children: [
              const Text(
                'Manage Invites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2B45),
                ),
              ),
              const Spacer(),
              if (team.status == 'pending')
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RescuerTeamCreateScreen(
                        currentUserId: currentUserId,
                        existingTeam: team,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('Invite'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1FAA59),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<TeamInviteModel>>(
            stream: FirestoreService.instance.teamInvitesStream(team.id),
            builder: (context, snap) {
              final invites = snap.data ?? [];
              final pending = invites
                  .where((i) => i.status == 'pending')
                  .toList();

              if (pending.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No pending invites',
                    style: TextStyle(fontSize: 13, color: Color(0xFF546E7A)),
                  ),
                );
              }

              return Column(
                children: pending.map((invite) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 16,
                          color: Color(0xFFFF6B00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FutureBuilder<Map<String, dynamic>?>(
                            future: FirestoreService.instance.getUser(
                              invite.inviteeId,
                            ),
                            builder: (context, userSnap) {
                              final name =
                                  userSnap.data?['display_name'] ??
                                  userSnap.data?['first_name'] ??
                                  'Rescuer';
                              return Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1A2B45),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B00).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFFF6B00),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
