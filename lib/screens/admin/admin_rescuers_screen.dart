import 'package:cloud_firestore/cloud_firestore.dart';
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
    List<Map<String, dynamic>> rescuers,
  ) {
    var filtered = rescuers;
    if (_statusFilter == 'on_duty') {
      filtered = filtered.where((r) => r['is_on_duty'] == true).toList();
    } else if (_statusFilter == 'off_duty') {
      filtered = filtered.where((r) => r['is_on_duty'] != true).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((r) {
        final name = ((r['display_name'] as String?) ?? '').toLowerCase();
        final zone = ((r['zone'] as String?) ?? '').toLowerCase();
        final team = ((r['team'] as String?) ?? '').toLowerCase();
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
          // Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      onSelected: (_) => setState(() => _statusFilter = f.$1),
                      selectedColor: const Color(
                        0xFF0D47A1,
                      ).withValues(alpha: 0.15),
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

          // Rescuers list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService.instance.allRescuersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _RescuerListSkeleton();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading rescuers: ${snapshot.error}',
                        style: const TextStyle(color: Color(0xFF546E7A)),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _RescuerCard(
                      rescuer: filtered[index],
                      onTap: () => _showRescuerDetail(context, filtered[index]),
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

  void _showRescuerDetail(BuildContext context, Map<String, dynamic> rescuer) {
    final rescuerId = (rescuer['id'] as String?) ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _RescuerDetailSheet(rescuer: rescuer, rescuerId: rescuerId),
    );
  }
}

// ── Rescuer detail bottom sheet with reviews tab ──────────────────────────────
class _RescuerDetailSheet extends StatefulWidget {
  final Map<String, dynamic> rescuer;
  final String rescuerId;

  const _RescuerDetailSheet({required this.rescuer, required this.rescuerId});

  @override
  State<_RescuerDetailSheet> createState() => _RescuerDetailSheetState();
}

class _RescuerDetailSheetState extends State<_RescuerDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.rescuer['display_name'] as String?) ?? 'Unknown';
    final isOnDuty = widget.rescuer['is_on_duty'] == true;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle + header (non-scrollable)
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
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
                    // Avg rating pill
                    _AdminRatingPill(rescuerId: widget.rescuerId),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF0D47A1),
                  unselectedLabelColor: const Color(0xFF546E7A),
                  indicatorColor: const Color(0xFF0D47A1),
                  tabs: const [
                    Tab(text: 'Info'),
                    Tab(text: 'Reviews'),
                  ],
                ),
              ],
            ),
          ),

          // Tab content (scrollable)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Info tab
                _InfoTab(rescuer: widget.rescuer, scrollCtrl: scrollCtrl),
                // Reviews tab
                _AdminReviewsTab(
                  rescuerId: widget.rescuerId,
                  scrollCtrl: scrollCtrl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  final Map<String, dynamic> rescuer;
  final ScrollController scrollCtrl;

  const _InfoTab({required this.rescuer, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    final email = (rescuer['email'] as String?) ?? '—';
    final phone = (rescuer['phone'] as String?) ?? '—';
    final zone = (rescuer['zone'] as String?) ?? '—';
    final team = (rescuer['team'] as String?) ?? '—';
    final activeMissions =
        (rescuer['active_mission_count'] as num?)?.toInt() ?? 0;
    final badge = (rescuer['badge_number'] as String?) ?? '—';
    final agency = (rescuer['agency_name'] as String?) ?? '—';

    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        children: [
          _DetailRow(icon: Icons.email_outlined, label: 'Email', value: email),
          const SizedBox(height: 10),
          _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
          const SizedBox(height: 10),
          _DetailRow(icon: Icons.badge_outlined, label: 'Badge', value: badge),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.account_balance_outlined,
            label: 'Agency',
            value: agency,
          ),
          const SizedBox(height: 10),
          _DetailRow(icon: Icons.map_outlined, label: 'Zone', value: zone),
          const SizedBox(height: 10),
          _DetailRow(icon: Icons.group_outlined, label: 'Team', value: team),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.assignment_outlined,
            label: 'Active Missions',
            value: activeMissions.toString(),
          ),
        ],
      ),
    );
  }
}

class _AdminReviewsTab extends StatelessWidget {
  final String rescuerId;
  final ScrollController scrollCtrl;

  const _AdminReviewsTab({required this.rescuerId, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: rescuerId)
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            color: const Color(0xFFF5F7FA),
            child: const Center(
              child: Text(
                'No reviews yet for this rescuer.',
                style: TextStyle(color: Color(0xFF546E7A)),
              ),
            ),
          );
        }

        // Compute overall stats
        final total = docs.fold<int>(
          0,
          (s, d) => s + ((d.data() as Map)['stars'] as int? ?? 0),
        );
        final avg = total / docs.length;
        final starCounts = List.filled(5, 0);
        for (final d in docs) {
          final s = ((d.data() as Map)['stars'] as int? ?? 1) - 1;
          if (s >= 0 && s < 5) starCounts[s]++;
        }

        return Container(
          color: const Color(0xFFF5F7FA),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              // Summary card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Big avg number
                    Column(
                      children: [
                        Text(
                          avg.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2B45),
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < avg.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: const Color(0xFFFFC107),
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${docs.length} review${docs.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF546E7A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    // Star breakdown bars
                    Expanded(
                      child: Column(
                        children: List.generate(5, (i) {
                          final starNum = 5 - i;
                          final count = starCounts[starNum - 1];
                          final pct = docs.isNotEmpty
                              ? count / docs.length
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  '$starNum',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF546E7A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.star_rounded,
                                  size: 11,
                                  color: Color(0xFFFFC107),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 8,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFFFFC107),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF546E7A),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Individual reviews
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final stars = (data['stars'] as int?) ?? 0;
                final comment = (data['comment'] as String?)?.trim() ?? '';
                final ts = data['created_at'] as Timestamp?;
                final date = ts != null ? _formatDate(ts.toDate()) : 'Unknown';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: const Color(0xFFFFC107),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF546E7A),
                            ),
                          ),
                        ],
                      ),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF37474F),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        Text(
                          'No comment left.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Avg rating pill for admin card/header ─────────────────────────────────────
class _AdminRatingPill extends StatelessWidget {
  final String rescuerId;
  const _AdminRatingPill({required this.rescuerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: rescuerId)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'No rating',
              style: TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
            ),
          );
        }
        final docs = snap.data!.docs;
        final total = docs.fold<int>(
          0,
          (s, d) => s + ((d.data() as Map)['stars'] as int? ?? 0),
        );
        final avg = total / docs.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFC107)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFFFFC107),
              ),
              const SizedBox(width: 4),
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF795548),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${docs.length})',
                style: const TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Rescuer card (with rating) ────────────────────────────────────────────────
class _RescuerCard extends StatelessWidget {
  final Map<String, dynamic> rescuer;
  final VoidCallback onTap;

  const _RescuerCard({required this.rescuer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (rescuer['display_name'] as String?) ?? 'Unknown';
    final isOnDuty = rescuer['is_on_duty'] == true;
    final zone = (rescuer['zone'] as String?) ?? 'No zone';
    final team = (rescuer['team'] as String?) ?? 'No team';
    final activeMissions =
        (rescuer['active_mission_count'] as num?)?.toInt() ?? 0;
    final rescuerId = (rescuer['id'] as String?) ?? '';

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
                  const SizedBox(height: 4),
                  // Rating row on card
                  _CardRatingRow(rescuerId: rescuerId),
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

// ── Inline rating row for the list card ──────────────────────────────────────
class _CardRatingRow extends StatelessWidget {
  final String rescuerId;
  const _CardRatingRow({required this.rescuerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescuer_reviews')
          .where('rescuer_id', isEqualTo: rescuerId)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Text(
            'No reviews yet',
            style: TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
          );
        }
        final docs = snap.data!.docs;
        final total = docs.fold<int>(
          0,
          (s, d) => s + ((d.data() as Map)['stars'] as int? ?? 0),
        );
        final avg = total / docs.length;
        return Row(
          children: [
            ...List.generate(
              5,
              (i) => Icon(
                i < avg.round()
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 13,
                color: const Color(0xFFFFC107),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${avg.toStringAsFixed(1)} · ${docs.length} review${docs.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
            ),
          ],
        );
      },
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _RescuerAvatar extends StatelessWidget {
  final String name;
  final bool isOnDuty;

  const _RescuerAvatar({required this.name, required this.isOnDuty});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOnDuty ? const Color(0xFFE8F5E9) : const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isOnDuty ? 'On Duty' : 'Off Duty',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isOnDuty ? const Color(0xFF2E7D32) : const Color(0xFF546E7A),
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
          style: const TextStyle(fontSize: 13, color: Color(0xFF546E7A)),
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
                  const SizedBox(height: 4),
                  _sh(100, 11),
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
