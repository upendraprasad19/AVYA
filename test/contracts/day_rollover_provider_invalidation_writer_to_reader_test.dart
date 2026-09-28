import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `day_rollover_provider_invalidation`
/// from docs/sot_registry.yaml.
///
/// Writer + Reader: DayRolloverService.runRolloverNow (self-contained)
/// The canonical "today" provider invalidation list. Adding a new today-bearing
/// provider requires updating runRolloverNow + the regression test.
void main() {
  late String rolloverSrc;

  setUpAll(() {
    final f = File('lib/core/services/day_rollover_service.dart');
    expect(f.existsSync(), isTrue,
        reason: 'day_rollover_service.dart must exist per sot_registry');
    rolloverSrc = f.readAsStringSync();
  });

  group('day_rollover_provider_invalidation writer↔reader source contract', () {
    test('runRolloverNow exists in day_rollover_service', () {
      expect(rolloverSrc.contains('runRolloverNow'), isTrue,
          reason: 'DayRolloverService must define runRolloverNow — '
              'canonical "today" invalidation entry point');
    });

    test('runRolloverNow invalidates todayWorkoutProvider', () {
      expect(rolloverSrc.contains('todayWorkoutProvider'), isTrue,
          reason:
              'runRolloverNow must invalidate todayWorkoutProvider per sot_registry.provider_invalidation_set');
    });

    test('runRolloverNow invalidates dailyNutritionProvider', () {
      expect(rolloverSrc.contains('dailyNutritionProvider'), isTrue,
          reason:
              'runRolloverNow must invalidate dailyNutritionProvider per sot_registry');
    });

    test('runRolloverNow invalidates streakProvider', () {
      expect(rolloverSrc.contains('streakProvider'), isTrue,
          reason:
              'runRolloverNow must invalidate streakProvider per sot_registry');
    });

    test('runRolloverNow invalidates aiInsightProvider', () {
      expect(rolloverSrc.contains('aiInsightProvider'), isTrue,
          reason:
              'runRolloverNow must invalidate aiInsightProvider per sot_registry');
    });

    // Bug 9c8958 / bae4dd (2026-09-28) — both were absent from the
    // invalidation list entirely (not a stale-name drift, an omission),
    // so this presence check plus the behavioral Test D/E in
    // day_rollover_provider_invalidation_behavioral_test.dart is the
    // regression coverage for both.
    test('runRolloverNow invalidates streakFreezeProvider', () {
      expect(rolloverSrc.contains('streakFreezeProvider'), isTrue,
          reason: 'runRolloverNow must invalidate streakFreezeProvider — '
              'the Monday refill (refillIfNewWeek) writes to Hive '
              'correctly, but the cached NotifierProvider needs its own '
              'invalidation to reflect it (bug 9c8958)');
    });

    test('runRolloverNow invalidates weeklyNutritionProvider', () {
      expect(rolloverSrc.contains('weeklyNutritionProvider'), isTrue,
          reason: 'runRolloverNow must invalidate weeklyNutritionProvider — '
              'its build() recomputes weekStart fresh from DateTime.now(), '
              'but nothing rebuilt the cached provider across a week '
              'boundary without this (bug bae4dd)');
    });

    // Bug b1bfea (2026-09-28, found by plan-review round 1) — this provider
    // had NO invalidation anywhere in the app (not just here) before this
    // fix; see docs/audit/open_issues.md OI-267 for the still-open
    // write-time invalidation gap this fix does not cover.
    test('runRolloverNow invalidates weeklyReportDataProvider', () {
      expect(rolloverSrc.contains('weeklyReportDataProvider'), isTrue,
          reason: 'runRolloverNow must invalidate weeklyReportDataProvider — '
              'its build() computes a 7-day window from DateTime.now() '
              'directly and had zero invalidation call sites anywhere in '
              'lib/ before this fix (bug b1bfea)');
    });

    // Bugs 4018b3 / ff3131 (2026-09-28, found by plan-review round 2's
    // independent audit) — both providers had exactly ONE existing
    // invalidation call site (a write-time-only trigger unrelated to the
    // day/week boundary), so — unlike weeklyReportDataProvider — only the
    // rollover leg was missing, with no fan-out complexity to file as an
    // OI. PRESENCE-ONLY by necessity: both compute from
    // SupabaseService.instance.currentUser?.createdAt + real DateTime.now()
    // with no Hive-mutable proxy and no existing test seam for injecting a
    // fake signup date, so a genuine behavioral (write→stale→invalidate→
    // fresh) test is not feasible — see each diagnose-doc's
    // `presence_only_reason`.
    // These two check the exact `ref.invalidate(X)` CALL substring, not just
    // the bare provider name — this file's own explanatory comments mention
    // several provider names in prose (e.g. "Unlike weeklyReportDataProvider,
    // both already had..."), so a bare-name `contains()` check would stay
    // green even if the real invalidate call were deleted, as long as SOME
    // comment nearby still mentions the name. Since these two providers have
    // NO behavioral-test sibling (presence_only: true — see each diagnose-doc)
    // to catch that class of regression instead, this presence check is the
    // ONLY protection they have and must not have that blind spot.
    test('runRolloverNow invalidates referralEligibilityProvider', () {
      expect(rolloverSrc.contains('ref.invalidate(referralEligibilityProvider)'),
          isTrue,
          reason: 'runRolloverNow must invalidate referralEligibilityProvider '
              '— its daysRemaining counts down via DateTime.now(), but its '
              'only invalidation call site fires on a redemption, never on '
              'the day boundary itself (bug 4018b3)');
    });

    test('runRolloverNow invalidates usageWeeksProvider', () {
      expect(rolloverSrc.contains('ref.invalidate(usageWeeksProvider)'), isTrue,
          reason: 'runRolloverNow must invalidate usageWeeksProvider — its '
              'week count derives from DateTime.now(), but its only '
              'invalidation call site (invalidateOnRetry) fires on a user '
              'retry tap or a background restore, never on the week '
              'boundary itself (bug ff3131)');
    });

    test('DayRolloverObserver class exists', () {
      // The class is DayRolloverObserver (not DayRolloverService — stale sot_registry ref)
      expect(
          rolloverSrc.contains('class DayRolloverObserver') ||
              rolloverSrc.contains('class DayRolloverService'),
          isTrue,
          reason:
              'day_rollover_service.dart must define DayRolloverObserver (or DayRolloverService) '
              '— the WidgetsBindingObserver that fires runRolloverNow on app resume');
    });

    test('runRolloverNow tracks date change to detect midnight rollover', () {
      // Rollover service compares stored date vs current date to detect midnight.
      // It uses DateTime.now() (device time) gated by the _hiveKey 'last_known_date'.
      // This is acceptable — the rollover invalidates on any date change.
      expect(
          rolloverSrc.contains('DateTime.now()') ||
              rolloverSrc.contains('_hiveKey') ||
              rolloverSrc.contains('last_known_date'),
          isTrue,
          reason:
              'day_rollover_service must track the current date (last_known_date) '
              'to detect when the calendar date has flipped and invalidation is needed');
    });
  });
}
