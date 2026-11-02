// train-header-b2 (plan docs/plans/2026-11-02-train-header-week-mode.md): the hero label follows the WEEK
// (Baseline / Overreach / Peak / Deload, `Working` after a lifted deload), not
// the phase number. ONE resolver, `WorkoutScheduleReadService.weekModeForRow`,
// feeds Train's hero (both `WorkoutDayData` constructors) and Home's card.
//
// Also hosts the crash-safety cases of `currentWaveCharacters()` (moved here
// from the deleted phase-arc test: the function stays, it feeds the resolver's
// fallback and the OI-166 hotel stamp via `planWeekAndCharacterFor`).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/week_mode_label.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

String _src(String path) {
  final raw = File(path).readAsStringSync();
  // strip comments so a pin cannot pass on prose
  return raw
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
      .join('\n');
}

void main() {
  late Directory tempDir;
  final planStart = DateTime(2026, 6, 1); // a Monday
  const waves = ['baseline', 'overreach', 'peak', 'deload'];

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // The plan-provider seam reads the calendar week: pin the clock inside the
    // seeded plan (plan_start 2026-06-01) so the test is not a function of today.
    setTestClockTo(DateTime(2026, 6, 10, 10));
  });
  tearDown(() async {
    resetTestClock();
    await tearDownHiveForTests(tempDir);
  });

  Future<void> seedBlob(List<String> w) =>
      HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          for (final c in w) {'week_character': c},
        ],
      });

  Future<void> seedStart([DateTime? d]) => HiveService.instance.userBox
      .put('plan_start_date', (d ?? planStart).toIso8601String());

  final svc = WorkoutScheduleService.instance;

  group('weekModeLabel — the pure token mapper', () {
    test('the five tokens', () {
      expect(weekModeLabel('baseline'), 'Baseline');
      expect(weekModeLabel('overreach'), 'Overreach');
      expect(weekModeLabel('peak'), 'Peak');
      expect(weekModeLabel('deload'), 'Deload');
      expect(weekModeLabel('working'), 'Working');
    });
    test('normalised once: padded and mixed case', () {
      expect(weekModeLabel('  DeLoAd  '), 'Deload');
      expect(weekModeLabel('PEAK'), 'Peak');
    });
    test('empty / blank / null -> null (no word is invented)', () {
      expect(weekModeLabel(null), isNull);
      expect(weekModeLabel(''), isNull);
      expect(weekModeLabel('   '), isNull);
    });
    test('an unknown token is capitalised, never dropped', () {
      expect(weekModeLabel('taper'), 'Taper');
    });
  });

  group('currentWaveCharacters — crash-safe (moved from the phase-arc test)', () {
    test('4-week wave', () async {
      await seedBlob(waves);
      expect(svc.currentWaveCharacters(), waves);
    });
    test('no plan -> []', () {
      expect(svc.currentWaveCharacters(), isEmpty);
    });
    test('week_plans not a List -> []', () async {
      await HiveService.instance.workoutBox
          .put('current_plan', {'week_plans': 'oops'});
      expect(svc.currentWaveCharacters(), isEmpty);
    });
    test('non-Map blob -> []', () async {
      await HiveService.instance.workoutBox.put('current_plan', 'garbage');
      expect(svc.currentWaveCharacters(), isEmpty);
    });
    test('an entry without week_character -> empty slot, no crash', () async {
      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          {'week_character': 'baseline'},
          {'foo': 'bar'},
        ],
      });
      expect(svc.currentWaveCharacters(), ['baseline', '']);
    });
  });

  group('weekModeForRow — the row stamp wins, the blob is the fallback', () {
    test('a stamped row says its own word, whatever the blob says', () async {
      await seedStart();
      await seedBlob(waves);
      expect(
          svc.weekModeForRow({'week_character': 'peak', 'week': 1},
              planStart.add(const Duration(days: 1))),
          'Peak');
    });

    test('a lifted week is mixed: each row says its OWN word', () async {
      await seedStart();
      await seedBlob(waves);
      final d = planStart.add(const Duration(days: 22));
      expect(svc.weekModeForRow({'week_character': 'deload'}, d), 'Deload');
      expect(svc.weekModeForRow({'week_character': 'working'}, d), 'Working');
    });

    test('a row with NO stamp falls back to the blob word of its plan week', () async {
      await seedStart();
      await seedBlob(waves);
      for (var w = 0; w < 4; w++) {
        final d = planStart.add(Duration(days: w * 7 + 2));
        expect(svc.weekModeForRow({'week': w + 1}, d),
            weekModeLabel(waves[w]),
            reason: 'week ${w + 1}');
      }
    });

    test('no stamp, a date past week 4 (plan_start + 28), NO is_hold -> null, never the clamped week 4', () async {
      await seedStart();
      await seedBlob(waves);
      final d = planStart.add(const Duration(days: 28));
      expect(svc.weekModeForRow({'week': 5}, d), isNull);
      expect(svc.weekModeForRow(<String, dynamic>{}, d), isNull,
          reason: 'even a row with no week field: the raw week is 5');
    });

    test('is_hold alone (no week field, date inside plan weeks 1-4) -> null', () async {
      await seedStart();
      await seedBlob(waves);
      expect(
          svc.weekModeForRow(
              {'is_hold': true}, planStart.add(const Duration(days: 3))),
          isNull);
    });

    test('a row `week` above 4 alone (date inside plan weeks 1-4) -> null', () async {
      await seedStart();
      await seedBlob(waves);
      expect(
          svc.weekModeForRow(
              {'week': 6}, planStart.add(const Duration(days: 9))),
          isNull);
    });

    test('raw plan week 5+ with a LONG blob (extended plan) -> null, never blob week 5', () async {
      await seedStart();
      await seedBlob([...waves, 'baseline', 'overreach']);
      expect(
          svc.weekModeForRow(
              <String, dynamic>{}, planStart.add(const Duration(days: 28))),
          isNull);
    });

    test('no stamp on a hold row -> null (a hold row is a Peak copy, not week 4)', () async {
      await seedStart();
      await seedBlob(waves);
      expect(
          svc.weekModeForRow({'is_hold': true, 'week': 5},
              planStart.add(const Duration(days: 3))),
          isNull);
    });

    test('a hold row that carries the copied Peak/Deload stamp says it', () async {
      await seedStart();
      await seedBlob(waves);
      final d = planStart.add(const Duration(days: 30));
      expect(
          svc.weekModeForRow(
              {'is_hold': true, 'week': 5, 'week_character': 'peak'}, d),
          'Peak');
      expect(
          svc.weekModeForRow(
              {'is_hold': true, 'week': 8, 'week_character': 'deload'}, d),
          'Deload');
    });

    test('a date one day BEFORE plan_start -> null (raw week truncates to 1)', () async {
      await seedStart();
      await seedBlob(waves);
      expect(
          svc.weekModeForRow(
              {'week': 1}, planStart.subtract(const Duration(days: 1))),
          isNull);
    });

    test('null date / null row / no plan_start / short blob -> null', () async {
      await seedBlob(waves);
      expect(svc.weekModeForRow({'week': 1}, null), isNull);
      expect(svc.weekModeForRow(null, planStart), isNull);
      expect(svc.weekModeForRow({'week': 1}, planStart), isNull,
          reason: 'no plan_start');
      await seedStart();
      await seedBlob(['baseline']);
      expect(
          svc.weekModeForRow(
              {'week': 3}, planStart.add(const Duration(days: 15))),
          isNull,
          reason: 'blob shorter than the row week');
    });
  });

  group('the two Train constructors fill WorkoutDayData.weekMode', () {
    Map<String, dynamic> row(String date, int week, int dow, {String? wc}) => {
          'type': 'workout',
          'workout_name': 'Push A',
          'status': 'planned',
          'date': date,
          'week': week,
          'day_of_week': dow,
          'exercises': [
            {'name': 'Bench Press', 'sets': 3, 'reps': '8'}
          ],
          'warmup': <dynamic>[],
          'cooldown': <dynamic>[],
          if (wc != null) 'week_character': wc,
        };

    test('workoutDayForDate (hold hero + Home START): stamped row', () async {
      await seedStart();
      await seedBlob(waves);
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-17', row('2026-06-17', 3, 2, wc: 'peak'));
      expect(workoutDayForDate(DateTime(2026, 6, 17))!.weekMode, 'Peak');
    });

    test('workoutDayForDate: a stamp-less (template) row takes the blob word', () async {
      await seedStart();
      await seedBlob(waves);
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-17', row('2026-06-17', 3, 2));
      expect(workoutDayForDate(DateTime(2026, 6, 17))!.weekMode, 'Peak');
    });

    test('the week list (normal hero path) carries the word per row, incl. a stamp-less one', () async {
      await seedStart();
      await seedBlob(waves);
      final wb = HiveService.instance.workoutBox;
      await wb.put('current_plan', {
        'name': 'Foundation',
        'focus': 'x',
        'week_plans': [
          for (final c in waves) {'week_character': c},
        ],
      });
      await wb.put('schedule_2026-06-01', row('2026-06-01', 1, 0, wc: 'baseline'));
      await wb.put('schedule_2026-06-02', row('2026-06-02', 1, 1)); // stamp-less
      await wb.put('schedule_2026-06-08', row('2026-06-08', 2, 0, wc: 'overreach'));
      final c = ProviderContainer(
          overrides: [authUserIdTokenProvider.overrideWithValue('u')]);
      addTearDown(c.dispose);
      final plan = c.read(currentPlanProvider);
      expect(plan.hasPlan, isTrue);
      final w1 = plan.getWeek(1).where((d) => !d.isRest).toList();
      expect(w1.map((d) => d.weekMode).toSet(), {'Baseline'},
          reason: 'stamped Baseline + stamp-less falling back to blob week 1');
      expect(plan.getWeek(2).firstWhere((d) => !d.isRest).weekMode,
          'Overreach');
      expect(plan.getWeek(1).where((d) => d.isRest).every((d) => d.weekMode == null),
          isTrue);
    });
  });

  group('presence pins (the cards are not pumpable here)', () {
    test('Train hero: renders workout.weekMode, no phase-number map', () {
      final hero = _src('lib/features/train/screens/train/hero_cards.dart');
      expect(hero.contains('workout.weekMode'), isTrue);
      expect(hero.contains('Relaxed'), isFalse);
      expect(hero.contains('Capacity'), isFalse);
      expect(hero.contains('phaseMode'), isFalse);
    });
    test('Home: ONE call of the shared resolver feeds both cards; no phase map, no raw stamp read', () {
      final home = _src('lib/features/home/screens/home_screen.dart');
      expect('weekModeForRow('.allMatches(home).length, 1);
      expect(home.contains('Relaxed'), isFalse);
      expect(home.contains('phaseMode'), isFalse);
      expect(home.contains("['week_character']"), isFalse);
      expect(RegExp(r'workoutMode:\s*modeLabel').allMatches(home).length, 2);
    });
    test('both Train constructors call the resolver', () {
      final tp = _src('lib/features/train/providers/train_provider.dart');
      expect('.weekModeForRow('.allMatches(tp).length, 2);
    });
    test('the strip and its flags are gone', () {
      expect(File('lib/features/train/widgets/phase_arc_strip.dart').existsSync(), isFalse);
      final flags = _src('lib/shared/repositories/plan_engine/plan_engine_flags.dart');
      expect(flags.contains('disable_phase_arc'), isFalse);
      expect(flags.contains('disable_deload_reason_line'), isFalse);
      expect(_src('lib/features/train/screens/train/screen.dart').contains('PhaseArcStrip'), isFalse);
    });
    test('the deload evaluator no longer writes a reason key', () {
      final ev = _src('lib/core/services/deload_evaluator.dart');
      expect(ev.contains('deload_reason_phase_'), isFalse);
      expect(ev.contains('deloadDecisionReason'), isFalse);
    });
    test('the plan header has no progress bar; the hold sessions text stays', () {
      final ph = _src('lib/features/train/screens/train/plan_header.dart');
      expect(ph.contains('WardBar'), isFalse);
      expect(ph.contains(r'$completedDays / $totalWorkoutDays SESSIONS'), isTrue);
    });
  });
}
