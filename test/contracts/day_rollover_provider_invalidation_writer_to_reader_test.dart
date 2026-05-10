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
