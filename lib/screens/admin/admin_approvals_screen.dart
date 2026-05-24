import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() =>
      _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  String _roleFilter = 'all';

  static const _roleFilters = [
    ('all', 'All'),
    ('citizen', 'Citizens'),
    ('rescuer', 'Rescuers'),
    ('moderator', 'Moderators'),
  ];

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> users) {
    if (_roleFilter == 'all') return users;
    return users
        .where((u) =>
    ((u['role'] as String?) ?? '').toLowerCase() == _roleFilter)
        .toList();
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
          stream:
          FirestoreService.instance.pendingApprovalsCountStream(),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Row(
              children: [
                const Text(
                  'Pending Approvals',
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
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
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
          // ── Filter chips ─────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _roleFilters.map((f) {
                  final isSelected = _roleFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.$2),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _roleFilter = f.$1),
                      selectedColor: const Color(0xFF0D47A1)
                          .withValues(alpha: 0.15),
                      checkmarkColor: const Color(0xFF0D47A1),
                      labelStyle: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF0D47A1)
                            : const Color(0xFF546E7A),
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF0D47A1)
                            : Colors.grey.shade300,
                      ),
                      backgroundColor: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Pending users list ───────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream:
              FirestoreService.instance.pendingUsersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return _ApprovalSkeleton();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading approvals: ${snapshot.error}',
                        style: const TextStyle(
                            color: Color(0xFF546E7A)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const _EmptyApprovals();
                }

                final filtered = _applyFilter(snapshot.data!);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No pending registrations for this role.',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _ApprovalCard(
                      user: filtered[index],
                      onApprove: () =>
                          _approve(context, filtered[index]),
                      onReject: () =>
                          _showRejectDialog(context, filtered[index]),
                      onViewDetails: () =>
                          _showDetails(context, filtered[index]),
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

  // ── Approve ──────────────────────────────────────────────────────────────
  Future<void> _approve(
      BuildContext context, Map<String, dynamic> user) async {
    final adminId =
        FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final name = (user['display_name'] as String?) ??
        (user['first_name'] as String?) ??
        'User';

    try {
      await FirestoreService.instance
          .approveUser(user['uid'] as String, adminId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name has been approved.'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    }
  }

  // ── Reject dialog ─────────────────────────────────────────────────────────
  void _showRejectDialog(
      BuildContext context, Map<String, dynamic> user) {
    final reasonCtrl = TextEditingController();
    final name = (user['display_name'] as String?) ??
        (user['first_name'] as String?) ??
        'User';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reject $name?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This user will be notified that their registration was rejected.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF546E7A)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText:
                'e.g. Duplicate account, incomplete info...',
                labelStyle: const TextStyle(
                    fontSize: 13, color: Color(0xFF546E7A)),
                hintStyle: const TextStyle(
                    fontSize: 13, color: Color(0xFFB0BEC5)),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFF0D47A1), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF546E7A)),
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _reject(
                  context, user, reasonCtrl.text.trim());
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD7263D),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _reject(BuildContext context,
      Map<String, dynamic> user, String reason) async {
    final adminId =
        FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final name = (user['display_name'] as String?) ??
        (user['first_name'] as String?) ??
        'User';

    try {
      await FirestoreService.instance.rejectUser(
        user['uid'] as String,
        adminId,
        reason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name has been rejected.'),
            backgroundColor: const Color(0xFF546E7A),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    }
  }

  // ── View Details ──────────────────────────────────────────────────────────
  void _showDetails(
      BuildContext context, Map<String, dynamic> user) {
    final name = (user['display_name'] as String?) ??
        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
            .trim();
    final email = (user['email'] as String?) ?? '—';
    final phone = (user['phone'] as String?) ?? '—';
    final role = (user['role'] as String?) ?? '—';
    final createdAt = user['created_at'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              'Registration Details',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2B45),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _DetailRow(icon: Icons.person_outline, label: 'Name', value: name),
            const SizedBox(height: 10),
            _DetailRow(icon: Icons.email_outlined, label: 'Email', value: email),
            const SizedBox(height: 10),
            _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: role[0].toUpperCase() + role.substring(1),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Registered',
                value: _formatTimestamp(createdAt),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    try {
      final dt = ts.toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APPROVAL CARD
// ═══════════════════════════════════════════════════════════════════════════

class _ApprovalCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewDetails;

  const _ApprovalCard({
    required this.user,
    required this.onApprove,
    required this.onReject,
    required this.onViewDetails,
  });

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  bool _checkingDuplicate = true;
  bool _isDuplicate = false;

  @override
  void initState() {
    super.initState();
    _checkDuplicate();
  }

  Future<void> _checkDuplicate() async {
    final email =
        (widget.user['email'] as String?) ?? '';
    final phone = widget.user['phone'] as String?;

    try {
      final matches =
      await FirestoreService.instance.checkDuplicateUser(
        email: email,
        phone: phone,
      );
      if (mounted) {
        setState(() {
          _isDuplicate = matches.isNotEmpty;
          _checkingDuplicate = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingDuplicate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = (user['display_name'] as String?) ??
        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
            .trim();
    final email = (user['email'] as String?) ?? '—';
    final phone = (user['phone'] as String?) ?? '—';
    final role =
    ((user['role'] as String?) ?? 'citizen').toLowerCase();
    final createdAt = user['created_at'];

    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDuplicate
              ? const Color(0xFFFFCDD2)
              : Colors.transparent,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Duplicate warning banner ─────────────────────────────────────
          if (_isDuplicate)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                borderRadius:
                BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB71C1C),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Possible duplicate — matches an existing account',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── User info ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                  _roleColor(role).withValues(alpha: 0.12),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'No name',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A2B45),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _RoleBadge(role: role),
                          const SizedBox(width: 8),
                          if (createdAt != null)
                            Text(
                              _timeAgo(createdAt),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF90A4AE),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Reject',
                    icon: Icons.close,
                    color: const Color(0xFFD7263D),
                    onTap: widget.onReject,
                    hasBorderRight: true,
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    label: 'Details',
                    icon: Icons.visibility_outlined,
                    color: const Color(0xFF1565C0),
                    onTap: widget.onViewDetails,
                    hasBorderRight: true,
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    label: 'Approve',
                    icon: Icons.check,
                    color: const Color(0xFF2E7D32),
                    onTap: widget.onApprove,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'rescuer':
        return const Color(0xFF2E7D32);
      case 'moderator':
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF0D47A1);
    }
  }

  String _timeAgo(dynamic ts) {
    try {
      final dt = ts.toDate() as DateTime;
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      return '${diff.inMinutes}m ago';
    } catch (_) {
      return '';
    }
  }
}

// ── Action button ──────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool hasBorderRight;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.hasBorderRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: hasBorderRight
              ? const Border(
              right: BorderSide(color: Color(0xFFF0F0F0)))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
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
      ),
    );
  }
}

// ── Role badge ─────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    switch (role) {
      case 'rescuer':
        bg = const Color(0xFFE8F5E9);
        text = const Color(0xFF1B5E20);
        break;
      case 'moderator':
        bg = const Color(0xFFF3E5F5);
        text = const Color(0xFF6A1B9A);
        break;
      default:
        bg = const Color(0xFFE3F2FD);
        text = const Color(0xFF0D47A1);
    }
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

// ── Detail row ─────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF546E7A)),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF546E7A),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A2B45),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyApprovals extends StatelessWidget {
  const _EmptyApprovals();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(
                Icons.how_to_reg_outlined,
                color: Color(0xFF2E7D32),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2B45),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No pending registrations to review.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF546E7A),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SKELETON LOADER
// ═══════════════════════════════════════════════════════════════════════════

class _ApprovalSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sh(130, 13),
                  const SizedBox(height: 6),
                  _sh(180, 11),
                  const SizedBox(height: 4),
                  _sh(100, 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sh(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}