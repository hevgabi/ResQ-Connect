import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';

// ── Entry screens ─────────────────────────────────────────────────────────────
import 'screens/entry/splash_screen.dart';
import 'screens/entry/login_screen.dart';
import 'screens/entry/otp_verification_screen.dart';
import 'screens/entry/register_screen.dart';
import 'screens/entry/google_complete_profile_screen.dart';

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
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
        },
      ),
    );
  }
}

/// Listens to [AuthProvider] and routes the user to the correct screen.
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

        // ── Account disabled / rejected ───────────────────────────────────────
        if (auth.isAccountDisabled) {
          return const _DisabledAccountScreen();
        }

        // ── Unverified — OTP not yet confirmed ───────────────────────────────
        if (auth.isUnverified) {
          return _UnverifiedScreen(email: auth.unverifiedEmail ?? '');
        }

        // ── Not authenticated ────────────────────────────────────────────────
        if (auth.user == null) {
          return const LoginScreen();
        }

        // ── Authenticated but pending admin approval ──────────────────────────
        if (auth.isPending) {
          return const _PendingApprovalScreen();
        }

        // ── Google user authenticated but no Firestore doc yet ───────────────
        if (auth.isNeedsProfileCompletion && auth.user != null) {
          return GoogleCompleteProfileScreen(googleUser: auth.user!);
        }

        // ── Authenticated — strict role-based routing ────────────────────────
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
            return const _RoleResolvingScreen();
        }
      },
    );
  }
}

// =============================================================================
// PENDING APPROVAL SCREEN
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Unverified Screen — shown when approval_status == 'unverified'
// ─────────────────────────────────────────────────────────────────────────────

class _UnverifiedScreen extends StatelessWidget {
  final String email;
  const _UnverifiedScreen({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFF0D47A1),
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Email Not Verified',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please verify your email address to continue.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF546E7A),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtpVerificationScreen(
                          email: email,
                          purpose: OtpPurpose.registration,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Verify Email',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(color: Color(0xFF546E7A), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingApprovalScreen extends StatelessWidget {
  const _PendingApprovalScreen();

  static const _primaryBlue = Color(0xFF0D47A1);
  static const _warningOrange = Color(0xFFFF6B00);
  static const _successGreen = Color(0xFF1FAA59);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _warningOrange.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_empty_rounded,
                  color: _warningOrange,
                  size: 50,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Account Pending Approval',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account is currently under review by our administrators.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF546E7A),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Timeline card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _TimelineStep(
                      icon: Icons.check_circle,
                      iconColor: _successGreen,
                      title: 'Registration Complete',
                      subtitle: 'Your account has been created',
                      isDone: true,
                    ),
                    _TimelineDivider(isDone: true),
                    _TimelineStep(
                      icon: Icons.mark_email_read_outlined,
                      iconColor: _successGreen,
                      title: 'Email Verified',
                      subtitle: 'Your email has been confirmed',
                      isDone: true,
                    ),
                    _TimelineDivider(isDone: false),
                    _TimelineStep(
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: _warningOrange,
                      title: 'Admin Review',
                      subtitle: 'Estimated: 1–3 business days',
                      isDone: false,
                      isActive: true,
                    ),
                    _TimelineDivider(isDone: false),
                    _TimelineStep(
                      icon: Icons.login_outlined,
                      iconColor: const Color(0xFF90A4AE),
                      title: 'Account Activated',
                      subtitle: 'You can start using ResQConnect',
                      isDone: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _primaryBlue.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _primaryBlue.withAlpha(40)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      color: _primaryBlue,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You will receive an email once your account is approved.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryBlue,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => context.read<AuthProvider>().logout(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF546E7A),
                    side: const BorderSide(
                      color: Color(0xFFCFD8DC),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDone;
  final bool isActive;

  const _TimelineStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDone,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = isDone || isActive;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(active ? 30 : 15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: active ? iconColor : const Color(0xFFB0BEC5),
            size: 18,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? const Color(0xFF263238)
                      : const Color(0xFFB0BEC5),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? const Color(0xFF546E7A)
                      : const Color(0xFFCFD8DC),
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B00).withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'In Progress',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6B00),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelineDivider extends StatelessWidget {
  final bool isDone;
  const _TimelineDivider({required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Container(
        width: 2,
        height: 20,
        color: isDone
            ? const Color(0xFF1FAA59).withAlpha(80)
            : const Color(0xFFCFD8DC),
      ),
    );
  }
}

// =============================================================================
// ROLE RESOLVING SCREEN
// =============================================================================

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
      debugPrint('RootRouter: max retries reached, forcing logout');
      await context.read<AuthProvider>().logout();
      return;
    }
    setState(() => _retryCount++);
    await context.read<AuthProvider>().refreshRole();

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

// =============================================================================
// DISABLED ACCOUNT SCREEN
// =============================================================================

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
