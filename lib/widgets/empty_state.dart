import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Color? iconColor;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.iconColor,
    this.iconSize = 72,
  });

  /// Predefined empty states for common use cases
  factory EmptyState.noMissions({VoidCallback? onRefresh}) => EmptyState(
    icon: Icons.assignment_outlined,
    title: 'No Missions Yet',
    subtitle: 'New rescue missions will appear here when assigned.',
    iconColor: const Color(0xFF1FAA59),
    action: onRefresh != null ? _RefreshButton(onPressed: onRefresh) : null,
  );

  factory EmptyState.noReports({VoidCallback? onRefresh}) => EmptyState(
    icon: Icons.report_gmailerrorred_outlined,
    title: 'No Reports Found',
    subtitle: 'Submitted incident reports will show up here for review.',
    iconColor: const Color(0xFFFF6B00),
    action: onRefresh != null ? _RefreshButton(onPressed: onRefresh) : null,
  );

  factory EmptyState.noAlerts() => const EmptyState(
    icon: Icons.notifications_off_outlined,
    title: 'No Alerts',
    subtitle: 'You\'re all clear! Emergency alerts will appear here.',
    iconColor: Color(0xFF0D47A1),
  );

  factory EmptyState.noSosRequests({VoidCallback? onRefresh}) => EmptyState(
    icon: Icons.health_and_safety_outlined,
    title: 'No SOS Requests',
    subtitle: 'Active distress calls from citizens will be shown here.',
    iconColor: const Color(0xFFD7263D),
    action: onRefresh != null ? _RefreshButton(onPressed: onRefresh) : null,
  );

  factory EmptyState.noResults() => const EmptyState(
    icon: Icons.search_off_outlined,
    title: 'No Results',
    subtitle: 'Try adjusting your filters or search query.',
    iconColor: Color(0xFF546E7A),
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (iconColor ?? const Color(0xFF0D47A1)).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: (iconColor ?? const Color(0xFF0D47A1)).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF263238),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF546E7A),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RefreshButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0D47A1),
        side: const BorderSide(color: Color(0xFF0D47A1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    );
  }
}
