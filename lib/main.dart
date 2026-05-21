import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';

// ── Entry screens ─────────────────────────────────────────────────────────────
import 'screens/entry/splash_screen.dart';
import 'screens/entry/login_screen.dart';

// ── Role dashboards ───────────────────────────────────────────────────────────
import 'screens/citizen/citizen_home_screen.dart';
import 'screens/rescuer/mission_queue_screen.dart';
import 'screens/moderator/moderator_report_queue_screen.dart';
import 'screens/admin/admin_overview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ResQConnectApp());
}

class ResQConnectApp extends StatelessWidget {
  const ResQConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'ResQConnect',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const RootRouter(),
      ),
    );
  }
}

/// Listens to [AuthProvider] and routes the user to the correct screen
/// based on their authentication state and Firestore role.
class RootRouter extends StatelessWidget {
  const RootRouter();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // ── Loading / resolving ──────────────────────────────────────────────
        if (auth.isLoading) {
          return const SplashScreen();
        }

        // ── Not authenticated ────────────────────────────────────────────────
        if (auth.user == null) {
          return const LoginScreen();
        }

        // ── Authenticated — route by role ────────────────────────────────────
        return switch (auth.role) {
          'citizen' => const CitizenHomeScreen(),
          'rescuer' => const MissionQueueScreen(),
          'moderator' => const ModeratorReportQueueScreen(),
          'admin' => const AdminOverviewScreen(),

          // Role is null (document not yet written) or unknown value:
          // Stay on splash while retrying, or show a fallback.
          _ => const _RoleResolvingScreen(),
        };
      },
    );
  }
}

/// Shown briefly when the user is authenticated but their role hasn't been
/// resolved from Firestore yet (e.g. the users/{uid} doc is still being
/// written during registration, or an unknown role value was stored).
class _RoleResolvingScreen extends StatefulWidget {
  const _RoleResolvingScreen();

  @override
  State<_RoleResolvingScreen> createState() => _RoleResolvingScreenState();
}

class _RoleResolvingScreenState extends State<_RoleResolvingScreen> {
  @override
  void initState() {
    super.initState();
    // Retry fetching the role once after a short delay.
    Future.delayed(const Duration(seconds: 2), _retry);
  }

  Future<void> _retry() async {
    if (!mounted) return;
    await context.read<AuthProvider>().refreshRole();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.health_and_safety,
                color: AppTheme.primaryBlue,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'ResQConnect',
              style: AppTheme.heading2(color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 8),
            Text(
              'Setting up your account…',
              style: AppTheme.body(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () => context.read<AuthProvider>().logout(),
              child: Text(
                'Sign out',
                style: AppTheme.body(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
