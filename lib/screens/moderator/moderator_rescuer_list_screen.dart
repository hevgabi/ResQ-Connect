import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/moderator_bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';

class ModeratorRescuerListScreen extends StatefulWidget {
  const ModeratorRescuerListScreen({super.key});

  @override
  State<ModeratorRescuerListScreen> createState() =>
      _ModeratorRescuerListScreenState();
}

class _ModeratorRescuerListScreenState
    extends State<ModeratorRescuerListScreen> {
  String _searchQuery = '';
  String _filterDuty = 'all'; // all | on_duty | off_duty

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        title: const Text(
          'All Rescuers',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        automaticallyImplyLeading: false,
        elevation: 2,
      ),
      body: Column(
        children: [
          // ── Search + Filter Bar ───────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by name...',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF90A4AE),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF90A4AE),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Color(0xFF90A4AE),
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Duty filter
                Row(
                  children: [
                    _DutyChip(
                      label: 'All',
                      selected: _filterDuty == 'all',
                      onTap: () => setState(() => _filterDuty = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _DutyChip(
                      label: '🟢 On Duty',
                      selected: _filterDuty == 'on_duty',
                      selectedColor: const Color(0xFF1FAA59),
                      onTap: () => setState(() => _filterDuty = 'on_duty'),
                    ),
                    const SizedBox(width: 8),
                    _DutyChip(
                      label: '⚪ Off Duty',
                      selected: _filterDuty == 'off_duty',
                      selectedColor: const Color(0xFF546E7A),
                      onTap: () => setState(() => _filterDuty = 'off_duty'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Rescuer List ──────────────────────────────────────────────
          Expanded(child: _buildRescuerList()),
        ],
      ),
      bottomNavigationBar: const ModeratorBottomNav(currentIndex: 3),
    );
  }

  Widget _buildRescuerList() {
    // Fetch from 'rescuers' collection — moderators have read access here
    // Duty filter applied via simple single-field query (no composite index needed)
    Stream<QuerySnapshot> stream;

    if (_filterDuty == 'on_duty') {
      stream = FirebaseFirestore.instance
          .collection('rescuers')
          .where('is_on_duty', isEqualTo: true)
          .snapshots();
    } else if (_filterDuty == 'off_duty') {
      stream = FirebaseFirestore.instance
          .collection('rescuers')
          .where('is_on_duty', isEqualTo: false)
          .snapshots();
    } else {
      stream = FirebaseFirestore.instance.collection('rescuers').snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: snapshot.error.toString());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.people_outline,
            iconColor: Color(0xFF546E7A),
            title: 'No Rescuers Found',
            subtitle: 'No registered rescuers in the system.',
          );
        }

        // Apply search filter
        final filtered = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (_searchQuery.isNotEmpty) {
            final firstName = (data['first_name'] as String? ?? '')
                .toLowerCase();
            final lastName = (data['last_name'] as String? ?? '').toLowerCase();
            final fullName = '$firstName $lastName';
            if (!fullName.contains(_searchQuery.toLowerCase())) return false;
          }
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            iconColor: Color(0xFF546E7A),
            title: 'No Results',
            subtitle: 'No rescuers match your search.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final data = doc.data() as Map<String, dynamic>;
            return _RescuerCard(
              uid: doc.id,
              rescuerData: data,
              dutyFilter: _filterDuty,
            );
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _shimmer(120, 13),
                const SizedBox(height: 6),
                _shimmer(80, 11),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmer(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

// ---------------------------------------------------------------------------
// Rescuer Card
// ---------------------------------------------------------------------------

class _RescuerCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> rescuerData;
  final String dutyFilter;

  const _RescuerCard({
    required this.uid,
    required this.rescuerData,
    required this.dutyFilter,
  });

  @override
  State<_RescuerCard> createState() => _RescuerCardState();
}

class _RescuerCardState extends State<_RescuerCard> {
  bool? _isOnDuty;
  String _agencyName = '';
  int _activeMissions = 0;

  @override
  void initState() {
    super.initState();
    _loadRescuerData();
  }

  Future<void> _loadRescuerData() async {
    try {
      // Duty/agency already available in rescuerData from rescuers collection
      final rData = widget.rescuerData;
      _isOnDuty = rData['is_on_duty'] as bool? ?? false;
      _agencyName = rData['agency_name'] as String? ?? '';

      final missionsSnap = await FirebaseFirestore.instance
          .collection('missions')
          .where('rescuer_id', isEqualTo: widget.uid)
          .where('status', isEqualTo: 'active')
          .count()
          .get();

      if (mounted) {
        setState(() {
          _activeMissions = missionsSnap.count ?? 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.rescuerData;
    final firstName = data['first_name'] as String? ?? '';
    final lastName = data['last_name'] as String? ?? '';
    final fullName = '${firstName} ${lastName}'.trim();
    final email = data['email'] as String? ?? '';
    final initials = fullName.isNotEmpty
        ? (firstName.isNotEmpty && lastName.isNotEmpty
              ? '${firstName[0]}${lastName[0]}'
              : fullName[0])
        : 'R';

    // Apply duty filter
    if (widget.dutyFilter == 'on_duty' && _isOnDuty == false) {
      return const SizedBox.shrink();
    }
    if (widget.dutyFilter == 'off_duty' && _isOnDuty == true) {
      return const SizedBox.shrink();
    }

    final dutyColor = _isOnDuty == true
        ? const Color(0xFF1FAA59)
        : const Color(0xFF90A4AE);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Duty indicator dot
              if (_isOnDuty != null)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: dutyColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isNotEmpty ? fullName : 'Unnamed Rescuer',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A2B45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _agencyName.isNotEmpty ? _agencyName : email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF90A4AE),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Right side info
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Duty status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: dutyColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isOnDuty == null
                      ? '...'
                      : (_isOnDuty! ? 'ON DUTY' : 'OFF DUTY'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: dutyColor,
                  ),
                ),
              ),
              if (_activeMissions > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.directions_run,
                      size: 12,
                      color: Color(0xFFFF6B00),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$_activeMissions active',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Duty Filter Chip
// ---------------------------------------------------------------------------

class _DutyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _DutyChip({
    required this.label,
    required this.selected,
    this.selectedColor = const Color(0xFF0D47A1),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withAlpha(20)
              : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? selectedColor : const Color(0xFFDDE2E8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? selectedColor : const Color(0xFF546E7A),
          ),
        ),
      ),
    );
  }
}
