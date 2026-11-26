// SoT `nutrition_target_history`: the ONE writer
// `TargetHistoryService.reconcile` (called after every profile put, at the
// day rollover, after a restore and on History-screen open) -> the readers
// `TargetHistoryService.read` / `targetFor` (plan
// docs/plans/nutrition-history.md 5.2, U1-U10).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/target_history_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../sync/sync_domain_skip_harness.dart';

TargetEntry _e(String from, int cal,
        {int pro = 140, int carbs = 300, int fat = 70, String s = 'balanced'}) =>
    TargetEntry(
        from: from,
        calories: cal,
        protein: pro,
        carbs: carbs,
        fat: fat,
        strategy: s,
        atMs: 1);

Map<String, dynamic> _pack(int cal, {int pro = 140, int carbs = 300, int fat = 70}) =>
    {
      'daily_calories': cal,
      'protein_grams': pro,
      'carb_grams': carbs,
      'fat_grams': fat,
      'current_weight_kg': 80.0,
    };

void main() {
  group('reconciled (pure)', () {
    final today = _e('2026-11-25', 2500);

    test('first entry is appended', () {
      expect(TargetHistoryService.reconciled(const [], today).single.from,
          '2026-11-25');
    });

    test('unchanged targets on a later day add nothing', () {
      final entries = [_e('2026-11-01', 2500)];
      expect(identical(TargetHistoryService.reconciled(entries, today), entries),
          isTrue);
    });

    test('each of the five value fields alone makes a new entry', () {
      final base = [_e('2026-11-01', 2500)];
      final variants = [
        _e('2026-11-25', 2501),
        _e('2026-11-25', 2500, pro: 141),
        _e('2026-11-25', 2500, carbs: 301),
        _e('2026-11-25', 2500, fat: 71),
        _e('2026-11-25', 2500, s: 'keto'),
      ];
      for (final v in variants) {
        expect(TargetHistoryService.reconciled(base, v).length, 2,
            reason: 'changed: ${v.toMap()}');
      }
    });

    test('a second change the same day replaces, never appends', () {
      final entries = [_e('2026-11-01', 2400), _e('2026-11-25', 2500)];
      final next =
          TargetHistoryService.reconciled(entries, _e('2026-11-25', 2600));
      expect(next.map((e) => e.calories), [2400, 2600]);
    });

    test(
        'changing back to the previous targets the same day KEEPS the day, '
        'with the reverted numbers and the newer at_ms', () {
      // The cloud merge cannot delete: a removed entry would leave the
      // reverted numbers (2500) in the cloud for good.
      final entries = [_e('2026-11-01', 2400), _e('2026-11-25', 2500)];
      final back = TargetEntry(
          from: '2026-11-25',
          calories: 2400,
          protein: 140,
          carbs: 300,
          fat: 70,
          strategy: 'balanced',
          atMs: 9);
      final next = TargetHistoryService.reconciled(entries, back);
      expect(next.map((e) => (e.from, e.calories, e.atMs)),
          [('2026-11-01', 2400, 1), ('2026-11-25', 2400, 9)]);
      // The day after, equal targets still write nothing.
      expect(
          identical(
              TargetHistoryService.reconciled(next, _e('2026-11-26', 2400)),
              next),
          isTrue);
    });

    test('entries dated after today are dropped, never obeyed (B-pass F2)', () {
      // The device clock was ahead when the 2027 entry was written.
      final entries = [_e('2026-11-01', 2400), _e('2027-06-01', 2000)];
      final changed =
          TargetHistoryService.reconciled(entries, _e('2026-11-25', 2500));
      expect(changed.map((e) => (e.from, e.calories)),
          [('2026-11-01', 2400), ('2026-11-25', 2500)]);
      // Even with nothing new to record the future entry goes.
      final same =
          TargetHistoryService.reconciled(entries, _e('2026-11-25', 2400));
      expect(same.map((e) => e.from), ['2026-11-01']);
      expect(identical(same, entries), isFalse);
      // Only a future entry: today's targets replace it.
      expect(
          TargetHistoryService.reconciled(
              [_e('2027-06-01', 2000)], today).single.from,
          '2026-11-25');
    });

    test('the cap drops the oldest entries', () {
      final entries = [
        for (var i = 0; i < TargetHistoryService.maxEntries; i++)
          _e('2020-01-01', 1000 + i),
      ];
      final next = TargetHistoryService.reconciled(entries, today);
      expect(next.length, TargetHistoryService.maxEntries);
      expect(next.first.calories, 1001);
      expect(next.last.calories, 2500);
    });
  });

  group('mergedHistories (pure; the rule merge_target_history applies)', () {
    TargetEntry at(String from, int cal, int atMs,
            {int pro = 140, int carbs = 300, int fat = 70, String s = 'balanced'}) =>
        TargetEntry(
            from: from,
            calories: cal,
            protein: pro,
            carbs: carbs,
            fat: fat,
            strategy: s,
            atMs: atMs);
    List<(String, int, int)> brief(List<TargetEntry> l) =>
        [for (final e in l) (e.from, e.calories, e.atMs)];
    const today = '2026-11-25';
    final merge = TargetHistoryService.mergedHistories;

    test('union by day, sorted; a short side deletes nothing', () {
      final local = [at('2026-11-20', 2500, 5)];
      final cloud = [at('2026-10-01', 2300, 1), at('2026-11-01', 2400, 2)];
      expect(brief(merge(local, cloud, today)), [
        ('2026-10-01', 2300, 1),
        ('2026-11-01', 2400, 2),
        ('2026-11-20', 2500, 5),
      ]);
      expect(brief(merge(cloud, local, today)), brief(merge(local, cloud, today)));
    });

    test('same day: the greater at_ms wins from either side', () {
      final older = [at('2026-11-20', 2500, 5)];
      final newer = [at('2026-11-20', 2600, 6)];
      expect(brief(merge(older, newer, today)), [('2026-11-20', 2600, 6)]);
      expect(brief(merge(newer, older, today)), [('2026-11-20', 2600, 6)]);
    });

    test('equal at_ms: each later field decides, the same way from both sides',
        () {
      final pairs = [
        (at('2026-11-20', 2500, 5), at('2026-11-20', 2600, 5)),
        (at('2026-11-20', 2500, 5, pro: 140), at('2026-11-20', 2500, 5, pro: 141)),
        (at('2026-11-20', 2500, 5, carbs: 300), at('2026-11-20', 2500, 5, carbs: 301)),
        (at('2026-11-20', 2500, 5, fat: 70), at('2026-11-20', 2500, 5, fat: 71)),
        (at('2026-11-20', 2500, 5, s: 'balanced'), at('2026-11-20', 2500, 5, s: 'keto')),
        (at('2026-11-20', 2500, 5, s: 'low_carb'), at('2026-11-20', 2500, 5, s: 'lowcarb')),
      ];
      for (final (lo, hi) in pairs) {
        expect(merge([lo], [hi], today).single.toMap(), hi.toMap());
        expect(merge([hi], [lo], today).single.toMap(), hi.toMap());
      }
      // A LOWER later field never beats a greater at_ms.
      final late = at('2026-11-20', 2000, 6, pro: 1, carbs: 1, fat: 1, s: 'a');
      final early = at('2026-11-20', 9000, 5, pro: 900, carbs: 900, fat: 900, s: 'z');
      expect(merge([early], [late], today).single.toMap(), late.toMap());
    });

    test('entries dated after today are dropped from both sides; today is kept',
        () {
      final local = [at('2026-11-25', 2500, 5), at('2026-11-26', 2600, 6)];
      final cloud = [at('2026-11-27', 2700, 7), at('2026-11-24', 2400, 4)];
      expect(brief(merge(local, cloud, today)),
          [('2026-11-24', 2400, 4), ('2026-11-25', 2500, 5)]);
    });

    test('the cap keeps the NEWEST days', () {
      final cloud = [
        for (var i = 0; i < TargetHistoryService.maxEntries; i++)
          at('2024-${(1 + i ~/ 28).toString().padLeft(2, '0')}-'
              '${(1 + i % 28).toString().padLeft(2, '0')}', 2000 + i, i),
      ];
      final next = merge([at('2026-11-20', 9999, 1)], cloud, today);
      expect(next.length, TargetHistoryService.maxEntries);
      expect(next.last.calories, 9999);
      expect(next.first.calories, 2001, reason: 'the oldest day went');
    });

    test('nothing new returns the SAME local instance (no write)', () {
      final local = [at('2026-11-01', 2400, 2), at('2026-11-20', 2500, 5)];
      expect(identical(merge(local, const [], today), local), isTrue);
      expect(identical(merge(local, [at('2026-11-20', 2500, 5)], today), local),
          isTrue);
      expect(identical(merge(local, [at('2026-11-20', 2400, 4)], today), local),
          isTrue, reason: 'an older cloud entry for the day loses');
      expect(identical(merge(local, [at('2026-11-20', 2500, 6)], today), local),
          isFalse, reason: 'only at_ms differs: still a change');
      expect(
          identical(merge(local, [at('2026-11-20', 2500, 5, s: 'keto')], today),
              local),
          isFalse);
    });
  });

  group('targetFor / parse (pure)', () {
    final entries = [_e('2026-10-10', 2400), _e('2026-11-01', 2600)];

    test('before, on and after the entries', () {
      final before = TargetHistoryService.targetFor('2026-10-09', entries)!;
      expect((before.entry.calories, before.assumed), (2400, true));
      final onFirst = TargetHistoryService.targetFor('2026-10-10', entries)!;
      expect((onFirst.entry.calories, onFirst.assumed), (2400, false));
      final between = TargetHistoryService.targetFor('2026-10-31', entries)!;
      expect(between.entry.calories, 2400);
      final onSecond = TargetHistoryService.targetFor('2026-11-01', entries)!;
      expect(onSecond.entry.calories, 2600);
      expect(TargetHistoryService.targetFor('2027-01-01', entries)!.entry.calories,
          2600);
      expect(TargetHistoryService.targetFor('2026-11-01', const []), isNull);
    });

    test('malformed stored entries are skipped, the rest sorted', () {
      final parsed = TargetHistoryService.parse([
        _e('2026-11-01', 2600).toMap(),
        'junk',
        {'from': '2026-10-10'},
        {'from': 'bad', 'calories': 1, 'protein': 1, 'carbs': 1, 'fat': 1},
        _e('2026-10-10', 2400).toMap(),
      ]);
      expect(parsed.map((e) => e.calories), [2400, 2600]);
      expect(TargetHistoryService.parse('not a list'), isEmpty);
    });
  });

  group('writer -> reader on real Hive', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      h.server.clear();
      DietStrategyFlags.debugEnabledOverride = false;
    });
    tearDown(() async {
      DietStrategyFlags.debugEnabledOverride = null;
      TargetHistoryService.debugFailNext = null;
      await h.tearDown();
    });

    final today = istDateStr(nowWall());
    final svc = ProfileWriteService.instance;

    test('a profile write records the targets, dated today, once', () async {
      await svc.updateProfile(_pack(2540));
      var entries = TargetHistoryService.read();
      expect(entries.single.toMap()..remove('at_ms'), {
        'from': today,
        'calories': 2540,
        'protein': 140,
        'carbs': 300,
        'fat': 70,
        'strategy': 'balanced',
      });
      await svc.patchProfile({'height_cm': 178});
      entries = TargetHistoryService.read();
      expect(entries.length, 1, reason: 'no target changed');
    });

    test('a goal change after an older entry adds one; changing back keeps the day',
        () async {
      await HiveService.instance.userBox
          .put(TargetHistoryService.boxKey, [_e('2026-01-05', 2540).toMap()]);
      await svc.updateProfile(_pack(2540));
      expect(TargetHistoryService.read().length, 1);

      await svc.patchProfile({'daily_calories': 2200, 'protein_grams': 150});
      expect(TargetHistoryService.read().map((e) => (e.from, e.calories)),
          [('2026-01-05', 2540), (today, 2200)]);

      await svc.patchProfile({'daily_calories': 2300});
      expect(TargetHistoryService.read().map((e) => e.calories), [2540, 2300],
          reason: 'second change the same day replaces');

      await svc.patchProfile({'daily_calories': 2540, 'protein_grams': 140});
      expect(TargetHistoryService.read().map((e) => (e.from, e.calories)),
          [('2026-01-05', 2540), (today, 2540)],
          reason: 'the day keeps an entry with the reverted numbers');
    });

    test('patchProfileWith records too; a weigh-in that moves no target does not',
        () async {
      await svc.updateProfile(_pack(2540));
      await HiveService.instance.userBox
          .put(TargetHistoryService.boxKey, [_e('2026-01-05', 2540).toMap()]);
      await svc.patchProfileWith((p) => {'current_weight_kg': 80.3},
          stillOwner: () => true);
      expect(TargetHistoryService.read().length, 1);
      await svc.patchProfileWith((p) => {'fat_grams': 75},
          stillOwner: () => true);
      expect(TargetHistoryService.read().last.fat, 75);
    });

    test('a restore-shaped write (skipSync) records the restored targets, '
        'replacing a same-day stub entry', () async {
      await svc.updateProfile({
        'current_weight_kg': 80.0,
        'height_cm': 178.0,
        'gender': 'male',
      });
      expect(TargetHistoryService.read().single.calories, 2602,
          reason: 'stub profile: recomputed from its inputs');
      await svc.updateProfile(_pack(2100), skipSync: true);
      expect(TargetHistoryService.read().single.calories, 2100);
    });

    test('a profile that only resolves to the fallback records nothing; the '
        'first real profile then does', () async {
      await svc.updateProfile({'name': 'x'});
      expect(TargetHistoryService.read(), isEmpty);
      await svc.updateProfile(_pack(2540));
      expect(TargetHistoryService.read().length, 1);
    });

    test('a zero calorie target is not recorded (B-pass F7)', () async {
      await svc.updateProfile(_pack(0));
      expect(TargetHistoryService.read(), isEmpty);
      await svc.updateProfile(_pack(2540));
      expect(TargetHistoryService.read().single.calories, 2540);
    });

    test('a future-dated stored entry no longer blocks recording', () async {
      await HiveService.instance.userBox
          .put(TargetHistoryService.boxKey, [_e('2999-01-01', 1800).toMap()]);
      await svc.updateProfile(_pack(2540));
      expect(TargetHistoryService.read().map((e) => (e.from, e.calories)),
          [(today, 2540)]);
    });

    test('kill switch: nothing is written', () async {
      await HiveService.instance.configBox
          .put(TargetHistoryService.killSwitch, true);
      await svc.updateProfile(_pack(2540));
      expect(TargetHistoryService.read(), isEmpty);
    });

    test('a failing reconcile never fails the profile write', () async {
      TargetHistoryService.debugFailNext = StateError('boom');
      await svc.updateProfile(_pack(2540));
      expect((HiveService.instance.userBox.get('profile') as Map)['daily_calories'],
          2540);
      expect(TargetHistoryService.read(), isEmpty);
      expect(TargetHistoryService.reconcile(), isTrue,
          reason: 'the next trigger heals it');
    });

    test('two profile writes back to back leave one consistent entry', () async {
      final a = svc.updateProfile(_pack(2540));
      final b = svc.patchProfile({'daily_calories': 2700});
      await Future.wait([a, b]);
      expect(TargetHistoryService.read().single.calories, 2700);
    });

    test('a strategy flag flip with no profile write is recorded by the '
        'post-restore trigger and by the screen-open trigger', () async {
      await HiveService.instance.userBox.put('profile', _pack(2540));
      expect(TargetHistoryService.read(), isEmpty,
          reason: 'a direct put has no trigger');
      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      expect(TargetHistoryService.read().single.calories, 2540);

      await HiveService.instance.userBox.put('profile', _pack(2000));
      expect(NutritionRepository.instance.reconcileTargetHistory(), isTrue);
      expect(TargetHistoryService.read().single.calories, 2000);
      expect(NutritionRepository.instance.reconcileTargetHistory(), isFalse);
    });

    test('no open session: reconcile and read do nothing and do not throw',
        () async {
      await svc.updateProfile(_pack(2540));
      await h.tearDown();
      expect(TargetHistoryService.reconcile(), isFalse);
      expect(TargetHistoryService.read(), isEmpty);
    });
  });
}
