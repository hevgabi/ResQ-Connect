import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import '../services/firestore_service.dart';

// =============================================================================
// SLIDE-IN ALERT TOAST (broadcast from admin — orange/red)
// Same widget used across Citizen, Rescuer, and Moderator home screens.
// =============================================================================

class _AlertToastBanner extends StatefulWidget {
  final String title;
  final String message;
  final bool isCritical;
  final VoidCallback onDismiss;

  const _AlertToastBanner({
    required this.title,
    required this.message,
    required this.isCritical,
    required this.onDismiss,
  });

  @override
  State<_AlertToastBanner> createState() => _AlertToastBannerState();
}

class _AlertToastBannerState extends State<_AlertToastBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);

    _ctrl.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isCritical
        ? const Color(0xFFD7263D)
        : const Color(0xFFFF6B00);
    final icon = widget.isCritical
        ? Icons.warning_rounded
        : Icons.info_outline_rounded;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF546E7A),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.close, size: 16, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BROADCAST ALERT OVERLAY
//
// Drop this widget anywhere inside a Stack (or wrap your Scaffold body in one).
// It self-manages the Firestore subscription and seen-ID tracking.
//
// Usage:
//   Stack(
//     children: [
//       YourMainContent(),
//       const BroadcastAlertOverlay(topOffset: 12),
//     ],
//   )
// =============================================================================

class BroadcastAlertOverlay extends StatefulWidget {
  /// Distance from the top of the Stack where the toast appears.
  final double topOffset;

  const BroadcastAlertOverlay({super.key, this.topOffset = 12});

  @override
  State<BroadcastAlertOverlay> createState() => _BroadcastAlertOverlayState();
}

class _BroadcastAlertOverlayState extends State<BroadcastAlertOverlay> {
  StreamSubscription<List<AlertModel>>? _sub;
  final Set<String> _seenIds = {};
  final List<AlertModel> _queue = [];
  final ValueNotifier<AlertModel?> _current = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Load persisted seen IDs so old alerts are never re-toasted.
    if (uid != null) {
      final persisted = await FirestoreService.instance.getSeenAlertIds(uid);
      if (!mounted) return;
      _seenIds.addAll(persisted);
    }

    // Prime with whatever is already in Firestore so the first stream
    // emission never fires toasts for existing alerts.
    try {
      final existing = await FirestoreService.instance.alertsStream().first;
      if (!mounted) return;
      for (final a in existing) {
        _seenIds.add(a.id);
      }
    } catch (_) {}

    _sub = FirestoreService.instance.alertsStream().listen((alerts) {
      if (!mounted) return;
      for (final alert in alerts) {
        if (!_seenIds.contains(alert.id)) {
          _seenIds.add(alert.id);
          _queue.add(alert);
        }
      }
      if (_current.value == null && _queue.isNotEmpty) {
        _showNext();
      }
    });
  }

  void _showNext() {
    if (_queue.isEmpty || !mounted) return;
    _current.value = _queue.removeAt(0);
  }

  void _dismiss() {
    if (!mounted) return;
    _current.value = null;
    if (_queue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), _showNext);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topOffset,
      left: 0,
      right: 0,
      child: ClipRect(
        child: ValueListenableBuilder<AlertModel?>(
          valueListenable: _current,
          builder: (_, alert, __) {
            if (alert == null) {
              return const IgnorePointer(child: SizedBox.shrink());
            }
            return _AlertToastBanner(
              title: alert.title,
              message: alert.message,
              isCritical: alert.severity == 'critical',
              onDismiss: _dismiss,
            );
          },
        ),
      ),
    );
  }
}
