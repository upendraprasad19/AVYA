import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_read_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
// OI-38 (2026-05-17) — streak_progress_service + ist_date imports
// dropped. _refillIfNewWeek() moved to StreakProgressService.refillIfNewWeek()
// and is now invoked from DayRolloverObserver / splash, not from
// StreakFreezeNotifier.build().
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

// ── Calendar Day Data ───────────────────────────────────────────

/// Status of a single day in the weekly calendar strip.
enum CalendarDayStatus {
  /// Workout is scheduled but not yet done.
  planned,

  /// Workout was completed.
  completed,

  /// Rest day — no workout scheduled.
  rest,

  /// Past day with a planned workout that was not completed.
  missed,

  /// Day is marked as travel mode.
  travel,

  /// No plan data for this date (outside plan range).
  none,
}

/// Data for one day in the 7-day calendar strip.
class CalendarDayData {
  final DateTime date;
  final String dayName; // M, T, W, T, F, S, S
  final CalendarDayStatus status;
  final bool isToday;
  final bool isSwapped;
  final String? workoutName;

  const CalendarDayData({
    required this.date,
    required this.dayName,
    required this.status,
    required this.isToday,
    this.isSwapped = false,
    this.workoutName,
  });
}

/// Provider that exposes the 7-day calendar strip data.
///
/// Queries Hive workoutBox via [WorkoutScheduleService] for the current
/// week (Mon-Sun) and returns a [CalendarDayData] per day with the
/// correct status: planned, completed, rest, missed, travel, or none.
class CalendarWeekNotifier extends Notifier<List<CalendarDayData>> {
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  List<CalendarDayData> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final now = nowWall();
    final todayDate = istMidnight(now);
    final weekStart = mondayOfIst(now);
    // A7 / B5 D9-D10 — canonical provider path.
    final service = ref.read(workoutScheduleServiceProvider);

    final result = <CalendarDayData>[];
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final schedule = service.getScheduleForDate(date);
      final isToday = date == todayDate;
      final isPast = date.isBefore(todayDate);

      final type = schedule?['type'] as String? ?? 'none';
      final statusStr = schedule?['status'] as String? ?? 'none';
      final isSwapped = schedule?['is_swapped'] as bool? ?? false;
      final workoutName = schedule?['workout_name'] as String?;

      CalendarDayStatus status;
      if (statusStr == 'completed') {
        status = CalendarDayStatus.completed;
      } else if (statusStr == 'travel') {
        status = CalendarDayStatus.travel;
      } else if ((type == 'workout' || type == 'custom_template') && statusStr == 'planned') {
        // Past day with planned workout that wasn't done = missed
        status = isPast && !isToday
            ? CalendarDayStatus.missed
            : CalendarDayStatus.planned;
      } else if (type == 'rest' || statusStr == 'rest') {
        status = CalendarDayStatus.rest;
      } else {
        status = CalendarDayStatus.none;
      }

      result.add(CalendarDayData(
        date: date,
        dayName: _dayLabels[i],
        status: status,
        isToday: isToday,
        isSwapped: isSwapped,
        workoutName: workoutName,
      ));
    }
    return result;
  }

  /// Force refresh when workout status changes (e.g. after completing a workout).
  void refresh() {
    ref.invalidateSelf();
  }
}

final calendarWeekProvider =
    NotifierProvider<CalendarWeekNotifier, List<CalendarDayData>>(
        CalendarWeekNotifier.new);

// ── User Greeting ────────────────────────────────────────────────

class UserGreetingNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final profile = UserRepository.instance.getProfile();
    final name = profile?['full_name'] as String? ?? 'there';
    final firstName = name.split(' ').first;
    final hour = DateTime.now().hour;

    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    return '$greeting, $firstName';
  }
}

final userGreetingProvider =
    NotifierProvider<UserGreetingNotifier, String>(UserGreetingNotifier.new);

// ── Time of Day (mono caps, no name) ─────────────────────────────
//
// Test #10 obs 1 — header redesign decouples greeting from name. The
// new layout stacks `GOOD EVENING,` (mono caps eyebrow) above
// `AVYAANSH 👋` (Fraunces display) inside the avatar height. Existing
// userGreetingProvider stays intact for any other consumers; this is
// additive.
class UserTimeOfDayNotifier extends Notifier<String> {
  @override
  String build() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }
}

final userTimeOfDayProvider =
    NotifierProvider<UserTimeOfDayNotifier, String>(UserTimeOfDayNotifier.new);

// ── User First Name ──────────────────────────────────────────────

class UserFirstNameNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final profile = UserRepository.instance.getProfile();
    final rawName = profile?['full_name'] as String?;
    // APK Test #12.8 — probe for the founder's "Profile name USER"
    // observation. Fires when the canonical home-greeting reader sees
    // a null/empty/placeholder full_name despite an authenticated
    // session existing. Surfaces sites where Hive profile didn't
    // populate from cloud restore (or wasn't synced from onboarding).
    if (rawName == null || rawName.trim().isEmpty || rawName == 'User') {
      unawaited(ErrorTelemetry.logEvent(
        'profile_full_name_empty_at_read',
        message: 'reader=user_first_name '
            'rawName=${rawName ?? "<null>"} '
            'hasProfile=${profile != null}',
      ));
    }
    final name = rawName ?? 'User';
    return name.split(' ').first.toUpperCase();
  }
}

final userFirstNameProvider =
    NotifierProvider<UserFirstNameNotifier, String>(UserFirstNameNotifier.new);

// ── User Initial ─────────────────────────────────────────────────

class UserInitialNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final profile = UserRepository.instance.getProfile();
    final name = profile?['full_name'] as String? ?? 'U';
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }
}

final userInitialProvider =
    NotifierProvider<UserInitialNotifier, String>(UserInitialNotifier.new);

// ── Streak ───────────────────────────────────────────────────────

class StreakNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // APK Test #12.7 — single source of truth for streak count.
    // Previously read cached `current_streak_days` from `user_progress`,
    // which was only refreshed inside `completeWorkout`. The rank-chip
    // bottom sheet (`rank_service_record_sheet`) and rank evaluator
    // (`RankService`) both call `WorkoutRepository.calculateCurrentStreak()`
    // directly — a live walk-back through `schedule_<date>` keys. The two
    // surfaces drifted (home showed 0, rank chip showed 5) whenever the
    // cached field was stale (cold start without a fresh
    // `completeWorkout`, restore-from-cloud not yet finished, etc.).
    //
    // Calling the canonical helper here aligns home with rank-chip and
    // makes the displayed value match the user's mental model
    // (consecutive completed-or-rest days walking back from today).
    //
    // C-14 (audit-2026-05-11) — pure READ. streakProvider rebuilds
    // freely (provider invalidations, hot reload, dev tools). The
    // pre-CQRS-split `calculateCurrentStreak` silently consumed
    // freezes on each render — three displays in 10s could burn
    // three freezes for the same missed day.
    return WorkoutRepository.instance.currentStreak();
  }
}

final streakProvider =
    NotifierProvider<StreakNotifier, int>(StreakNotifier.new);

// ── Streak Freeze ────────────────────────────────────────────────

class StreakFreezeNotifier extends Notifier<int> {
  @override
  int build() {
    // OI-38 (audit-2026-05-17 Hermes C3) — build is now READ-ONLY.
    // Pre-fix `_refillIfNewWeek()` fired inside build, a Riverpod
    // write-on-read anti-pattern. Refill orchestration moved to
    // `StreakProgressService.refillIfNewWeek()` and invoked from
    // `DayRolloverObserver._doRolloverWithRef` (every rollover; idempotent
    // for non-Monday calls) + splash post-restore (first launch).
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final progress = UserRepository.instance.getProgress();
    final stored = (progress?['streak_freezes_available'] as int?) ?? 1;
    // Bug f8c1a5 (APK Test #16.2) — clamp on read defends against
    // corrupted Hive state (cloud-restored unclamped value from a legacy
    // path, or any future write that bypasses StreakProgressService).
    // Without this clamp a stored 8 with PRO cap=3 rendered "8/3" on
    // the streak badge until the next Monday refill — which itself was
    // gated out by the idempotency check when streak_freezes_last_refill
    // was already set. The one-shot StreakFreezeClampMigrator normalises
    // Hive at next launch; this read-side clamp makes the current
    // session's UX correct immediately. Pinned by
    // test/contracts/streak_freeze_value_clamped_on_read_test.dart.
    // A7 / B5 D9-D10 — migrated from SubscriptionService.instance to the
    // canonical provider so cross-account swaps trigger a reset via
    // ref.listen(authUserIdTokenProvider, …) inside subscriptionServiceProvider.
    // Phase 2 (discipline-overhaul, 2026-06-18) — upgraded to
    // ref.watch(subscriptionInfoProvider).isPro so a mid-session PRO grant
    // (onStateChanged → invalidate subscriptionInfoProvider) immediately
    // rebuilds this notifier and flips the cap 1→3 without requiring
    // an auth change or app relaunch. Pattern from profile_provider.dart:308.
    final cap = ref.watch(subscriptionInfoProvider).isPro ? 3 : 1;
    return stored.clamp(0, cap);
  }
}

final streakFreezeProvider =
    NotifierProvider<StreakFreezeNotifier, int>(StreakFreezeNotifier.new);

/// Max streak freezes the user is entitled to: 1 for free, 3 for PRO.
/// Read by [StreakBadge] (and [WardStatusStrip] passthrough) to render
/// the `available/max` ladder format. APK Test #14 / Bug D.3.
final streakFreezeMaxProvider = Provider<int>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  // A7 / B5 D9-D10 — see comment in StreakFreezeNotifier above.
  // Phase 2 (discipline-overhaul, 2026-06-18) — upgraded to
  // ref.watch(subscriptionInfoProvider).isPro so a mid-session PRO grant
  // flips the denominator 1→3 immediately (no relaunch). Pattern from
  // profile_provider.dart:308 (H-1 audit-2026-05-11). Behavioral test:
  // test/contracts/reactive_subscription_three_sites_test.dart H-3.
  return ref.watch(subscriptionInfoProvider).isPro ? 3 : 1;
});

// ── Streak Warning Eligibility (Bug #12) ─────────────────────────

/// Bug #12 — Derived inputs for the smart streak warning banner.
///
/// The old logic fired on Sat/Sun mornings regardless of context, which is
/// useless for users with mid-week schedules and annoying for early-morning
/// trainers. This provider replaces it with personalised, time-aware logic:
///
/// 1. **Median workout hour** — read from last 10 completed workouts
///    (more robust than mean against outlier sessions). Falls back to
///    19:00 IST for new users with <3 logs.
/// 2. **isWorkoutDayToday** — today's schedule must be a workout entry
///    (not rest, not none).
/// 3. **isTodayCompleted** — today's workout must NOT already be done.
///
/// The actual show/hide decision lives in [StreakWarningBanner.shouldShow]
/// which applies a 15:00 floor and 23:00 ceiling on top of (median + 3).
class StreakWarningEligibility {
  /// True when ALL guards pass: workout day, not yet completed, time of
  /// day past the user's personalised threshold.
  final bool shouldShow;
  /// Computed median completion hour with cold-start fallback (19:00).
  /// Useful for diagnostics — and for tests that want to assert the math.
  final int medianWorkoutHour;
  /// Whether today is a workout day per Hive schedule.
  final bool isWorkoutDayToday;
  /// Whether today's workout is already marked completed.
  final bool isTodayCompleted;

  const StreakWarningEligibility({
    required this.shouldShow,
    required this.medianWorkoutHour,
    required this.isWorkoutDayToday,
    required this.isTodayCompleted,
  });
}

class StreakWarningEligibilityNotifier
    extends Notifier<StreakWarningEligibility> {
  @override
  StreakWarningEligibility build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final streakDays = ref.watch(streakProvider);
    final todaySchedule = ref.watch(todayWorkoutProvider);

    // 1. Is today a workout day? Read from today's schedule entry.
    //    `workout` and `custom_template` are both real workout days.
    //    `rest` and missing entries are not.
    final type = todaySchedule?['type'] as String? ?? 'none';
    final status = todaySchedule?['status'] as String? ?? 'none';
    final isWorkoutDayToday = type == 'workout' || type == 'custom_template';

    // 2. Has today's workout already been completed?
    final isTodayCompleted = status == 'completed';

    // 3. Personalised median workout hour with cold-start fallback.
    //    <3 logs → 19:00 IST default (sensible "after evening" threshold).
    //    Otherwise → median of last 10 completion hours.
    final hours =
        WorkoutRepository.instance.getRecentWorkoutCompletionHours(limit: 10);
    final int medianHour;
    if (hours.length < 3) {
      medianHour = 19;
    } else {
      final sorted = [...hours]..sort();
      final mid = sorted.length ~/ 2;
      medianHour = sorted.length.isOdd
          ? sorted[mid]
          : ((sorted[mid - 1] + sorted[mid]) / 2).round();
    }

    // Reuse the pure decision logic in StreakWarningBanner.shouldShow so
    // the rules stay in one place and remain unit-testable.
    final show = _evaluate(
      streakDays: streakDays,
      isWorkoutDayToday: isWorkoutDayToday,
      isTodayCompleted: isTodayCompleted,
      medianWorkoutHour: medianHour,
    );

    return StreakWarningEligibility(
      shouldShow: show,
      medianWorkoutHour: medianHour,
      isWorkoutDayToday: isWorkoutDayToday,
      isTodayCompleted: isTodayCompleted,
    );
  }

  /// Inline copy of [StreakWarningBanner.shouldShow]'s rule so we don't have
  /// to import the widget into the provider layer. The widget keeps the
  /// public method as the canonical reference; this is a passthrough.
  bool _evaluate({
    required int streakDays,
    required bool isWorkoutDayToday,
    required bool isTodayCompleted,
    required int medianWorkoutHour,
  }) {
    if (streakDays == 0) return false;
    if (!isWorkoutDayToday) return false;
    if (isTodayCompleted) return false;

    final currentHour = DateTime.now().hour;
    final rawThreshold = medianWorkoutHour + 3;
    // Must stay in sync with [StreakWarningBanner.shouldShow].
    // Handoff: banner is evening-only → 18 floor.
    final thresholdHour = rawThreshold.clamp(18, 23);
    return currentHour >= thresholdHour;
  }
}

final streakWarningEligibilityProvider = NotifierProvider<
    StreakWarningEligibilityNotifier,
    StreakWarningEligibility>(StreakWarningEligibilityNotifier.new);

// ── Subscription expiry banner (diagnose 2026-06-06) ──────────────

/// configBox kill-switch (§4.6) — set true to disable the expiry banner.
const String _expiryBannerKillSwitchKey = 'disable_expiry_banner';

/// Once-per-day dismiss key (per-user, IST date). When it equals today's IST
/// date the banner stays hidden until the next day.
const String _expiryBannerDismissedKey = 'expiry_banner_dismissed_date';

/// Home PRO-expiry banner state. `show` gates rendering; `severity` picks amber
/// (expiringSoon) vs red (lapsed); `daysLeft` fills the copy.
class ExpiryBannerState {
  final bool show;
  final ExpiryBannerSeverity severity;
  final int daysLeft;
  const ExpiryBannerState({
    this.show = false,
    this.severity = ExpiryBannerSeverity.none,
    this.daysLeft = 0,
  });
}

/// Decides whether the Home subscription-expiry banner shows, reusing the pure
/// [SubscriptionService.expiryBannerSeverity] decision so the rule stays
/// testable. Honors a per-user once-per-day dismiss + a configBox kill-switch.
class SubscriptionExpiryBannerNotifier extends Notifier<ExpiryBannerState> {
  @override
  ExpiryBannerState build() {
    ref.watch(authUserIdTokenProvider); // rebuild on auth change
    ref.watch(subscriptionInfoProvider); // rebuild on PRO state change

    if (HiveService.instance.configBox.get(_expiryBannerKillSwitchKey) ==
        true) {
      return const ExpiryBannerState();
    }

    final sub = SubscriptionService.instance;
    final isProNow = sub.proStateSnapshot(); // OI-44 U6: PURE — build method
    final daysLeft = sub.daysUntilExpiry();
    final severity = SubscriptionService.expiryBannerSeverity(
      isPro: isProNow,
      daysUntilExpiry: daysLeft,
      isLapsed: !isProNow && sub.proLapsedAt != null,
    );
    if (severity == ExpiryBannerSeverity.none) {
      return const ExpiryBannerState();
    }

    // Once-per-day dismiss: hidden if dismissed today (IST).
    final dismissed = MigratedKey.read<dynamic>(_expiryBannerDismissedKey);
    final hiddenToday = dismissed != null &&
        dismissed.toString() == istDateStr(DateTime.now());

    // Suppress during an in-flight renewal so a user mid-payment doesn't see a
    // red "expired" flash before the webhook lands (review P2 2026-06-06).
    final show = !hiddenToday && !sub.isPaymentInFlight;

    return ExpiryBannerState(
      show: show,
      severity: severity,
      daysLeft: daysLeft,
    );
  }

  /// Hide the banner for the rest of today (IST). It re-appears tomorrow until
  /// the user renews (which clears the lapsed marker + restores PRO).
  Future<void> dismissForToday() async {
    await MigratedKey.write(
        _expiryBannerDismissedKey, istDateStr(DateTime.now()));
    ref.invalidateSelf();
  }
}

final subscriptionExpiryBannerProvider = NotifierProvider<
    SubscriptionExpiryBannerNotifier,
    ExpiryBannerState>(SubscriptionExpiryBannerNotifier.new);

// ── Today's Workout ──────────────────────────────────────────────

class TodayWorkoutNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // Read today's schedule from WorkoutScheduleService (single source of truth)
    // A7 / B5 D9-D10 — canonical provider path.
    return ref
        .read(workoutScheduleServiceProvider)
        .getScheduleForDate(DateTime.now());
  }
}

final todayWorkoutProvider =
    NotifierProvider<TodayWorkoutNotifier, Map<String, dynamic>?>(
        TodayWorkoutNotifier.new);

// ── Nutrition Summary ────────────────────────────────────────────

class NutritionSummaryData {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double calorieTarget;
  final double proteinTarget;
  final double carbTarget;
  final double fatTarget;

  const NutritionSummaryData({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.calorieTarget = 2000,
    this.proteinTarget = 120,
    this.carbTarget = 250,
    this.fatTarget = 65,
  });
}

class NutritionSummaryNotifier extends Notifier<NutritionSummaryData> {
  @override
  NutritionSummaryData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // F7 · Single source of truth — Home + Nutrition screens sum
    // identically via NutritionRepository.dailyMacros.
    final today = DateTime.now();
    final macros = NutritionRepository.instance.dailyMacros(today);

    final profile = UserRepository.instance.getProfile();
    final baseCalorieTarget =
        (profile?['daily_calories'] as num?)?.toDouble() ?? 2000;
    final proteinTarget =
        (profile?['protein_grams'] as num?)?.toDouble() ?? 120;
    // OBS-11 — dual-name read; a restored profile carries the plural
    // `carbs_grams` (cloud/restore name), not `carb_grams`. Without this Home's
    // carb target silently fell to the 250 default. (See nutrition_provider.)
    final carbTarget =
        ((profile?['carb_grams'] ?? profile?['carbs_grams']) as num?)
                ?.toDouble() ??
            250;
    final fatTarget = (profile?['fat_grams'] as num?)?.toDouble() ?? 65;

    // Apply AI-coach calorie target override for today (clamped 800..6000).
    // Macros are not scaled — overrides ship a kcal delta only.
    final override =
        NutritionRepository.instance.getActiveTargetOverride(today);
    final calorieTarget = override == null
        ? baseCalorieTarget
        : (baseCalorieTarget + ((override['delta_kcal'] as num?) ?? 0))
            .clamp(800, 6000)
            .toDouble();

    return NutritionSummaryData(
      calories: (macros['calories'] as num?)?.toDouble() ?? 0.0,
      protein: (macros['protein'] as num?)?.toDouble() ?? 0.0,
      carbs: (macros['carbs'] as num?)?.toDouble() ?? 0.0,
      fat: (macros['fat'] as num?)?.toDouble() ?? 0.0,
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      carbTarget: carbTarget,
      fatTarget: fatTarget,
    );
  }
}

final nutritionSummaryProvider =
    NotifierProvider<NutritionSummaryNotifier, NutritionSummaryData>(
        NutritionSummaryNotifier.new);

// ── Weight History ───────────────────────────────────────────────

/// Returns ALL weight entries sorted by date (the widget handles filtering).
class WeightHistoryNotifier extends Notifier<List<WeightEntryData>> {
  @override
  List<WeightEntryData> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final hive = HiveService.instance;
    final healthBox = hive.healthBox;

    final entries = <WeightEntryData>[];
    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'weight_log' || log['weight_kg'] != null) {
        final date = log['date'] as String? ?? '';
        final weight = (log['weight_kg'] as num?)?.toDouble();
        if (weight != null && date.isNotEmpty) {
          entries.add(WeightEntryData(date: date, weight: weight));
        }
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }
}

class WeightEntryData {
  final String date;
  final double weight;
  const WeightEntryData({required this.date, required this.weight});
}

final weightHistoryProvider =
    NotifierProvider<WeightHistoryNotifier, List<WeightEntryData>>(
        WeightHistoryNotifier.new);

// ── Latest AI Coach Insight ──────────────────────────────────────

class AiInsightNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final now = DateTime.now();

    // 1. Always compute insight from LOCAL schedule data (source of truth)
    final insight = _computeScheduleInsight(now);

    // 2. Optionally append a coach tip from today's latest AI interaction
    final coachTip = _getLatestCoachTip(now);
    if (coachTip != null) {
      return '$insight\n💡 $coachTip';
    }

    return insight;
  }

  /// Build insight from today's workout schedule in Hive.
  String _computeScheduleInsight(DateTime now) {
    // A7 / B5 D9-D10 — canonical provider path.
    final schedule =
        ref.read(workoutScheduleServiceProvider).getScheduleForDate(now);
    if (schedule != null) {
      final type = schedule['type'] as String? ?? 'rest';
      final status = schedule['status'] as String? ?? 'planned';
      final name = schedule['workout_name'] as String? ?? 'Workout';
      final exercises = schedule['exercises'] as List? ?? [];
      if (status == 'completed') {
        return '$name completed today — ${exercises.length} exercises. Great work 💪';
      } else if (type == 'workout' || type == 'custom_template') {
        return '$name is scheduled for today — ${exercises.length} exercises. Ready when you are!';
      } else if (type == 'rest') {
        return 'Rest day! You have earned it! 🎉';
      }
    }
    return 'No workout scheduled for today. A good day for active recovery!';
  }

  /// Extract a short tip from the latest AI coach response today.
  /// Returns the last sentence (≤80 chars) or null.
  String? _getLatestCoachTip(DateTime now) {
    final coachBox = HiveService.instance.coachBox;
    final todayPrefix = formatDateKey(now);
    String? latestResponse;
    String latestDate = '';

    for (final raw in coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      if (!createdAt.startsWith(todayPrefix)) continue;
      if (interaction['failed'] == true) continue;
      final response = interaction['ai_response'] as String?;
      if (response != null && createdAt.compareTo(latestDate) > 0) {
        latestDate = createdAt;
        latestResponse = response;
      }
    }

    if (latestResponse == null) return null;

    // Extract last sentence as a concise tip — skip if it's too long
    final sentences = latestResponse.split(RegExp(r'[.!?]\s+'));
    if (sentences.isEmpty) return null;
    final tip = sentences.last.trim();
    if (tip.length > 80 || tip.length < 10) return null;
    return tip;
  }
}

final aiInsightProvider =
    NotifierProvider<AiInsightNotifier, String?>(AiInsightNotifier.new);

// ── Recent Food Logs ─────────────────────────────────────────────

class RecentFoodLogEntry {
  final String name;
  final double protein;
  final double carbs;
  final double fat;
  final double calories;

  const RecentFoodLogEntry({
    required this.name,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.calories,
  });
}

class RecentFoodLogsNotifier extends Notifier<List<RecentFoodLogEntry>> {
  @override
  List<RecentFoodLogEntry> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final hive = HiveService.instance;
    final nutritionBox = hive.nutritionBox;
    final today = DateTime.now();
    // Obs 2 (2026-06-05): match the writer's IST date key (was local
    // year/month/day — drifts vs `istDateStr(date)` between IST 00:00–05:30).
    final todayStr = istDateStr(today);

    final logs = <RecentFoodLogEntry>[];
    for (final raw in nutritionBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      // Hermes L37: exclude saved-meal templates (defensive — they currently
      // carry no `date` so they're already filtered, but guard explicitly so a
      // future writer that stamps `date` on a template can't leak into recents).
      if (log['is_saved_meal'] == true) continue;
      if (log['date'] == todayStr) {
        // Obs 2: use the SHARED derivation (items[].name → meal_type). The home
        // reader previously read top-level `food_name`/`meal_name`/`name` that
        // the writer never writes → every row showed "Unknown".
        final name = NutritionReadService.deriveMealDisplayName(log);
        if (name == NutritionReadService.kFallbackMealName) {
          // ignore: discarded_futures
          ErrorTelemetry.logEvent('food_log_unknown_name',
              message: 'source=home_recent_logs date=$todayStr');
        }
        logs.add(RecentFoodLogEntry(
          name: name,
          protein: (log['total_protein'] as num?)?.toDouble() ?? 0,
          carbs: (log['total_carbs'] as num?)?.toDouble() ?? 0,
          fat: (log['total_fat'] as num?)?.toDouble() ?? 0,
          calories: (log['total_calories'] as num?)?.toDouble() ?? 0,
        ));
      }
    }

    return logs;
  }
}

final recentFoodLogsProvider =
    NotifierProvider<RecentFoodLogsNotifier, List<RecentFoodLogEntry>>(
        RecentFoodLogsNotifier.new);

// ── Daily Quote ────────────────────────────────────────────────────

class DailyQuoteData {
  final String quote;
  final String author;

  const DailyQuoteData({required this.quote, required this.author});
}

class DailyQuoteNotifier extends Notifier<DailyQuoteData> {
  static const _defaultQuotes = [
    DailyQuoteData(
      quote: 'The only bad workout is the one that didn\'t happen.',
      author: 'Unknown',
    ),
    DailyQuoteData(
      quote: 'Take care of your body. It\'s the only place you have to live.',
      author: 'Jim Rohn',
    ),
    DailyQuoteData(
      quote: 'Strength does not come from the body. It comes from the will.',
      author: 'Gandhi',
    ),
    DailyQuoteData(
      quote: 'The pain you feel today will be the strength you feel tomorrow.',
      author: 'Arnold Schwarzenegger',
    ),
    DailyQuoteData(
      quote: 'Fitness is not about being better than someone else. It\'s about being better than you used to be.',
      author: 'Khloe Kardashian',
    ),
    DailyQuoteData(
      quote: 'Your body can stand almost anything. It\'s your mind that you have to convince.',
      author: 'Andrew Murphy',
    ),
    DailyQuoteData(
      quote: 'Success isn\'t always about greatness. It\'s about consistency.',
      author: 'Dwayne Johnson',
    ),
  ];

  @override
  DailyQuoteData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // Use day of year as index to rotate quotes daily.
    final dayOfYear = DateTime.now().difference(
      DateTime(DateTime.now().year, 1, 1),
    ).inDays;
    final index = dayOfYear % _defaultQuotes.length;
    return _defaultQuotes[index];
  }
}

final dailyQuoteProvider =
    NotifierProvider<DailyQuoteNotifier, DailyQuoteData>(
        DailyQuoteNotifier.new);

// ── Today's Steps ─────────────────────────────────────────────────

class TodayStepsNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final hive = HiveService.instance;
    final healthBox = hive.healthBox;
    final todayStr = istTodayStr();

    for (final raw in healthBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] == 'step_log' && log['date'] == todayStr) {
        return (log['steps'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }
}

final todayStepsProvider =
    NotifierProvider<TodayStepsNotifier, int>(TodayStepsNotifier.new);

// ── Weight Log ────────────────────────────────────────────────────

class WeightLogNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> logWeight(double weightKg) async {
    // audit-2026-05-16 task E.7 — routes through HealthWriteService so
    // the `weight_<istDate>` key is IST-anchored and the syncWeightNow
    // + pushSnapshot fan-out lives in a single canonical place. The
    // companion profile mutation stays here (the service is scoped to
    // healthBox writes).
    //
    // Bug w7r4c3 (APK Test #16.2) — must be Future<void> + awaitable.
    // HealthWriteService.logWeight does `await _acquireLock` BEFORE
    // `box.put`, so the Hive write is strictly async. If the caller
    // (WeightLogSheet._save / ConversationalLogHandler._logWeight)
    // fires `ref.invalidate(weightHistoryProvider)` synchronously after
    // this method returns, the provider rebuilds reading stale Hive
    // BEFORE the put microtask runs and the entries-count footer shows
    // a stale value. The await below collapses the race.
    await HealthWriteService.instance.logWeight(
      date: DateTime.now(),
      weightKg: weightKg,
      source: WriteSource.manual,
    );
    // Also update profile current_weight_kg via canonical write
    // service (audit 2026-05-20 A4). ProfileWriteService.updateField
    // handles the merge under mutex, stamps `updated_at`, and fires
    // syncProfileNow internally — no need to call it explicitly here.
    await ProfileWriteService.instance.updateField('current_weight_kg', weightKg);
    BadgeService.instance.checkAll();
  }
}

final weightLogNotifierProvider =
    NotifierProvider<WeightLogNotifier, void>(WeightLogNotifier.new);

// ── Today Weight Logged Check ────────────────────────────────────

class TodayWeightLoggedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final healthBox = HiveService.instance.healthBox;
    // Bug w7r4c3 (APK Test #16.2) — read the IST date string to match the
    // writer's key formula at health_write_service.dart:122. Pre-fix this
    // used device-local YYYY-MM-DD; at IST 00:00-05:30 the local UTC date
    // is the prior day, so a freshly-written today-IST weight returned
    // false here and the "log weight" pill on Home would not flip to its
    // done state until ~05:30 IST. Pinned by test/contracts/today_weight_logged_ist_test.dart.
    final todayStr = istDateStr(DateTime.now());
    return healthBox.get('weight_$todayStr') != null;
  }

  void refresh() => ref.invalidateSelf();
}

final todayWeightLoggedProvider =
    NotifierProvider<TodayWeightLoggedNotifier, bool>(
        TodayWeightLoggedNotifier.new);

// ── All Exercise PRs ─────────────────────────────────────────────

/// Loads PR records for every exercise the user has ever logged.
/// Invalidated by [completeWorkout()] so home screen refreshes immediately.
class AllExercisePRsNotifier extends Notifier<List<ExercisePR>> {
  @override
  List<ExercisePR> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    return WorkoutRepository.instance.loadAllExercisePRs();
  }
}

final allExercisePRsProvider =
    NotifierProvider<AllExercisePRsNotifier, List<ExercisePR>>(
        AllExercisePRsNotifier.new);

// ── ⑧ 3-a2 (W2.5) repeat-content nudge ──────────────────────────
// (declared at EOF so it never shifts the line-ranges of the providers above
// that the SoT registry pins — check_sot_registry_parity.dart.)

/// The low-adherence "you repeated — step it up?" nudge flag.
///
/// SET (`true`) by `advanceProPhaseIfExpired` (`lib/shared/services/
/// pro_phase_advance.dart`) when a phase advance actually REPEATED last phase's
/// plan (adherence-gate flag ON + low completion). Local-only + user-scoped
/// (MigratedKey → userBox). CLEARED only on an explicit [PhaseRepeatNudgeNotifier.dismiss]
/// (never in build) so the banner SURVIVES Home rebuilds until the user acts.
/// Ship-dark: with `enable_adherence_gate` OFF the writer never fires ⇒ stays false.
class PhaseRepeatNudgeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      MigratedKey.read<bool>('phase_repeat_nudge_pending') ?? false;

  void dismiss() {
    MigratedKey.write('phase_repeat_nudge_pending', false);
    state = false;
  }
}

final phaseRepeatNudgeProvider =
    NotifierProvider<PhaseRepeatNudgeNotifier, bool>(
        PhaseRepeatNudgeNotifier.new);
