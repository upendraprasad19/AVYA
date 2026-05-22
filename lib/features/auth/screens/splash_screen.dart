import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/scheduled_workouts_resync_migrator.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/profile/services/notification_inbox_service.dart';
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
    // A7 / B5 D9-D10 — canonical provider path.
    _restoreSub = ref.read(syncServiceProvider).onRestoreComplete.listen((_) {
      if (!mounted) return;
      // Bug 2026-05-19 (Monday +1 race) — re-apply the weekly refill
      // AFTER cloud restore lands. Splash-time refill in _runDeferredInit
      // (via runRolloverNow → refillIfNewWeek) writes local then schedules
      // fire-and-forget syncFreezes(); the subsequent _restoreFreezes used
      // to clobber that with stale cloud state. The restore-side max-merge
      // closes the race in the common case; this re-call is defence-in-
      // depth for the edge where local last_refill was somehow lost.
      // Idempotent — no-ops if last_refill is already this week.
      try {
        StreakProgressService.instance.refillIfNewWeek();
      } catch (e, st) {
        debugPrint(
            '[Splash] post-restore refillIfNewWeek failed (non-fatal): $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'splash_post_restore_refill'));
      }
      ref.invalidate(allExercisePRsProvider);
      ref.invalidate(currentPlanProvider);
      ref.invalidate(workoutStatsProvider);
      ref.invalidate(calendarWeekProvider);
      ref.invalidate(todayWorkoutProvider);
      ref.invalidate(streakFreezeProvider);
      ref.invalidate(streakProvider);
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
      _runDeferredInit().catchError((err, stack) { // Never block navigation on init failure
        debugPrint('[Splash] deferred init error: $err');
        // TODO(follow-up): surface fatal init errors (e.g. corrupted Hive) via a
        // dedicated /error route with a "Reinstall required" message and request_id.
      }),
      Future.delayed(const Duration(milliseconds: 3000)),
    ]);
    _navigateNext();
  }

  /// Initializes Supabase, seeds first-launch data, and sets up OneSignal.
  /// Safe to call multiple times — each service is idempotent.
  Future<void> _runDeferredInit() async {
    // Supabase must come first — auth state is needed by _navigateNext.
    await SupabaseService.instance.initialize();

    // C-6 (audit-2026-05-11) — The cross-account guard previously
    // lived here and was a no-op: `HiveService.instance.userBox` is a
    // GuardedBox that throws `HiveUserSession not opened` at this point
    // in cold start (no `openForUser` has run yet), which the try/catch
    // swallowed. The guard now lives inside `HiveUserSession.openForUser`
    // itself, so every code path that opens a session gets it for free.
    // `auth_provider._ensureLocalUser` performs a heavier
    // ClearResult / force-signOut second-layer check.

    // Seed exercise + food databases on first launch only.
    // compute() keeps JSON parsing off the main thread.
    // A7 / B5 D9-D10 — canonical provider path.
    await ref.read(seedServiceProvider).seedIfNeeded();

    // Bug 2026-05-19 (B3) — Defensive: clear stale `streak_freeze_just_used`
    // UI flag on every cold start. The flag is a one-shot UI signal: writer
    // is commitConsume(), sole reader is home_screen._checkStreakFreezeUsed
    // which clears it after firing the SnackBar. If a previous session set
    // the flag but never reached home (auth race, crash, signOut before the
    // snackbar rendered), the flag lingers in durable Hive and surfaces as
    // a spurious banner on the next launch. Cold-start clear is safe — any
    // real consume that fires during this session re-sets it.
    try {
      final progress = UserRepository.instance.getProgress();
      if (progress != null && progress['streak_freeze_just_used'] == true) {
        await UserRepository.instance
            .updateProgress({'streak_freeze_just_used': false});
      }
    } catch (e, st) {
      debugPrint('[Splash] just_used clear failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'splash_just_used_clear'));
    }

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
    // A7 / B5 D9-D10 — canonical provider path.
    unawaited(ref.read(syncServiceProvider).pushSnapshot());

    // APK Test #14 / Bug B.3 — one-shot resync of any local
    // 'completed' schedule rows that diverged from cloud during the
    // pre-fix FK-violation window. Idempotent (gated by per-user flag
    // in userBox); subsequent launches short-circuit. Fires before
    // checkAndSync so the migrator's syncWorkoutData() call uses the
    // hardened lookup-by-name path. See
    // docs/diagnoses/2026-05-10-resync-migrator-e3f7a8.md.
    unawaited(ScheduledWorkoutsResyncMigrator.runIfNeeded());

    // Trigger background sync check (weekly full sync, cross-channel pull).
    // Fire-and-forget — checkAndSync() has its own try-catch.
    // A7 / B5 D9-D10 — canonical provider path.
    unawaited(ref.read(syncServiceProvider).checkAndSync());
    // APK Test #3 / Obs 1: catch-up promotions for users who passed a
    // milestone while the app was uninstalled / signed out.
    unawaited(RankService.instance.evaluateAndPromote());

    // F1 · Refresh subscription state on every app launch so PRO survives
    // logout/login and cross-device sessions without requiring a PRO-feature
    // tap to trigger verifyFromServer().
    // A7 / B5 D9-D10 — canonical provider path.
    unawaited(ref.read(subscriptionServiceProvider).refreshFromSupabase());

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

    // Prune stale msg_count_* keys from userBox (older than 7 IST days).
    // Fire-and-forget — keeps userBox tidy without blocking navigation.
    unawaited(MessageLimitNotifier.pruneOld());

    // OneSignal — fire and forget; don't block navigation on OS permission dialog.
    if (!kIsWeb) {
      unawaited(OneSignal.initialize(AppConstants.oneSignalAppId));
      unawaited(OneSignal.Notifications.requestPermission(true));
      // Wire the in-app inbox — foreground/click listeners mirror every
      // push into the Hive notificationsBox so the Notifications screen
      // has data to render. Also seeds the welcome entry on first run.
      // See NotificationInboxService for the ingest contract.
      NotificationInboxService.instance.init();
    }
  }

  /// Audit H9 · If user is PRO and the current Phase has expired,
  /// auto-generate the next Phase (N+1). Reads goal / equipment /
  /// days_per_week / experience / injuries from the Hive profile +
  /// progress maps — same inputs the onboarding flow uses for Phase 1.
  Future<void> _autoGenerateNextPhaseForPro() async {
    try {
      // C-7 (audit-2026-05-11) — defensive HiveUserSession bootstrap.
      // Fires fire-and-forget BEFORE `_ensureLocalUser` has opened the
      // per-user namespaced boxes; without this the `getProfile()` /
      // `getProgress()` reads below throw `HiveUserSession not opened`
      // and PRO users silently miss next-phase auto-generation.
      final uid = await HiveUserSession.ensureOpenedForCurrentSession();
      if (uid == null) return;

      // A7 / B5 D9-D10 — canonical provider path.
      if (!ref.read(subscriptionServiceProvider).isPro()) return;
      if (!ref.read(workoutScheduleServiceProvider).isPhaseExpired()) return;

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

      // A7 / B5 D9-D10 — canonical provider path.
      final generated = await ref
          .read(workoutScheduleServiceProvider)
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
        // A7 / B5 D9-D10 — canonical provider path.
        unawaited(ref.read(syncServiceProvider).pushSnapshot());
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

    // Authenticated user — RestoringScreen is the canonical post-auth
    // gate (introduced in Test #4 / Q1). It owns the cloud profile
    // lookup, the onboarding-completion check, the Plan A self-heal
    // reconciliation (relocated from splash during the merge), and
    // the restore-from-cloud kickoff. Splash just routes there.
    context.go('/restoring');
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
