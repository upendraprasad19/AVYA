import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
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

// ── Profile providers (biometrics from health sync) ──
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

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

  /// Call once from a [ConsumerStatefulWidget.initState] or similar.
  void init(WidgetRef ref) {
    _ref = ref;
    if (!_attached) {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    }
    // Store today's date on init so we can compare later.
    _storeCurrentDate();
  }

  void dispose() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
    _ref = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRollover();
      // Re-subscribe to realtime sync if PRO (was paused on background).
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

    // 2. Store new date
    await HiveService.instance.configBox.put(_hiveKey, today);

    // 3. Invalidate all daily-scoped providers
    // ── Workout providers ──
    ref.invalidate(currentPlanProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(allExercisePRsProvider);

    // ── Nutrition providers ──
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(selectedDateProvider); // reset to today
    ref.invalidate(waterIntakeProvider);

    // ── Health providers ──
    ref.invalidate(todayStepsProvider);
    ref.invalidate(todayWeightLoggedProvider);
    ref.invalidate(biometricProvider);

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
}
