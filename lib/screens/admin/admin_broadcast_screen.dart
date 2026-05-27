import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  String _alertType = 'general';
  String _targetAudience = 'all';
  String _targetZone = '';
  bool _submitting = false;

  static const _alertTypes = [
    ('general', 'General Info', Icons.info_outline, Color(0xFF1565C0)),
    ('evacuation', 'Evacuation Order', Icons.directions_run,
    Color(0xFFD7263D)),
    ('weather', 'Weather Warning', Icons.thunderstorm_outlined,
    Color(0xFFE65100)),
    ('road', 'Road Closure', Icons.block_outlined, Color(0xFF546E7A)),
  ];

  static const _audiences = [
    ('all', 'All Users', Icons.people_outline),
    ('citizen', 'Citizens Only', Icons.person_outline),
    ('rescuer', 'Rescuers Only', Icons.emergency_outlined),
    ('zone', 'Specific Zone', Icons.map_outlined),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_targetAudience == 'zone' && _targetZone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a zone name.')),
      );
      return;
    }
    setState(() => _submitting = true);

    try {
      final adminId =
          FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      await FirebaseFirestore.instance.collection('alerts').add({
        'title': _titleCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'type': _alertType,
        'target_audience': _targetAudience,
        'target_zone':
        _targetAudience == 'zone' ? _targetZone.trim() : null,
        'created_by': adminId,
        'created_at': FieldValue.serverTimestamp(),
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert broadcast successfully.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedType =
    _alertTypes.firstWhere((t) => t.$1 == _alertType);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Broadcast Alert',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Alert type selector ──────────────────────────────────
              _SectionLabel('Alert Type'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.8,
                children: _alertTypes.map((t) {
                  final isSelected = _alertType == t.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _alertType = t.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? t.$4.withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? t.$4
                              : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(t.$3,
                              size: 18,
                              color: isSelected
                                  ? t.$4
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              t.$2,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? t.$4
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Selected type preview ────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selectedType.$4.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(selectedType.$3,
                        size: 16, color: selectedType.$4),
                    const SizedBox(width: 8),
                    Text(
                      'Selected: ${selectedType.$2}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selectedType.$4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────────────────
              _SectionLabel('Alert Title *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null,
                decoration: const InputDecoration(
                  hintText: 'e.g. Mandatory Evacuation — Barangay Tandang Sora',
                ),
              ),
              const SizedBox(height: 16),

              // ── Message ──────────────────────────────────────────────
              _SectionLabel('Message *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Message is required'
                    : null,
                decoration: const InputDecoration(
                  hintText:
                  'Enter the full alert message that users will see...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              // ── Target audience ──────────────────────────────────────
              _SectionLabel('Target Audience'),
              const SizedBox(height: 10),
              ..._audiences.map((a) {
                final isSelected = _targetAudience == a.$1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _targetAudience = a.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryBlue
                            .withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(a.$3,
                              size: 20,
                              color: isSelected
                                  ? AppTheme.primaryBlue
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 12),
                          Text(
                            a.$2,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppTheme.primaryBlue
                                  : const Color(0xFF1A2B45),
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(Icons.check_circle,
                                color: AppTheme.primaryBlue, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // ── Zone input (conditional) ─────────────────────────────
              if (_targetAudience == 'zone') ...[
                const SizedBox(height: 8),
                TextFormField(
                  onChanged: (v) => _targetZone = v,
                  decoration: const InputDecoration(
                    labelText: 'Zone Name *',
                    hintText: 'e.g. Barangay Commonwealth, QC',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // ── Send button ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _send,
                  icon: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                      _submitting ? 'Sending...' : 'Send Broadcast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dangerRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'This will immediately notify all targeted users.',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A2B45),
      ),
    );
  }
}