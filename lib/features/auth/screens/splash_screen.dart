import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Full-screen splash with AVYA logo, tagline, and a 3-dot loading animation.
///
/// On mount, runs deferred heavy initialization (Supabase, seed data,
/// OneSignal) so [main] can call [runApp] immediately and show this screen
/// without a black-screen delay. Once init completes (minimum 1.5s for
/// branding), navigates based on auth state:
///   - Authenticated + onboarded -> /home
///   - Authenticated + not onboarded -> /onboarding
///   - Not authenticated -> /sign-in
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _logoFade;
  late final Animation<double> _taglineFade;
  late final AnimationController _dotController;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoFade = CurvedAnimation(
      parent: _fadeController,
      curve: const Interval(0.0, 0.75, curve: Curves.easeIn),
    );
    _taglineFade = CurvedAnimation(
      parent: _fadeController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeIn),
    );

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fadeController.forward();

    // Run all deferred init in parallel with a minimum 1.5s splash duration.
    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    await Future.wait([
      _runDeferredInit(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    _navigateNext();
  }

  /// Initializes Supabase, seeds first-launch data, and sets up OneSignal.
  /// Safe to call multiple times — each service is idempotent.
  Future<void> _runDeferredInit() async {
    // Supabase must come first — auth state is needed by _navigateNext.
    await SupabaseService.instance.initialize();

    // Seed exercise + food databases on first launch only.
    // compute() keeps JSON parsing off the main thread.
    await SeedService.instance.seedIfNeeded();

    // OneSignal — fire and forget; don't block navigation on OS permission dialog.
    if (!kIsWeb) {
      OneSignal.initialize(AppConstants.oneSignalAppId);
      OneSignal.Notifications.requestPermission(true);
    }
  }

  void _navigateNext() {
    if (!mounted) return;

    final isAuthenticated = SupabaseService.instance.isAuthenticated;

    if (!isAuthenticated) {
      context.go('/sign-in');
      return;
    }

    final isOnboarded = HiveService.instance.configBox
        .get('onboarding_completed', defaultValue: false) as bool;

    if (!isOnboarded) {
      context.go('/onboarding');
      return;
    }

    context.go('/home');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AVYA logo — fade in
            FadeTransition(
              opacity: _logoFade,
              child: Image.asset(
                'assets/avya_logo.png',
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),

            // Tagline — fade in with 200ms delay
            FadeTransition(
              opacity: _taglineFade,
              child: Text(
                'Your AI Fitness Coach',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 3-dot loader
            FadeTransition(
              opacity: _taglineFade,
              child: _buildDotLoader(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotLoader() {
    return AnimatedBuilder(
      animation: _dotController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Stagger each dot by ~167ms (0.167 of 1200ms cycle)
            final phase = (_dotController.value + index * 0.167) % 1.0;
            // Smooth sine pulse: opacity ranges from 0.3 to 1.0
            final opacity =
                0.3 + 0.7 * ((math.sin(2 * math.pi * phase - math.pi / 2) + 1) / 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha((opacity * 255).round()),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
