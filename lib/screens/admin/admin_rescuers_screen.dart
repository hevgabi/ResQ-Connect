import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';

class AdminRescuersScreen extends StatefulWidget {
  const AdminRescuersScreen({super.key});

  @override
  State<AdminRescuersScreen> createState() => _AdminRescuersScreenState();
}

class _AdminRescuersScreenState extends State<AdminRescuersScreen> {
  String _statusFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  static const _statusFilters = [
    ('all', 'All'),
    ('on_duty', 'On Duty'),
    ('off_duty', 'Off Duty'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> rescuers) {
    var filtered = rescuers;

    // Status filter
    if (_statusFilter == 'on_duty') {
      filtered =
          filtered.where((r) => r['is_on_duty'] == true).toList();
    } else if (_statusFilter == 'off_duty') {
      filtered =
          filtered.where((r) => r['is_on_duty'] != true).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((r) {
        final name =
        ((r['display_name'] as String?) ?? '').toLowerCase();
        final zone =
        ((r['zone'] as String?) ?? '').toLowerCase();
        final team =
        ((r['team'] as String?) ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            zone.contains(_searchQuery) ||
            team.contains(_searchQuery);
      }).toList();
    }

    return filtered;
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
        title: _showSearch
            ? TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search by name, zone, team...',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: (v) =>
              setState(() => _searchQuery = v.toLowerCase()),
        )
            : const Text(
          'Rescuers',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchQuery = '';
                  _searchCtrl.clear();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ─────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusFilters.map((f) {
                  final isSelected = _statusFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.$2),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _statusFilter = f.$1),
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

          // ── Rescuers list ────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream:
              FirestoreService.instance.allRescuersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return _RescuerListSkeleton();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading rescuers: ${snapshot.error}',
                        style: const TextStyle(
                            color: Color(0xFF546E7A)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No rescuers found.',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                    ),
                  );
                }

                final filtered = _applyFilters(snapshot.data!);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No rescuers match the current filter.',
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
                    return _RescuerCard(
                      rescuer: filtered[index],
                      onTap: () => _showRescuerDetail(
                          context, filtered[index]),
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

  void _showRescuerDetail(
      BuildContext context, Map<String, dynamic> rescuer) {
    final name =
        (rescuer['display_name'] as String?) ?? 'Unknown';
    final email = (rescuer['email'] as String?) ?? '—';
    final phone = (rescuer['phone'] as String?) ?? '—';
    final isOnDuty = rescuer['is_on_duty'] == true;
    final zone = (rescuer['zone'] as String?) ?? '—';
    final team = (rescuer['team'] as String?) ?? '—';
    final activeMissions =
        (rescuer['active_mission_count'] as num?)?.toInt() ?? 0;

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
            // Handle bar
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

            // Header
            Row(
              children: [
                _RescuerAvatar(name: name, isOnDuty: isOnDuty),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2B45),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _StatusBadge(isOnDuty: isOnDuty),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Details
            _DetailRow(
                icon: Icons.email_outlined, label: 'Email', value: email),
            const SizedBox(height: 8),
            _DetailRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: phone),
            const SizedBox(height: 8),
            _DetailRow(
                icon: Icons.map_outlined, label: 'Zone', value: zone),
            const SizedBox(height: 8),
            _DetailRow(
                icon: Icons.group_outlined, label: 'Team', value: team),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.assignment_outlined,
              label: 'Active Missions',
              value: activeMissions.toString(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESCUER CARD
// ═══════════════════════════════════════════════════════════════════════════

class _RescuerCard extends StatelessWidget {
  final Map<String, dynamic> rescuer;
  final VoidCallback onTap;

  const _RescuerCard({
    required this.rescuer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        (rescuer['display_name'] as String?) ?? 'Unknown';
    final isOnDuty = rescuer['is_on_duty'] == true;
    final zone = (rescuer['zone'] as String?) ?? 'No zone';
    final team = (rescuer['team'] as String?) ?? 'No team';
    final activeMissions =
        (rescuer['active_mission_count'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _RescuerAvatar(name: name, isOnDuty: isOnDuty),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2B45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 12,
                        color: Color(0xFF546E7A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        zone,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.group_outlined,
                        size: 12,
                        color: Color(0xFF546E7A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        team,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                    ],
                  ),
                  if (activeMissions > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$activeMissions active mission${activeMissions > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0D47A1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusBadge(isOnDuty: isOnDuty),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFFB0BEC5),
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _RescuerAvatar extends StatelessWidget {
  final String name;
  final bool isOnDuty;

  const _RescuerAvatar({
    required this.name,
    required this.isOnDuty,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
    name.isNotEmpty ? name[0].toUpperCase() : 'R';
    return Stack(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF0D47A1).withValues(alpha: 0.1),
          child: Text(
            initial,
            style: const TextStyle(
              color: Color(0xFF0D47A1),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isOnDuty
                  ? const Color(0xFF43A047)
                  : const Color(0xFFB0BEC5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOnDuty;
  const _StatusBadge({required this.isOnDuty});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOnDuty
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isOnDuty ? 'On Duty' : 'Off Duty',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isOnDuty
              ? const Color(0xFF2E7D32)
              : const Color(0xFF546E7A),
        ),
      ),
    );
  }
}

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
// SKELETON LOADER
// ═══════════════════════════════════════════════════════════════════════════

class _RescuerListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
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
                  _sh(120, 13),
                  const SizedBox(height: 6),
                  _sh(180, 11),
                ],
              ),
            ),
            _sh(60, 22),
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