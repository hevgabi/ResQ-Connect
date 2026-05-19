import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _slideController;

  static const List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      icon: Icons.campaign_outlined,
      accentColor: Color(0xFFFF6B00),
      title: 'Report Incidents',
      subtitle:
          'Quickly document disasters, flooding, or hazards near you. '
          'Add photos and your location so responders can act fast.',
      backgroundIcon: Icons.campaign,
    ),
    _OnboardingSlide(
      icon: Icons.sos_outlined,
      accentColor: Color(0xFFD7263D),
      title: 'Get Help Fast',
      subtitle:
          'Trigger an SOS with one tap and get matched with the nearest '
          'available rescuer. Track their arrival in real time on the map.',
      backgroundIcon: Icons.sos,
    ),
    _OnboardingSlide(
      icon: Icons.sensors_outlined,
      accentColor: Color(0xFF1FAA59),
      title: 'Stay Informed',
      subtitle:
          'Receive verified community alerts, find evacuation centers, '
          'and follow live updates during emergencies — all in one place.',
      backgroundIcon: Icons.sensors,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _slideController
      ..reset()
      ..forward();
  }

  bool get _isLastPage => _currentPage == _slides.length - 1;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final slide = _slides[_currentPage];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: page counter + skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      '${_currentPage + 1} / ${_slides.length}',
                      key: ValueKey(_currentPage),
                      style: const TextStyle(
                        color: Color(0xFF546E7A),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!_isLastPage)
                    TextButton(
                      onPressed: _finishOnboarding,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: Color(0xFF546E7A),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 60),
                ],
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _slides.length,
                itemBuilder: (context, index) =>
                    _SlideContent(slide: _slides[index], size: size),
              ),
            ),

            // Bottom: dots + button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => _DotIndicator(
                        isActive: i == _currentPage,
                        color: _slides[_currentPage].accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Next / Get Started button
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLastPage
                            ? const Color(0xFF1FAA59)
                            : const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Row(
                          key: ValueKey(_isLastPage),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLastPage ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isLastPage
                                  ? Icons.rocket_launch_outlined
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
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

// ── Individual slide content ─────────────────────────────────────────────────

class _SlideContent extends StatefulWidget {
  final _OnboardingSlide slide;
  final Size size;

  const _SlideContent({required this.slide, required this.size});

  @override
  State<_SlideContent> createState() => _SlideContentState();
}

class _SlideContentState extends State<_SlideContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();

    _iconScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.35, 0.75, curve: Curves.easeIn),
      ),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
          ),
        );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration area
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Opacity(
              opacity: _iconOpacity.value,
              child: Transform.scale(
                scale: _iconScale.value,
                child: _buildIllustration(slide),
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Text content
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Opacity(
              opacity: _textOpacity.value,
              child: SlideTransition(
                position: _textSlide,
                child: Column(
                  children: [
                    Text(
                      slide.title,
                      style: const TextStyle(
                        color: Color(0xFF0D1B2A),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      slide.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF546E7A),
                        fontSize: 15,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustration(_OnboardingSlide slide) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.accentColor.withValues(alpha: 0.08),
            ),
          ),
          // Middle ring
          Container(
            width: 155,
            height: 155,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.accentColor.withValues(alpha: 0.12),
            ),
          ),
          // Inner circle with icon
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.accentColor,
              boxShadow: [
                BoxShadow(
                  color: slide.accentColor.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(slide.icon, size: 52, color: Colors.white),
          ),
          // Background decorative icon (large, faded)
          Positioned(
            right: 10,
            top: 10,
            child: Icon(
              slide.backgroundIcon,
              size: 48,
              color: slide.accentColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot indicator ────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final bool isActive;
  final Color color;

  const _DotIndicator({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? color : const Color(0xFFCFD8DC),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class _OnboardingSlide {
  final IconData icon;
  final IconData backgroundIcon;
  final Color accentColor;
  final String title;
  final String subtitle;

  const _OnboardingSlide({
    required this.icon,
    required this.backgroundIcon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
  });
}
