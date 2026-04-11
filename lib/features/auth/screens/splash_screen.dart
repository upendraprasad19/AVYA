import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Full-screen splash with AVYA logo, tagline, and a 3-dot loading animation.
///
/// On mount, runs deferred heavy initialization (Supabase, seed data,
/// OneSignal) so [main] can call [runApp] immediately and show this screen
/// without a black-screen delay. Once init completes (minimum 3s for
/// branding), navigates based on auth state:
///   - Authenticated + onboarded -> /home
///   - Authenticated + not onboarded -> /onboarding
///   - Not authenticated -> /sign-in
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
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

    // Run all deferred init in parallel with a minimum 3s splash duration.
    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    await Future.wait([
      _runDeferredInit().catchError((_) {}), // Never block navigation on init failure
      Future.delayed(const Duration(milliseconds: 3000)),
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

    // Bug #13 — Cold-launch day rollover. Invalidate every "today"-scoped
    // provider before the user lands on home so the first paint can't show
    // yesterday's workout / water count / weight badge / AI insight. The
    // resume-time observer in DayRolloverObserver still uses its gated
    // `_checkAndRollover` path, so this won't double-invalidate when the
    // user backgrounds and resumes within the same day.
    if (mounted) {
      await DayRolloverObserver.instance.runRolloverNow(ref);
    }

    // Refresh AI coach context immediately so the next coach query reflects
    // today's state (covers Bug #6 — "no workout planned today" hallucination
    // when snapshot was last pushed yesterday).
    unawaited(SyncService.instance.pushSnapshot());

    // Trigger background sync check (weekly full sync, cross-channel pull).
    // Fire-and-forget — checkAndSync() has its own try-catch.
    SyncService.instance.checkAndSync();

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

    // Guard: even if the flag is set, verify the profile has real data.
    // A stale Hive can have onboarding_completed=true but only a minimal
    // stub profile ({id, email}) — e.g. after a failed sync or browser
    // storage surviving across rebuilds. Redirect to onboarding in that case.
    if (isOnboarded) {
      final profile = HiveService.instance.userBox.get('profile');
      if (profile is Map) {
        final hasRealData =
            profile['primary_goal'] != null || profile['height_cm'] != null;
        if (!hasRealData) {
          // Clear the stale flag so onboarding can proceed.
          HiveService.instance.configBox.delete('onboarding_completed');
          context.go('/onboarding');
          return;
        }
      }
    }

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full bleed splash image
          FadeTransition(
            opacity: _logoFade,
            child: Image.asset(
              'assets/avya_logo.png',
              fit: BoxFit.cover,
            ),
          ),
          // 3-dot loader pinned to bottom center
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _taglineFade,
              child: Center(child: _buildDotLoader()),
            ),
          ),
        ],
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
                color: AppColors.accent.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
