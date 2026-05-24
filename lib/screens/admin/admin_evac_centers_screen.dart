import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/evac_center_model.dart';
import '../../services/firestore_service.dart';

class AdminEvacCentersScreen extends StatefulWidget {
  const AdminEvacCentersScreen({super.key});

  @override
  State<AdminEvacCentersScreen> createState() =>
      _AdminEvacCentersScreenState();
}

class _AdminEvacCentersScreenState
    extends State<AdminEvacCentersScreen> {
  String _statusFilter = 'all';

  static const _statusFilters = [
    ('all', 'All'),
    ('open', 'Open'),
    ('full', 'Full'),
    ('closed', 'Closed'),
  ];

  List<EvacCenterModel> _applyFilter(List<EvacCenterModel> centers) {
    if (_statusFilter == 'all') return centers;
    return centers
        .where((c) => c.status == _statusFilter)
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
        title: const Text(
          'Evac Centers',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      // ── FAB — Add new center ─────────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0D47A1),
        onPressed: () => _showAddCenterSheet(context),
        child: const Icon(Icons.add, color: Colors.white),
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

          // ── Centers list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<EvacCenterModel>>(
              stream:
              FirestoreService.instance.evacCentersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return _EvacCenterSkeleton();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading centers: ${snapshot.error}',
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
                        'No evacuation centers found.\nTap + to add one.',
                        style: TextStyle(color: Color(0xFF546E7A)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final filtered = _applyFilter(snapshot.data!);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No centers match the current filter.',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _EvacCenterCard(
                      center: filtered[index],
                      onArchive: () =>
                          _confirmArchive(context, filtered[index]),
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

  // ── Add Center Bottom Sheet ──────────────────────────────────────────────
  void _showAddCenterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddEvacCenterForm(),
    );
  }

  // ── Archive Confirmation ─────────────────────────────────────────────────
  void _confirmArchive(BuildContext context, EvacCenterModel center) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Archive Center',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Archive "${center.name}"?\n\nIt will be hidden from the list but data will be preserved.',
          style: const TextStyle(color: Color(0xFF546E7A)),
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
              try {
                await FirestoreService.instance
                    .archiveEvacCenter(center.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${center.name}" archived.'),
                      backgroundColor: const Color(0xFF546E7A),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Archive failed: $e'),
                      backgroundColor: const Color(0xFFD7263D),
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF546E7A),
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVAC CENTER CARD
// ═══════════════════════════════════════════════════════════════════════════

class _EvacCenterCard extends StatelessWidget {
  final EvacCenterModel center;
  final VoidCallback onArchive;

  const _EvacCenterCard({
    required this.center,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final occupancyPct = center.occupancyRate;
    Color occColor;
    if (occupancyPct < 0.7) {
      occColor = const Color(0xFF43A047);
    } else if (occupancyPct < 0.9) {
      occColor = const Color(0xFFFB8C00);
    } else {
      occColor = const Color(0xFFE53935);
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
          // ── Top row: name + 3-dot menu ───────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  center.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B45),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: Color(0xFF546E7A),
                  size: 20,
                ),
                onSelected: (value) {
                  if (value == 'archive') onArchive();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined,
                            size: 18, color: Color(0xFF546E7A)),
                        SizedBox(width: 8),
                        Text('Archive'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Address ──────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 13, color: Color(0xFF90A4AE)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  center.address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF546E7A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Capacity row ─────────────────────────────────────────────────
          Row(
            children: [
              _CapStat(
                label: 'Total',
                value: center.capacity.toString(),
                color: const Color(0xFF546E7A),
              ),
              const SizedBox(width: 16),
              _CapStat(
                label: 'Occupied',
                value: center.currentOccupancy.toString(),
                color: occColor,
              ),
              const SizedBox(width: 16),
              _CapStat(
                label: 'Available',
                value: center.availableSlots.toString(),
                color: const Color(0xFF0D47A1),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Occupancy bar ─────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: occupancyPct,
              minHeight: 6,
              backgroundColor: const Color(0xFFECEFF1),
              valueColor: AlwaysStoppedAnimation<Color>(occColor),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(occupancyPct * 100).toStringAsFixed(0)}% occupied',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF90A4AE),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Status toggle ─────────────────────────────────────────────────
          Row(
            children: [
              const Text(
                'Status:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF546E7A),
                ),
              ),
              const SizedBox(width: 12),
              _StatusToggle(center: center),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Capacity stat widget ───────────────────────────────────────────────────

class _CapStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CapStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF90A4AE),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATUS TOGGLE
// ═══════════════════════════════════════════════════════════════════════════

class _StatusToggle extends StatefulWidget {
  final EvacCenterModel center;
  const _StatusToggle({required this.center});

  @override
  State<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends State<_StatusToggle> {
  bool _updating = false;

  static const _statuses = ['open', 'full', 'closed'];

  static const _labels = {
    'open': 'Open',
    'full': 'Full',
    'closed': 'Closed',
  };

  static const _colors = {
    'open': Color(0xFF2E7D32),
    'full': Color(0xFFE65100),
    'closed': Color(0xFFB71C1C),
  };

  static const _bgColors = {
    'open': Color(0xFFE8F5E9),
    'full': Color(0xFFFFF3E0),
    'closed': Color(0xFFFFEBEE),
  };

  Future<void> _onStatusChanged(String newStatus) async {
    if (_updating || newStatus == widget.center.status) return;
    setState(() => _updating = true);
    try {
      await FirestoreService.instance
          .updateEvacCenterStatus(widget.center.id, newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updating) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF0D47A1),
        ),
      );
    }

    return Row(
      children: _statuses.map((s) {
        final isActive = widget.center.status == s;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => _onStatusChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isActive
                    ? _bgColors[s]
                    : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? (_colors[s] ?? Colors.grey)
                      .withValues(alpha: 0.5)
                      : Colors.grey.shade300,
                ),
              ),
              child: Text(
                _labels[s] ?? s,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isActive
                      ? _colors[s]
                      : const Color(0xFF90A4AE),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ADD EVAC CENTER FORM
// ═══════════════════════════════════════════════════════════════════════════

class _AddEvacCenterForm extends StatefulWidget {
  const _AddEvacCenterForm();

  @override
  State<_AddEvacCenterForm> createState() => _AddEvacCenterFormState();
}

class _AddEvacCenterFormState extends State<_AddEvacCenterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  String _initialStatus = 'open';
  final List<String> _selectedFacilities = [];
  bool _submitting = false;

  static const _allFacilities = [
    'Water',
    'Food',
    'Medical',
    'Shelter',
    'Power',
    'Sanitation',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _capacityCtrl.dispose();
    _contactCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      await FirestoreService.instance.addEvacCenter({
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'capacity': int.parse(_capacityCtrl.text.trim()),
        'contact_number': _contactCtrl.text.trim(),
        'latitude': double.tryParse(_latCtrl.text.trim()) ?? 0.0,
        'longitude': double.tryParse(_lngCtrl.text.trim()) ?? 0.0,
        'status': _initialStatus,
        'facilities': _selectedFacilities
            .map((f) => f.toLowerCase())
            .toList(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evacuation center added successfully.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add center: $e'),
            backgroundColor: const Color(0xFFD7263D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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

              const Text(
                'Add Evacuation Center',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2B45),
                ),
              ),
              const SizedBox(height: 20),

              // Name
              _FormField(
                controller: _nameCtrl,
                label: 'Center Name *',
                hint: 'e.g. Barangay Hall Evacuation Center',
                validator: (v) =>
                (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null,
              ),
              const SizedBox(height: 14),

              // Address
              _FormField(
                controller: _addressCtrl,
                label: 'Address *',
                hint: 'Full address',
                validator: (v) =>
                (v == null || v.trim().isEmpty)
                    ? 'Address is required'
                    : null,
              ),
              const SizedBox(height: 14),

              // Capacity
              _FormField(
                controller: _capacityCtrl,
                label: 'Total Capacity *',
                hint: 'e.g. 200',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Capacity is required';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Contact
              _FormField(
                controller: _contactCtrl,
                label: 'Contact Number',
                hint: 'e.g. +63 912 345 6789',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // Lat / Lng
              Row(
                children: [
                  Expanded(
                    child: _FormField(
                      controller: _latCtrl,
                      label: 'Latitude *',
                      hint: 'e.g. 14.6590',
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormField(
                      controller: _lngCtrl,
                      label: 'Longitude *',
                      hint: 'e.g. 121.0890',
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Facilities
              const Text(
                'Facilities',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF546E7A),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _allFacilities.map((f) {
                  final selected =
                  _selectedFacilities.contains(f);
                  return FilterChip(
                    label: Text(f),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      if (selected) {
                        _selectedFacilities.remove(f);
                      } else {
                        _selectedFacilities.add(f);
                      }
                    }),
                    selectedColor: const Color(0xFF0D47A1)
                        .withValues(alpha: 0.12),
                    checkmarkColor: const Color(0xFF0D47A1),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? const Color(0xFF0D47A1)
                          : const Color(0xFF546E7A),
                    ),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF0D47A1)
                          : Colors.grey.shade300,
                    ),
                    backgroundColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Initial status
              const Text(
                'Initial Status',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF546E7A),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: ['open', 'closed'].map((s) {
                  final isSelected = _initialStatus == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                          s[0].toUpperCase() + s.substring(1)),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _initialStatus = s),
                      selectedColor: const Color(0xFF0D47A1)
                          .withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? const Color(0xFF0D47A1)
                            : const Color(0xFF546E7A),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
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
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Add Center',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
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

// ── Form field helper ──────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFF546E7A),
        ),
        hintStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFFB0BEC5),
        ),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0xFF0D47A1),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7263D)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SKELETON LOADER
// ═══════════════════════════════════════════════════════════════════════════

class _EvacCenterSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sh(160, 15),
            const SizedBox(height: 8),
            _sh(220, 12),
            const SizedBox(height: 14),
            Row(children: [
              _sh(50, 30),
              const SizedBox(width: 16),
              _sh(50, 30),
              const SizedBox(width: 16),
              _sh(50, 30),
            ]),
            const SizedBox(height: 10),
            _sh(double.infinity, 6),
            const SizedBox(height: 14),
            _sh(200, 28),
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