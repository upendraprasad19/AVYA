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

    // 1. Reset usage counters (AI text logs, scan meal, etc.)
    await UsageCounterService.instance.checkAndResetCounters();

    // 2. Store new date
    await configBox.put(_hiveKey, today);

    // 3. Invalidate all daily-scoped providers
    final ref = _ref;
    if (ref == null) return;

    // Home screen providers
    ref.invalidate(nutritionSummaryProvider);
    ref.invalidate(recentFoodLogsProvider);
    ref.invalidate(todayStepsProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(todayWeightLoggedProvider);

    // Nutrition providers
    ref.invalidate(waterIntakeProvider);
    ref.invalidate(dailyNutritionProvider);
    ref.invalidate(selectedDateProvider); // reset to today
    ref.invalidate(aiTextLogRemainingProvider);
    ref.invalidate(scanMealRemainingProvider);
    ref.invalidate(cartAuditorRemainingProvider);

    // AI Coach daily limits
    ref.invalidate(messageLimitProvider);
    ref.invalidate(trialInfoProvider);

    debugPrint('[DayRollover] All daily providers invalidated.');
  }
}
