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
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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

  StreamSubscription<void>? _restoreSub;

  @override
  void initState() {
    super.initState();

    // F5 · When SyncService finishes a restore pass (logs, templates,
    // profile all refreshed from cloud), invalidate the home + train
    // providers so the UI reflects the new data immediately — critical
    // for PRs (recomputed from logs), today's workout, stats grid, etc.
    _restoreSub = SyncService.instance.onRestoreComplete.listen((_) {
      if (!mounted) return;
      ref.invalidate(allExercisePRsProvider);
      ref.invalidate(currentPlanProvider);
      ref.invalidate(workoutStatsProvider);
      ref.invalidate(calendarWeekProvider);
      ref.invalidate(todayWorkoutProvider);
    });

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

    // Sync health data (steps, weight) from Health Connect / HealthKit into
    // Hive BEFORE navigating to home. This ensures the first paint shows
    // today's step count and any weight logged via a health wearable.
    // Non-fatal — health sync failure should never block app launch.
    if (!kIsWeb && HealthSyncService.isEnabled()) {
      try {
        await HealthSyncService.instance.syncToHive();
      } catch (_) {
        // Health sync is best-effort; log but don't block navigation.
      }
    }

    // Refresh AI coach context immediately so the next coach query reflects
    // today's state (covers Bug #6 — "no workout planned today" hallucination
    // when snapshot was last pushed yesterday).
    unawaited(SyncService.instance.pushSnapshot());

    // Trigger background sync check (weekly full sync, cross-channel pull).
    // Fire-and-forget — checkAndSync() has its own try-catch.
    SyncService.instance.checkAndSync();

    // F1 · Refresh subscription state on every app launch so PRO survives
    // logout/login and cross-device sessions without requiring a PRO-feature
    // tap to trigger verifyFromServer().
    unawaited(SubscriptionService.instance.refreshFromSupabase());

    // Audit H9 · PRO auto-generate next Phase on expiry.
    //
    // Free users hit the 3-door PlanExpiredCard on day 29. PRO users
    // should never see that card — if their Phase has run out, silently
    // generate the next one so Home + Train just show fresh workouts.
    // Runs fire-and-forget; the card branch checks `isPhaseExpired()`
    // again at render time so a race here (card flickers for one frame
    // on PRO users) can't happen — the generation writes schedule keys
    // BEFORE we navigate off splash, and PRO's expiry window is caught
    // by this check.
    unawaited(_autoGenerateNextPhaseForPro());

    // Drain any persisted sync-queue ops left over from a previous session
    // (app killed while offline, JWT expired mid-flight, etc.). No-op when
    // sync_reliability_v1 feature flag is off — the queue is empty then.
    unawaited(SyncQueue.instance.drain());

    // OneSignal — fire and forget; don't block navigation on OS permission dialog.
    if (!kIsWeb) {
      OneSignal.initialize(AppConstants.oneSignalAppId);
      OneSignal.Notifications.requestPermission(true);
    }
  }

  /// Audit H9 · If user is PRO and the current Phase has expired,
  /// auto-generate the next Phase (N+1). Reads goal / equipment /
  /// days_per_week / experience / injuries from the Hive profile +
  /// progress maps — same inputs the onboarding flow uses for Phase 1.
  Future<void> _autoGenerateNextPhaseForPro() async {
    try {
      if (!SubscriptionService.instance.isPro()) return;
      if (!WorkoutScheduleService.instance.isPhaseExpired()) return;

      final profile = UserRepository.instance.getProfile() ?? {};
      final progress = UserRepository.instance.getProgress() ?? {};

      final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
      final equipment = (profile['equipment_access'] as String?) ?? 'bodyweight';
      final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
      final experience = (profile['fitness_experience'] as String?) ?? 'intermediate';
      final currentPhase = (progress['current_phase'] as int?) ?? 1;
      final rawInjuries = profile['injuries'];
      final injuries = rawInjuries is List
          ? rawInjuries.map((e) => e.toString()).toList()
          : const <String>[];
      final sessionDuration = (profile['session_duration_minutes'] as num?)?.toInt();

      final generated = await WorkoutScheduleService.instance
          .autoGenerateNextPhaseIfNeeded(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        experienceLevel: experience,
        currentPhase: currentPhase,
        injuries: injuries,
        sessionDuration: sessionDuration,
      );

      if (generated) {
        // Bump user_progress.current_phase + plan_generated_at.
        final updated = Map<String, dynamic>.from(progress);
        updated['current_phase'] = currentPhase + 1;
        updated['current_week'] = 1;
        updated['plan_generated_at'] = DateTime.now().toIso8601String();
        updated['phase_started_at'] = DateTime.now().toIso8601String();
        await UserRepository.instance.saveProgress(updated);
        // Fire-and-forget snapshot push so AI coach sees the new Phase.
        unawaited(SyncService.instance.pushSnapshot());
      }
    } catch (e) {
      debugPrint('[splash._autoGenerateNextPhaseForPro] $e');
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
    _restoreSub?.cancel();
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
