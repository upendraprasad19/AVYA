import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/deload_evaluator.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

// ── Home screen daily providers ──
import 'package:icanbefitter/features/home/providers/home_provider.dart';

// ── Nutrition daily providers ──
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

// ── AI Coach daily providers ──
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

// ── Train providers (workout plan, stats) ──
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

// ── Profile providers (biometrics from health sync) ──
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';
import 'package:icanbefitter/features/profile/providers/weekly_report_data_provider.dart';

/// Observes app lifecycle and invalidates all daily-scoped providers
/// when the calendar date changes (midnight rollover).
///
/// Attach via [DayRolloverObserver.init] from a widget that has
/// access to a [WidgetRef].
class DayRolloverObserver with WidgetsBindingObserver {
  DayRolloverObserver._();
  static final instance = DayRolloverObserver._();

  WidgetRef? _ref;
  bool _attached = false;
  Timer? _midnightTimer;

  /// Call once from a [ConsumerStatefulWidget.initState] or similar.
  void init(WidgetRef ref) {
    _ref = ref;
    if (!_attached) {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
      _scheduleMidnightTimer();
    }
    // Store today's date on init so we can compare later.
    _storeCurrentDate();
  }

  void dispose() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
    _midnightTimer?.cancel();
    _midnightTimer = null;
    _ref = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRollover();
      // Re-subscribe to realtime sync (was paused on background).
      //
      // e4a7c9 — this comment used to read "if PRO", above a line that checked
      // nothing. The gate lives inside subscribeToRealtimeSync now (on the
      // sink), so the call is correct as written and needs no condition here —
      // but the old wording described an entitlement check that did not exist,
      // which is how every user ended up attaching a PRO-only WAL poller on
      // every foreground. This is also the free→PRO recovery path: a
      // newly-upgraded user attaches on their next resume.
      unawaited(SyncService.instance.subscribeToRealtimeSync());
    } else if (state == AppLifecycleState.paused) {
      // Cancel realtime subscription on background to save battery/data.
      SyncService.instance.unsubscribeRealtime();
    }
  }

  // ── Internals ─────────────────────────────────────────────────

  static const _hiveKey = 'last_known_date';

  String _todayStr() => istTodayStr();

  void _storeCurrentDate() {
    HiveService.instance.configBox.put(_hiveKey, _todayStr());
  }

  Future<void> _checkAndRollover() async {
    final configBox = HiveService.instance.configBox;
    final lastKnown = configBox.get(_hiveKey) as String?;
    final today = _todayStr();

    if (lastKnown == today) return; // Same day — nothing to do.

    // ── Date changed! ───────────────────────────────────────────
    debugPrint('[DayRollover] Date changed: $lastKnown → $today');

    await _doRollover(today);
  }

  /// Bug #13 — Public unconditional rollover. Called from the splash screen
  /// on cold launch so that providers instantiated during the previous
  /// launch don't render stale "yesterday" data on first paint of home.
  ///
  /// Unlike [_checkAndRollover], this does NOT compare against the stored
  /// `last_known_date` — it always invalidates the full provider list and
  /// updates the stored date. The resume-time observer still uses the
  /// gated path so we don't double-invalidate when the user backgrounds
  /// and resumes within the same day.
  ///
  /// Pass the splash's [WidgetRef] explicitly so we don't depend on
  /// [init] having been called yet (cold launch hasn't reached home).
  ///
  /// IMPORTANT: uses `_ref ??= ref` (not `_ref = ref`) so that
  /// [init]'s long-lived app-root ref (set from app.dart.initState before
  /// any screen mounts) is NEVER overwritten by the short-lived splash ref.
  /// If runRolloverNow used `_ref = ref`, the splash ref would replace the
  /// durable app ref; after splash disposes its ref becomes stale; and all
  /// subsequent resume-time [_doRollover] calls would silently no-op on
  /// `ref.invalidate(...)`, leaving today-providers stale across midnight.
  /// (Bug b7e3f1 — APK Test #13, 2026-05-12)
  Future<void> runRolloverNow(WidgetRef ref) async {
    // Only store if init() hasn't already provided a long-lived app-root ref.
    _ref ??= ref;
    final today = _todayStr();
    debugPrint('[DayRollover] runRolloverNow (splash cold launch)');
    // Use the passed ref directly for the immediate cold-start invalidation,
    // in case _ref was already set to a durable ref that might not include
    // the splash context. This ensures cold-start invalidations always fire.
    await _doRolloverWithRef(ref, today);
  }

  /// b4e7a1 — the post-restore streak reckon for the BACKGROUND-restore branch.
  ///
  /// A returning user's cold start runs `runRolloverNow` BEFORE the background
  /// restore finishes, so its decay reckon is (correctly) gated off and nothing
  /// ever re-ran it: the idle-day freeze debit never persisted on a cold start
  /// (the founder's "16 days / 2 freezes" on 2026-10-06). The restoring
  /// screen's background heal calls this once the restore settles, ref-free
  /// (singletons) so it survives the screen's disposal:
  ///   (a) reckon + persist — gated inside on the restore having settled for
  ///       THIS account, so a restore that reported a streak-critical failure
  ///       still persists nothing;
  ///   (b) ONE best-effort LOW event when the restore succeeded but did not
  ///       settle (a LOW event can be dropped under client cooldown — its
  ///       absence proves nothing; the failing op is already named in
  ///       `client_errors` by the sync failure funnel);
  ///   (c) bump `restoreCompletedTick` LAST, so every tick listener (Home,
  ///       Train, Nutrition, AI Coach) repaints from the already-debited ledger.
  /// Kill switch `disable_streak_reckon_user_gate`: only the bump (the pre-fix
  /// heal), because the gate is then the tick this call is about to bump.
  void reckonAndNotifyAfterRestore() {
    if (SyncFlags.streakReckonUserGateEnabled) {
      try {
        WorkoutRepository.instance.reckonStreakDecayAndPersist();
      } catch (e, st) {
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'bg_heal_streak_reckon'));
      }
      try {
        final sync = SyncService.instance;
        final why = sync.lastRestoreWithheldReason;
        if (!sync.restoreSettledForCurrentUser && why != null) {
          unawaited(ErrorTelemetry.logEvent('streak_reckon_withheld',
              message: why));
        }
      } catch (_) {}
    }
    SyncService.instance.bumpRestoreCompleted();
  }

  /// Resume-time rollover — uses the stored [_ref] (set by [init]).
  Future<void> _doRollover(String today) async {
    final ref = _ref;
    if (ref == null) return;
    await _doRolloverWithRef(ref, today);
  }

  /// Core rollover logic. Accepts an explicit [ref] so both the resume
  /// path ([_doRollover] via [_ref]) and the cold-start path
  /// ([runRolloverNow] passing the splash ref directly) share one
  /// implementation without coupling to the stored [_ref].
  Future<void> _doRolloverWithRef(WidgetRef ref, String today) async {
    // 1. Reset usage counters (AI text logs, scan meal, etc.)
    await UsageCounterService.instance.checkAndResetCounters();

    // OI-38 (audit-2026-05-17 Hermes C3) — streak freeze weekly refill.
    // Moved out of StreakFreezeNotifier.build() (write-on-read anti-pattern).
    // Idempotent — only refills on Monday-after-last-refill, no-op otherwise.
    // Fires on every rollover (and from splash on first launch) so users
    // who don't open the app exactly on Monday still get their refill the
    // next launch after.
    try {
      StreakProgressService.instance.refillIfNewWeek();
    } catch (e, st) {
      debugPrint('[DayRollover] refillIfNewWeek failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_rollover_streak_freeze_refill'));
    }

    // D2 (f9d2e7) — streak-decay reckon. Refill runs FIRST (tops up the weekly
    // budget) THEN reckon, so an idle user's missed days are consumed + PERSISTED
    // on app-open — not only on completeWorkout (pre-D2 the read-only streak
    // display and the persisted freeze count diverged). Gated inside reckon
    // (the restore for THIS account settled + non-empty schedule — b4e7a1) so a
    // pre-restore cold start can't spuriously decay. A returning user's cold
    // start reaches here BEFORE the background restore finishes, so it is gated
    // off; `reckonAndNotifyAfterRestore` runs the reckon once the restore
    // settles.
    try {
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
    } catch (e, st) {
      debugPrint('[DayRollover] streak reckon failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_rollover_streak_reckon'));
    }

    // 2. Store new date
    await HiveService.instance.configBox.put(_hiveKey, today);

    // ⑥ Batch 7-B-2 (W2.4) — triggered-deload eval. Ship-dark (no-op unless BOTH
    // triggered-deload + readiness are live; disable_* kills them). Placed BEFORE the
    // invalidation block so a lifted week-4 repaints via the currentPlan /
    // todayWorkout / calendarWeek invalidations below. AWAITED so the rewrite
    // lands before the repaint; the eval's own durability sync is unawaited so
    // it never blocks cold-launch home nav. Non-fatal — must never break the
    // rollover.
    try {
      await DeloadEvaluator.instance.maybeEvaluate();
    } catch (e, st) {
      debugPrint('[DayRollover] deload eval failed (non-fatal): $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_rollover_deload_eval'));
    }

    // 3. Invalidate all daily-scoped providers
    // ── Workout providers ──
    ref.invalidate(currentPlanProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(allExercisePRsProvider);
    // Bug 9c8958 — streakFreezeProvider was absent from this list. The
    // Monday refill (StreakProgressService.refillIfNewWeek, called above)
    // wrote the new count to Hive correctly and on time; nothing told
    // this NotifierProvider its cached build was stale, so the streak
    // badge kept showing the pre-refill count until an unrelated
    // invalidation (or app restart) happened to rebuild it. Reader:
    // StreakFreezeNotifier.build() (home_provider.dart) — same file/class
    // as streakProvider two lines up, which WAS already invalidated here.
    ref.invalidate(streakFreezeProvider);

    // ── Nutrition providers ──
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(selectedDateProvider); // reset to today
    ref.invalidate(waterIntakeProvider);
    // Bug bae4dd — weeklyNutritionProvider was absent from this list. Its
    // build() computes weekStart fresh from DateTime.now() every time, so
    // once invalidated it always reflects the current week correctly; the
    // bug is purely that NOTHING invalidated it here, so a week-boundary
    // crossing left the weekly chart/avg pinned to the OLD week's cached
    // NotifierProvider state. Reader: WeeklyNutritionNotifier.build()
    // (nutrition_provider.dart) — already invalidated on every meal log
    // (NutritionWriteService.logMeal) but not on rollover.
    ref.invalidate(weeklyNutritionProvider);

    // ── Health providers ──
    ref.invalidate(todayStepsProvider);
    ref.invalidate(todayWeightLoggedProvider);
    ref.invalidate(biometricProvider);

    // ── Profile providers ──
    // Plan-review round 1 finding (docs/plan-reviews/reps-secs-invalidation-fixes.md)
    // — weeklyReportDataProvider (Profile PRO Weekly Report sparkline) computes
    // its rolling 7-day window from `DateTime.now()` directly and had NO
    // invalidation anywhere in the app: not here, not on a new weight/meal/
    // workout log. Unlike weeklyNutritionProvider (bug bae4dd, same batch),
    // which already had write-time invalidation and was only missing this
    // rollover leg, this provider was missing invalidation entirely — once
    // built, its 7-day window (dates AND values) never advances for the rest
    // of the app session. The write-time leg (invalidate on a new weight/meal/
    // workout log, matching the provider's own doc comment's stated intent)
    // is a separable, larger fix spanning 3 domains' call sites and is filed
    // as OI-267, not silently expanded into this batch or silently dropped.
    ref.invalidate(weeklyReportDataProvider);

    // Plan-review round 2 finding — two more day/week-boundary providers
    // with the SAME missing-rollover-invalidation shape, found by an
    // independent audit starting from a different angle (every
    // DateTime.now()-computing provider under lib/features/*/providers/).
    // Unlike weeklyReportDataProvider, both already had a SINGLE existing
    // write-time invalidation call site, so — like streakFreezeProvider/
    // weeklyNutritionProvider — only the rollover leg was missing; no
    // fan-out complexity, so fixed directly rather than filed as an OI.
    //
    // referralEligibilityProvider (bug 4018b3): daysRemaining counts down
    // from signup via DateTime.now().difference(signupDate).inDays — its
    // only invalidation call site (profile_content.dart's
    // ApplyReferralSheet.show onTap handler, on redemption success) fires
    // on a REDEMPTION, never on the day boundary
    // itself, so an un-redeemed user's "N DAYS LEFT" CTA could keep
    // showing a since-expired window for as long as Profile stays mounted
    // (StatefulShellRoute.indexedStack never disposes it on tab switch).
    ref.invalidate(referralEligibilityProvider);
    // usageWeeksProvider (bug ff3131): DateTime.now().difference(createdAt)
    // ~/ 7 gates the Weekly Report card's "Available after Week 1" lock —
    // its only invalidation call site is invalidateOnRetry (an explicit
    // user retry tap OR a background cloud-restore heal), neither of which
    // is a day/week-boundary event.
    ref.invalidate(usageWeeksProvider);

    // ── AI providers ──
    ref.invalidate(aiInsightProvider);
    ref.invalidate(predictionProvider);
    ref.invalidate(messageLimitProvider);

    // ── Misc daily providers ──
    // Expiry banner: dismiss is once-per-IST-day, so re-evaluate at rollover
    // (review P1 2026-06-06) — else a dismissed banner won't re-show next day.
    ref.invalidate(subscriptionExpiryBannerProvider);
    ref.invalidate(dailyQuoteProvider);
    ref.invalidate(aiTextLogRemainingProvider);
    ref.invalidate(scanMealRemainingProvider);
    ref.invalidate(cartAuditorRemainingProvider);

    debugPrint('[DayRollover] All daily providers invalidated.');
  }

  // ── Foreground midnight-timer backstop ───────────────────────────
  //
  // [didChangeAppLifecycleState] only checks the date on resume (and
  // [runRolloverNow] on cold launch). An app left open in the FOREGROUND
  // straight through midnight — no background/foreground transition —
  // never hits either trigger, so daily-scoped providers silently go
  // stale until the next resume. Founder-raised design gap, 2026-09-28.
  // This timer is a second, independent trigger: it fires once at the
  // next IST midnight and re-arms itself for the following one, so a
  // foreground session gets the same rollover a resume would have
  // triggered — without needing a resume.
  //
  // Uses the GATED `_checkAndRollover()` (not the unconditional
  // `_doRollover`), so a resume that happens to land within a few ms of
  // the same midnight can't double-invalidate.

  void _scheduleMidnightTimer() {
    _midnightTimer?.cancel();
    _midnightTimer =
        Timer(durationUntilNextIstMidnight(), _onMidnightTimerFired);
  }

  void _onMidnightTimerFired() {
    debugPrint('[DayRollover] Foreground midnight timer fired.');
    unawaited(_checkAndRollover());
    // Re-arm for the following midnight. Guarded by _attached so a
    // dispose() racing the callback (already queued when cancel() ran)
    // can't resurrect a timer after this observer has been torn down.
    if (_attached) {
      _scheduleMidnightTimer();
    }
  }
}

/// Wall-clock [Duration] until the next IST 00:00:00, honoring the
/// dev/test clock override ([nowWall] in `ist_date.dart`) so the year-sim
/// harness and tests can exercise this without waiting real time.
///
/// Not private (and top-level, not a class member) so
/// `day_rollover_midnight_timer_test.dart` can pin the arithmetic
/// directly, independent of Timer/Hive machinery — see CLAUDE.md's
/// "await-ing real disk I/O inside testWidgets hangs" pitfall for why a
/// pure formula test is preferable to routing every case through a real
/// Timer + real Hive I/O.
@visibleForTesting
Duration durationUntilNextIstMidnight() {
  final now = nowWall().toUtc();
  var nextMidnightUtc = istMidnightUtc(nowWall()).add(const Duration(days: 1));
  // Defensive: never schedule a zero/negative-duration timer even if `now`
  // lands exactly on (or fractionally past) a midnight boundary.
  while (!nextMidnightUtc.isAfter(now)) {
    nextMidnightUtc = nextMidnightUtc.add(const Duration(days: 1));
  }
  return nextMidnightUtc.difference(now);
}
