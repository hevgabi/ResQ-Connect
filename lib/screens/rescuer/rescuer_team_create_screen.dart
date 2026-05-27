import 'package:flutter/material.dart';
import '../../models/team_model.dart';
import '../../services/firestore_service.dart';

class RescuerTeamCreateScreen extends StatefulWidget {
  final String currentUserId;
  final TeamModel? existingTeam; // non-null = manage invites for existing team

  const RescuerTeamCreateScreen({
    super.key,
    required this.currentUserId,
    this.existingTeam,
  });

  @override
  State<RescuerTeamCreateScreen> createState() =>
      _RescuerTeamCreateScreenState();
}

class _RescuerTeamCreateScreenState extends State<RescuerTeamCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _teamId;
  TeamModel? _team;

  List<Map<String, dynamic>> _allRescuers = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _invitedIds = {};

  @override
  void initState() {
    super.initState();
    _team = widget.existingTeam;
    if (_team != null) {
      _teamId = _team!.id;
      _nameCtrl.text = _team!.name;
      _descCtrl.text = _team!.description;
    }
    _loadRescuers();
  }

  Future<void> _loadRescuers() async {
    setState(() => _isLoading = true);
    try {
      final rescuers = await FirestoreService.instance.getApprovedRescuers();
      // Exclude self
      final filtered = rescuers
          .where((r) => r['uid'] != widget.currentUserId)
          .toList();

      // If editing existing team, also load existing invites
      if (_teamId != null) {
        final invitesSnap = await FirestoreService.instance
            .teamInvitesStream(_teamId!)
            .first;
        for (final invite in invitesSnap) {
          if (invite.status == 'pending' || invite.status == 'accepted') {
            _invitedIds.add(invite.inviteeId);
          }
        }
        // Also mark current members
        if (_team != null) {
          for (final m in _team!.memberIds) {
            _invitedIds.add(m);
          }
        }
      }

      setState(() {
        _allRescuers = filtered;
        _filtered = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _allRescuers.where((r) {
        final name = ((r['display_name'] ?? r['first_name'] ?? '') as String)
            .toLowerCase();
        final email = ((r['email'] ?? '') as String).toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> _createTeamAndInvite(String inviteeId) async {
    // Create team first if not yet created
    if (_teamId == null) {
      if (_nameCtrl.text.trim().isEmpty) {
        _showError('Please enter a team name first.');
        return;
      }
      setState(() => _isSubmitting = true);
      try {
        final id = await FirestoreService.instance.createTeam(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          leaderId: widget.currentUserId,
        );
        _teamId = id;
      } catch (e) {
        setState(() => _isSubmitting = false);
        _showError('Failed to create team. Try again.');
        return;
      }
      setState(() => _isSubmitting = false);
    }

    await _sendInvite(inviteeId);
  }

  Future<void> _sendInvite(String inviteeId) async {
    if (_teamId == null) return;
    final invitee = _allRescuers.firstWhere(
      (r) => r['uid'] == inviteeId,
      orElse: () => {},
    );
    final inviteeName =
        invitee['display_name'] ?? invitee['first_name'] ?? 'Rescuer';

    final me = await FirestoreService.instance.getUser(widget.currentUserId);
    final myName = me?['display_name'] ?? me?['first_name'] ?? 'Leader';

    try {
      await FirestoreService.instance.sendTeamInvite(
        teamId: _teamId!,
        teamName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (_team?.name ?? 'Team'),
        inviterId: widget.currentUserId,
        inviterName: myName,
        inviteeId: inviteeId,
      );
      setState(() => _invitedIds.add(inviteeId));
    } catch (e) {
      _showError('Failed to send invite.');
    }
  }

  Future<void> _submitForApproval() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Team name is required.');
      return;
    }
    if (_teamId == null) {
      // Create team first (no invites yet, just submit solo)
      setState(() => _isSubmitting = true);
      try {
        final id = await FirestoreService.instance.createTeam(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          leaderId: widget.currentUserId,
        );
        _teamId = id;
      } catch (e) {
        setState(() => _isSubmitting = false);
        _showError('Failed to create team.');
        return;
      }
      setState(() => _isSubmitting = false);
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Team submitted for admin approval!'),
        backgroundColor: Color(0xFF1FAA59),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingTeam != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1FAA59),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditMode ? 'Invite Rescuers' : 'Create a Team',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          // Team name/desc (only if not edit mode)
          if (!isEditMode) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Team Details',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2B45),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Team Name *',
                      hintText: 'e.g. Alpha Rescue Team',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Brief description of your team',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search rescuers by name or email...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF546E7A)),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // Rescuer list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No rescuers found',
                      style: TextStyle(color: Color(0xFF546E7A)),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final r = _filtered[index];
                      final uid = r['uid'] as String;
                      final name =
                          r['display_name'] ?? r['first_name'] ?? 'Rescuer';
                      final email = r['email'] ?? '';
                      final isInvited = _invitedIds.contains(uid);
                      final isCurrentMember =
                          _team?.memberIds.contains(uid) ?? false;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(
                            0xFF1FAA59,
                          ).withOpacity(0.1),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Color(0xFF1FAA59),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                        trailing: isCurrentMember
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1FAA59,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Member',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF1FAA59),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : isInvited
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF6B00,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Invited',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFFF6B00),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: () => _createTeamAndInvite(uid),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF1FAA59),
                                ),
                                child: const Text('Invite'),
                              ),
                      );
                    },
                  ),
          ),

          // Submit button
          if (!isEditMode)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForApproval,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FAA59),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Team for Approval',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
