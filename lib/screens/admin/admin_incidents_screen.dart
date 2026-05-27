import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';

class AdminIncidentsScreen extends StatefulWidget {
  const AdminIncidentsScreen({super.key});

  @override
  State<AdminIncidentsScreen> createState() => _AdminIncidentsScreenState();
}

class _AdminIncidentsScreenState extends State<AdminIncidentsScreen> {
  String _statusFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  static const _filters = [
    ('all', 'All'),
    ('open', 'Open'),
    ('assigned', 'Assigned'),
    ('resolved', 'Resolved'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // FIX: Removed the combined where+orderBy that caused the composite index
  // error. Now we order by created_at always, and apply status filter only
  // when needed — with where() BEFORE orderBy() to satisfy Firestore rules.
  // For 'all', we skip the where() entirely so no composite index is needed.
  Stream<QuerySnapshot> _buildStream() {
    if (_statusFilter == 'all') {
      return FirebaseFirestore.instance
          .collection('sos_requests')
          .orderBy('created_at', descending: true)
          .snapshots();
    }
    // where() first, then orderBy() — requires a composite index in Firebase
    // Console for (status ASC, created_at DESC) — but this is the correct
    // Firestore pattern. Index link will appear in the error log if missing.
    return FirebaseFirestore.instance
        .collection('sos_requests')
        .where('status', isEqualTo: _statusFilter)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
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
            hintText: 'Search by type or location...',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: (v) =>
              setState(() => _searchQuery = v.toLowerCase()),
        )
            : const Text(
          'Incidents',
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
          // ── Filter chips ────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final isSelected = _statusFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.$2),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _statusFilter = f.$1),
                      selectedColor:
                      AppTheme.primaryBlue.withValues(alpha: 0.15),
                      checkmarkColor: AppTheme.primaryBlue,
                      labelStyle: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.primaryBlue
                            : AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.primaryBlue
                            : Colors.grey.shade300,
                      ),
                      backgroundColor: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Composite index hint banner ─────────────────────────────────
          if (_statusFilter != 'all')
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFFFFF8E1),
              child: const Text(
                'Tip: If you see an index error, tap the link in your debug console to create the Firestore index.',
                style: TextStyle(fontSize: 10, color: Color(0xFFE65100)),
              ),
            ),

          // ── Incident list ───────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _IncidentListSkeleton();
                }
                if (snapshot.hasError) {
                  final errStr = snapshot.error.toString();
                  // Show a helpful message if it's the index error
                  if (errStr.contains('index') ||
                      errStr.contains('FAILED_PRECONDITION')) {
                    return _IndexErrorWidget(error: errStr);
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error: $errStr',
                        style: const TextStyle(
                            color: AppTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.event_busy,
                    iconColor: AppTheme.textSecondary,
                    title: 'No Incidents Found',
                    subtitle: 'No incidents match the current filter.',
                  );
                }

                var docs = snapshot.data!.docs;

                // Client-side search
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final type =
                    ((data['type'] as String?) ?? '').toLowerCase();
                    final lat =
                        (data['latitude'] as double?)?.toString() ?? '';
                    final lng =
                        (data['longitude'] as double?)?.toString() ?? '';
                    return type.contains(_searchQuery) ||
                        lat.contains(_searchQuery) ||
                        lng.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    iconColor: AppTheme.textSecondary,
                    title: 'No Results',
                    subtitle: 'Try a different search term.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _IncidentCard(sosId: doc.id, data: data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Index error helper widget ──────────────────────────────────────────────

class _IndexErrorWidget extends StatelessWidget {
  final String error;
  const _IndexErrorWidget({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE65100), size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'Firestore Index Required',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF1A2B45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This filter requires a composite index.\n\n'
                        '1. Open your Android Studio debug console\n'
                        '2. Find the Firebase error message\n'
                        '3. Tap the link to auto-create the index\n'
                        '4. Wait ~1 minute then try again',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INCIDENT CARD
// ═══════════════════════════════════════════════════════════════════════════

class _IncidentCard extends StatefulWidget {
  final String sosId;
  final Map<String, dynamic> data;
  const _IncidentCard({required this.sosId, required this.data});

  @override
  State<_IncidentCard> createState() => _IncidentCardState();
}

class _IncidentCardState extends State<_IncidentCard> {
  String _citizenName = 'Loading...';
  String _rescuerName = '';
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    final data = widget.data;
    final citizenId = data['citizen_id'] as String?;
    final rescuerId = data['assigned_rescuer_id'] as String?;

    try {
      String citizenName = 'Unknown';
      String rescuerName = '';

      if (citizenId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(citizenId)
            .get();
        citizenName =
            (doc.data()?['display_name'] as String?) ?? 'Unknown';
      }

      if (rescuerId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(rescuerId)
            .get();
        rescuerName =
            (doc.data()?['display_name'] as String?) ?? 'Unknown Rescuer';
      }

      if (mounted) {
        setState(() {
          _citizenName = citizenName;
          _rescuerName = rescuerName;
          _loadingNames = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _citizenName = 'Unknown';
          _loadingNames = false;
        });
      }
    }
  }

  Future<void> _showReassignDialog() async {
    QuerySnapshot rescuersSnap;
    try {
      rescuersSnap = await FirebaseFirestore.instance
          .collection('rescuers')
          .where('is_on_duty', isEqualTo: true)
          .get();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rescuers: $e')),
        );
      }
      return;
    }

    if (rescuersSnap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No on-duty rescuers available.')),
        );
      }
      return;
    }

    String? selectedRescuerId;
    String? selectedRescuerName;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Reassign Rescuer',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select an on-duty rescuer:',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rescuersSnap.docs.length,
                    itemBuilder: (_, i) {
                      final rDoc = rescuersSnap.docs[i];
                      final rData =
                      rDoc.data() as Map<String, dynamic>;
                      final name =
                          (rData['display_name'] as String?) ??
                              'Rescuer ${i + 1}';
                      final activeMissions =
                          (rData['active_mission_count'] as num?)
                              ?.toInt() ??
                              0;
                      final isSelected = selectedRescuerId == rDoc.id;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primaryBlue
                              .withValues(alpha: 0.1),
                          child: Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '$activeMissions active mission${activeMissions != 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                            color: AppTheme.successGreen)
                            : null,
                        selected: isSelected,
                        selectedTileColor: AppTheme.primaryBlue
                            .withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        onTap: () => setDialogState(() {
                          selectedRescuerId = rDoc.id;
                          selectedRescuerName = name;
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            FilledButton(
              onPressed: selectedRescuerId == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    ).then((confirmed) async {
      if (confirmed == true &&
          selectedRescuerId != null &&
          selectedRescuerName != null) {
        await _doReassign(selectedRescuerId!, selectedRescuerName!);
      }
    });
  }

  Future<void> _doReassign(
      String newRescuerId, String newRescuerName) async {
    final oldRescuerId =
    widget.data['assigned_rescuer_id'] as String?;
    final batch = FirebaseFirestore.instance.batch();

    final sosRef = FirebaseFirestore.instance
        .collection('sos_requests')
        .doc(widget.sosId);
    batch.update(sosRef, {
      'assigned_rescuer_id': newRescuerId,
      'status': 'assigned',
      'reassigned_at': FieldValue.serverTimestamp(),
    });

    if (oldRescuerId != null && oldRescuerId != newRescuerId) {
      final oldRef = FirebaseFirestore.instance
          .collection('rescuers')
          .doc(oldRescuerId);
      batch.update(
          oldRef, {'active_mission_count': FieldValue.increment(-1)});
    }

    final newRef = FirebaseFirestore.instance
        .collection('rescuers')
        .doc(newRescuerId);
    batch.update(
        newRef, {'active_mission_count': FieldValue.increment(1)});

    try {
      await batch.commit();
      if (mounted) {
        setState(() => _rescuerName = newRescuerName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reassigned to $newRescuerName'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reassign failed: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final type = (data['type'] as String?) ?? 'Unknown';
    final status = (data['status'] as String?) ?? 'open';
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();

    final locationText = (lat != null && lng != null)
        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
        : 'Unknown location';
    final timeText =
    createdAt != null ? timeago.format(createdAt) : 'Unknown';

    Color statusColor;
    String statusLabel;
    Color statusBg;
    switch (status) {
      case 'assigned':
        statusColor = AppTheme.primaryBlue;
        statusBg = const Color(0xFFE3F2FD);
        statusLabel = 'Assigned';
        break;
      case 'resolved':
        statusColor = AppTheme.successGreen;
        statusBg = const Color(0xFFE8F5E9);
        statusLabel = 'Resolved';
        break;
      default:
        statusColor = AppTheme.dangerRed;
        statusBg = const Color(0xFFFFEBEE);
        statusLabel = 'Open';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.person_outline,
            text: _loadingNames ? 'Loading...' : _citizenName,
          ),
          const SizedBox(height: 4),
          _DetailRow(
              icon: Icons.location_on_outlined, text: locationText),
          const SizedBox(height: 4),
          _DetailRow(icon: Icons.access_time, text: timeText),
          if (_rescuerName.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
              icon: Icons.emergency_outlined,
              text: 'Rescuer: $_rescuerName',
              color: AppTheme.primaryBlue,
            ),
          ],
          if (status != 'resolved') ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _showReassignDialog,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Reassign'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  side: const BorderSide(color: AppTheme.primaryBlue),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.text,
    this.color = AppTheme.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child:
          Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}

class _IncidentListSkeleton extends StatelessWidget {
  const _IncidentListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 130,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_sh(120, 14), _sh(60, 22)],
            ),
            _sh(160, 12),
            _sh(130, 12),
            _sh(90, 12),
          ],
        ),
      ),
    );
  }

  static Widget _sh(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}