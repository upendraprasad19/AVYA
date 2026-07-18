import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/scheduled_workouts_resync_migrator.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/services/pro_phase_advance.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/profile/services/notification_inbox_service.dart';
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

    // Bug 2026-05-22 (diagnose dc52a4) — the previous `onRestoreComplete`
    // listener lived here and was DEAD CODE: splash disposes when it
    // navigates to /restoring (within ~3s) — long before the
    // restoreFromCloudForUser future emits (~36s in the founder's
    // case). The listener's StreamSubscription.cancel() in dispose()
    // tore down the listener before it could fire. The
    // refillIfNewWeek + provider-invalidations moved to
    // RestoringScreen._ensureOwnershipBeforeHome where they actually
    // run AFTER HiveUserSession.openForUser has opened the user-scoped
    // boxes.

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

  /// Hive-first boot guard (diagnose a1f9c4). `_runDeferredInit` `await`s
  /// cloud/IO (`SupabaseService.initialize` → `Supabase.initialize`) with no
  /// timeout. If that STALLS — slow/cold backend, or a wedged web session —
  /// the future never completes, so `_navigateNext` never fires and the user
  /// is stranded on the AVYA seal with NO escape (the `.catchError` only
  /// handles a THROW, not a HANG). Bound the init so the app always reaches
  /// the next route and boots offline-first from Hive. On a genuine timeout
  /// `isAuthenticated` reads false → routes to `/sign-in` (a re-auth is a far
  /// better degradation than an infinite splash; only fires on a real >12s
  /// stall — a warm init is <2s). Kill-switch: `disable_splash_init_timeout`.
  static const Duration _kInitTimeout = Duration(seconds: 12);

  Future<void> _initAndNavigate() async {
    Future<void> guardedInit = _runDeferredInit().catchError((err, stack) {
      debugPrint('[Splash] deferred init error: $err');
    });
    final timeoutDisabled = HiveService.instance.configBox
            .get('disable_splash_init_timeout') ==
        true;
    if (!timeoutDisabled) {
      guardedInit = guardedInit.timeout(_kInitTimeout, onTimeout: () {
        debugPrint('[Splash] deferred init exceeded '
            '${_kInitTimeout.inSeconds}s — navigating anyway (offline-first boot)');
      });
    }
    await Future.wait([
      guardedInit,
      Future.delayed(const Duration(milliseconds: 3000)),
    ]);
    _navigateNext();
  }

  /// Initializes Supabase, seeds first-launch data, and sets up OneSignal.
  /// Safe to call multiple times — each service is idempotent.
  Future<void> _runDeferredInit() async {
    // Supabase must come first — auth state is needed by _navigateNext.
    await SupabaseService.instance.initialize();

    // Obs 4 (2026-06-05): warm the backend connection NOW (parallel with the
    // ~3s branding) so RestoringScreen's restore avoids the ~24s cold-start
    // penalty on its first query. Fire-and-forget — never blocks navigation.
    unawaited(SupabaseService.instance.warmConnection());

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

    // Bug 2026-05-22 (diagnose dc52a4) — the just_used clear AND the
    // DayRolloverObserver.runRolloverNow(ref) call previously lived here.
    // Both touched userBox via GuardedBox, which throws "HiveUserSession
    // not opened" at this point in cold start. The C-6 (audit-2026-05-11)
    // comment at lines 127-134 above already documented this constraint
    // but the code drifted. Both calls moved to
    // RestoringScreen._ensureOwnershipBeforeHome where HiveUserSession is
    // open. day_rollover_streak_freeze_refill telemetry had been failing
    // on every trigger since at least 2026-05-06 — universally for every
    // user, every cold start.

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

    // Audit H9 · PRO auto-generate next Phase on expiry (REG-1 hardened,
    // a4e2d9).
    //
    // Free users hit the 3-door PlanExpiredCard on day 29. PRO users should
    // never see that card — if their Phase has run out, silently generate the
    // next one so Home + Train just show fresh workouts. This is fire-and-
    // forget and is NOT awaited, so it CAN fail or still be in flight when
    // Home/Train build. When it does, those screens now render the PRO
    // `PhaseGeneratingCard` (a one-tap regenerate) instead of the free
    // "go PRO" card — so a slow/errored pass no longer strands a paying user.
    // A failure here is recorded via ErrorTelemetry (never swallowed).
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

  /// Audit H9 · If the user is PRO and the current Phase has expired,
  /// auto-generate the next Phase (N+1). Delegates to the shared
  /// [advanceProPhaseIfExpired] (also used by the Home/Train
  /// `PhaseGeneratingCard` retry CTA), so both surfaces run one code path.
  /// Fire-and-forget: a failure is recorded via telemetry, never surfaced or
  /// swallowed (REG-1 a4e2d9 — a swallowed `debugPrint` used to hide the
  /// failure that stranded a PRO on the free PlanExpiredCard).
  Future<void> _autoGenerateNextPhaseForPro() async {
    try {
      await advanceProPhaseIfExpired(ref);
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'splash_auto_advance_phase'));
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
