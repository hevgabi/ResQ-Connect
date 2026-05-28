import 'package:flutter/material.dart';
import '../../models/team_model.dart';
import '../../services/firestore_service.dart';

// ─── Step enum ────────────────────────────────────────────────────────────────
enum _Step { requirements, details, invites }

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
  // ── Step state ──────────────────────────────────────────────────────────────
  _Step _currentStep = _Step.requirements;

  // ── Step 1: Leader requirements ─────────────────────────────────────────────
  final _yearsCtrl = TextEditingController();
  final _motivationCtrl = TextEditingController();
  final _certCtrl = TextEditingController();
  final _trainingCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ── Step 2: Team details ────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // ── Step 3: Invites ─────────────────────────────────────────────────────────
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
      // Skip straight to invites when managing an existing team
      _currentStep = _Step.invites;
    }
    _loadRescuers();
  }

  Future<void> _loadRescuers() async {
    setState(() => _isLoading = true);
    try {
      final rescuers = await FirestoreService.instance.getApprovedRescuers();
      final filtered = rescuers
          .where((r) => r['uid'] != widget.currentUserId)
          .toList();

      if (_teamId != null) {
        final invitesSnap = await FirestoreService.instance
            .teamInvitesStream(_teamId!)
            .first;
        for (final invite in invitesSnap) {
          if (invite.status == 'pending' || invite.status == 'accepted') {
            _invitedIds.add(invite.inviteeId);
          }
        }
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

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _nextFromRequirements() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _currentStep = _Step.details);
  }

  void _nextFromDetails() {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Team name is required.');
      return;
    }
    setState(() => _currentStep = _Step.invites);
  }

  // ── Team creation + invite ──────────────────────────────────────────────────

  Future<void> _createTeamAndInvite(String inviteeId) async {
    if (_teamId == null) {
      setState(() => _isSubmitting = true);
      try {
        final id = await FirestoreService.instance.createTeam(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          leaderId: widget.currentUserId,
          leaderRequirements: {
            'years_experience': _yearsCtrl.text.trim(),
            'certifications': _certCtrl.text.trim(),
            'training': _trainingCtrl.text.trim(),
            'motivation': _motivationCtrl.text.trim(),
          },
        );
        _teamId = id;
      } catch (e) {
        setState(() => _isSubmitting = false);
        _showError('Failed to create team. Please try again.');
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
    if (invitee.isEmpty) return;

    final me = await FirestoreService.instance.getUser(widget.currentUserId);
    final myName = me?['display_name'] ?? me?['first_name'] ?? 'Leader';
    final teamName = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (_team?.name ?? 'Team');

    try {
      await FirestoreService.instance.sendTeamInvite(
        teamId: _teamId!,
        teamName: teamName,
        inviterId: widget.currentUserId,
        inviterName: myName,
        inviteeId: inviteeId,
      );
      setState(() => _invitedIds.add(inviteeId));
    } catch (e) {
      _showError('Failed to send invite. Please try again.');
    }
  }

  Future<void> _submitForApproval() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Team name is required.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      if (_teamId == null) {
        final id = await FirestoreService.instance.createTeam(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          leaderId: widget.currentUserId,
          leaderRequirements: {
            'years_experience': _yearsCtrl.text.trim(),
            'certifications': _certCtrl.text.trim(),
            'training': _trainingCtrl.text.trim(),
            'motivation': _motivationCtrl.text.trim(),
          },
        );
        _teamId = id;
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showError('Failed to create team. Please try again.');
      return;
    }
    setState(() => _isSubmitting = false);

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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingTeam != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1FAA59),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (!isEditMode && _currentStep != _Step.requirements) {
              setState(() {
                _currentStep = _Step.values[_currentStep.index - 1];
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          isEditMode
              ? 'Invite Rescuers'
              : _currentStep == _Step.requirements
              ? 'Leader Requirements'
              : _currentStep == _Step.details
              ? 'Team Details'
              : 'Invite Members',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: isEditMode
          ? _buildInviteStep()
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _currentStep == _Step.requirements
                  ? _buildRequirementsStep()
                  : _currentStep == _Step.details
                  ? _buildDetailsStep()
                  : _buildInviteStep(),
            ),
    );
  }

  // ── Step 1: Requirements ─────────────────────────────────────────────────────

  Widget _buildRequirementsStep() {
    return SingleChildScrollView(
      key: const ValueKey('requirements'),
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1FAA59).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF1FAA59).withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FAA59).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF1FAA59),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team Leader Qualification',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF1A2B45),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Admin will review your qualifications before approving your team.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _sectionLabel('Years of Experience in Rescue Operations *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _yearsCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(
                hint: 'e.g. 3',
                icon: Icons.work_history_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Required';
                }
                final n = int.tryParse(v.trim());
                if (n == null || n < 0) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _sectionLabel('Certifications / Licenses'),
            const SizedBox(height: 4),
            const Text(
              'e.g. EMT, Lifeguard, BSDF Certificate, First Aid — list all relevant ones',
              style: TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _certCtrl,
              maxLines: 2,
              decoration: _inputDecoration(
                hint: 'EMT Level II, BSDF Basic, Red Cross First Aid...',
                icon: Icons.card_membership_outlined,
              ),
            ),
            const SizedBox(height: 16),

            _sectionLabel('Emergency Training / Workshops Attended'),
            const SizedBox(height: 4),
            const Text(
              'e.g. USAR, Flood Response, Fire Safety seminar',
              style: TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _trainingCtrl,
              maxLines: 2,
              decoration: _inputDecoration(
                hint: 'NDRRMC Basic Training, Flood Rescue Workshop 2024...',
                icon: Icons.school_outlined,
              ),
            ),
            const SizedBox(height: 16),

            _sectionLabel('Motivation for Leading a Team *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _motivationCtrl,
              maxLines: 3,
              decoration: _inputDecoration(
                hint:
                    'Briefly explain why you want to lead a rescue team and how you plan to coordinate responses...',
                icon: Icons.edit_note_outlined,
              ),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? 'Please provide at least 20 characters'
                  : null,
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _nextFromRequirements,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FAA59),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Next: Team Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Team Details ─────────────────────────────────────────────────────

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Team Name *'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: _inputDecoration(
                    hint: 'e.g. Alpha Rescue Team',
                    icon: Icons.groups_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel('Description (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: _inputDecoration(
                    hint: 'Brief description of your team\'s focus area...',
                    icon: Icons.description_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() => _currentStep = _Step.requirements),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF546E7A),
                    side: const BorderSide(color: Color(0xFF546E7A)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _nextFromDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FAA59),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Next: Invite Members',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 3: Invite ───────────────────────────────────────────────────────────

  Widget _buildInviteStep() {
    return Column(
      key: const ValueKey('invites'),
      children: [
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
                          ? _statusBadge('Member', const Color(0xFF1FAA59))
                          : isInvited
                          ? _statusBadge('Invited', const Color(0xFFFF6B00))
                          : TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _createTeamAndInvite(uid),
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
        if (widget.existingTeam == null)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
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
              ],
            ),
          ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1A2B45),
    ),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0BEC5)),
    prefixIcon: Icon(icon, size: 18, color: const Color(0xFF90A4AE)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF1FAA59), width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _statusBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );

  @override
  void dispose() {
    _yearsCtrl.dispose();
    _motivationCtrl.dispose();
    _certCtrl.dispose();
    _trainingCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }
}
