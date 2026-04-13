import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';

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
      SyncService.instance.subscribeToRealtimeSync();
    } else if (state == AppLifecycleState.paused) {
      // Cancel realtime subscription on background to save battery/data.
      SyncService.instance.unsubscribeRealtime();
    }
  }

  // ── Internals ─────────────────────────────────────────────────

  static const _hiveKey = 'last_known_date';

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

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
  Future<void> runRolloverNow(WidgetRef ref) async {
    _ref = ref; // store for any subsequent resume-time invalidations
    final today = _todayStr();
    debugPrint('[DayRollover] runRolloverNow (splash cold launch)');
    await _doRollover(today);
  }

  Future<void> _doRollover(String today) async {
    // 1. Reset usage counters (AI text logs, scan meal, etc.)
    await UsageCounterService.instance.checkAndResetCounters();

    // 2. Store new date
    await HiveService.instance.configBox.put(_hiveKey, today);

    // 3. Invalidate all daily-scoped providers
    final ref = _ref;
    if (ref == null) return;

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
    ref.invalidate(trialInfoProvider);

    // ── Misc daily providers ──
    ref.invalidate(dailyQuoteProvider);
    ref.invalidate(aiTextLogRemainingProvider);
    ref.invalidate(scanMealRemainingProvider);
    ref.invalidate(cartAuditorRemainingProvider);

    debugPrint('[DayRollover] All daily providers invalidated.');
  }
}
