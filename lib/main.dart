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
        // ── Still resolving auth + role ──────────────────────────────────────
        if (auth.isLoading) {
          return const SplashScreen();
        }

        // ── Account disabled ─────────────────────────────────────────────────
        if (auth.isAccountDisabled) {
          return const _DisabledAccountScreen();
        }

        // ── Not authenticated ────────────────────────────────────────────────
        if (auth.user == null) {
          return const LoginScreen();
        }

        // ── Authenticated — strict role-based routing ────────────────────────
        // Only exact role matches are allowed. Any unknown or null role
        // goes to _RoleResolvingScreen which retries or forces logout.
        switch (auth.role) {
          case 'citizen':
            return const CitizenHomeScreen();
          case 'rescuer':
            return const MissionQueueScreen();
          case 'moderator':
            return const ModeratorReportQueueScreen();
          case 'admin':
            return const AdminOverviewScreen();
          default:
            // Role is null or unrecognized — retry or force logout
            return const _RoleResolvingScreen();
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Resolving Screen
// Shown when user is authenticated but role is null (e.g. mid-registration
// or Firestore read failed). Retries once, then offers sign out.
// ─────────────────────────────────────────────────────────────────────────────

class _RoleResolvingScreen extends StatefulWidget {
  const _RoleResolvingScreen();

  @override
  State<_RoleResolvingScreen> createState() => _RoleResolvingScreenState();
}

class _RoleResolvingScreenState extends State<_RoleResolvingScreen> {
  int _retryCount = 0;
  static const _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    Future.delayed(const Duration(seconds: 2), _retry);
  }

  Future<void> _retry() async {
    if (!mounted) return;
    if (_retryCount >= _maxRetries) {
      // Too many retries — force logout
      debugPrint('RootRouter: max retries reached, forcing logout');
      await context.read<AuthProvider>().logout();
      return;
    }
    setState(() => _retryCount++);
    await context.read<AuthProvider>().refreshRole();

    // If still no role after refresh, schedule another retry
    if (mounted && context.read<AuthProvider>().role == null) {
      _scheduleRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            const SizedBox(height: 8),
            Text(
              'Attempt ${_retryCount + 1} of $_maxRetries',
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

// ─────────────────────────────────────────────────────────────────────────────
// Disabled Account Screen
// Shown when is_active == false in Firestore
// ─────────────────────────────────────────────────────────────────────────────

class _DisabledAccountScreen extends StatelessWidget {
  const _DisabledAccountScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7263D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.block,
                  color: Color(0xFFD7263D),
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Account Disabled',
                style: AppTheme.heading2(color: const Color(0xFFD7263D)),
              ),
              const SizedBox(height: 8),
              Text(
                'Your account has been disabled. Please contact the administrator for assistance.',
                textAlign: TextAlign.center,
                style: AppTheme.body(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD7263D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
