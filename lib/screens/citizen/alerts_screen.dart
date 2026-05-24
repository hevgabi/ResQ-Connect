import 'package:flutter/material.dart';

import '../../models/alert_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
// Idinagdag na import para sa hamburger menu function at role
import '../settings/hamburger_menu_screen.dart'; // i-adjust path depende sa location

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  static const _blue = Color(0xFF0D47A1);
  static const _red = Color(0xFFD7263D);
  static const _orange = Color(0xFFFF6B00);
  static const _bg = Color(0xFFF5F7FA);
  static const _textSec = Color(0xFF546E7A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Alerts',
          style: TextStyle(
            color: _blue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _blue),
          onPressed: () => Navigator.pop(context),
        ),
        // Dito inilagay ang hinahanap na actions para sa burger menu
        actions: [
          IconButton(
            icon: const Icon(
              Icons.menu,
              color: _blue,
            ), // Pinalitan ko ng _blue para bumagay sa white appBar mo pre, pero pwede mong gawing Colors.white kung gusto mo
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.citizen),
          ),
        ],
      ),
      body: StreamBuilder<List<AlertModel>>(
        stream: FirestoreService.instance.alertsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorBanner(message: snapshot.error.toString());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'No alerts right now',
              subtitle: 'You\'re all caught up!',
            );
          }

          final alerts = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final isCritical = alert.severity == 'critical';
              final borderColor = isCritical ? _red : _orange;
              final iconData = isCritical
                  ? Icons.warning_rounded
                  : Icons.info_outline_rounded;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(color: borderColor, width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(iconData, color: borderColor, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: borderColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alert.message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _textSec,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}
