import 'package:flutter/material.dart';

enum UserRole { citizen, rescuer, moderator, admin }

/// Colored badge that displays a user's role.
///
/// Role → Color mapping:
///   citizen   → Blue   (0xFF0D47A1)
///   rescuer   → Green  (0xFF1FAA59)
///   moderator → Purple (0xFF6A1B9A)
///   admin     → Red    (0xFFD7263D)
class RoleBadge extends StatelessWidget {
  final UserRole role;
  final bool compact;
  final double fontSize;

  const RoleBadge({
    super.key,
    required this.role,
    this.compact = false,
    this.fontSize = 11,
  });

  /// Construct from a raw string role (e.g., from Firestore).
  factory RoleBadge.fromString(
    String roleString, {
    bool compact = false,
    double fontSize = 11,
  }) {
    final role = _parseRole(roleString);
    return RoleBadge(role: role, compact: compact, fontSize: fontSize);
  }

  static UserRole _parseRole(String value) {
    switch (value.toLowerCase().trim()) {
      case 'rescuer':
        return UserRole.rescuer;
      case 'moderator':
        return UserRole.moderator;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.citizen;
    }
  }

  _RoleStyle get _style {
    switch (role) {
      case UserRole.citizen:
        return _RoleStyle(
          background: const Color(0xFFE3F2FD),
          border: const Color(0xFF0D47A1),
          text: const Color(0xFF0D47A1),
          label: 'Citizen',
          icon: Icons.person,
        );
      case UserRole.rescuer:
        return _RoleStyle(
          background: const Color(0xFFE8F5E9),
          border: const Color(0xFF1FAA59),
          text: const Color(0xFF1FAA59),
          label: 'Rescuer',
          icon: Icons.medical_services,
        );
      case UserRole.moderator:
        return _RoleStyle(
          background: const Color(0xFFF3E5F5),
          border: const Color(0xFF6A1B9A),
          text: const Color(0xFF6A1B9A),
          label: 'Moderator',
          icon: Icons.shield,
        );
      case UserRole.admin:
        return _RoleStyle(
          background: const Color(0xFFFFEBEE),
          border: const Color(0xFFD7263D),
          text: const Color(0xFFD7263D),
          label: 'Admin',
          icon: Icons.admin_panel_settings,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final iconSize = fontSize + 2;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.border.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.text, size: iconSize),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              style.label,
              style: TextStyle(
                color: style.text,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleStyle {
  final Color background;
  final Color border;
  final Color text;
  final String label;
  final IconData icon;

  const _RoleStyle({
    required this.background,
    required this.border,
    required this.text,
    required this.label,
    required this.icon,
  });
}
