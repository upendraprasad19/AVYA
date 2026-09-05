// Behavioral — ⑥ Batch 7-A (W3.2 phase arc): `currentWaveCharacters()` reads the
// materialized `current_plan` blob's `week_plans[].week_character` (snake_case per
// WeekPlan.toMap), crash-safe on absent/malformed blobs. `phaseArcProvider` is
// flag-gated. The flag FLIPPED LIVE 2026-09-05: the key is now
// `disable_phase_arc` (kill-switch) and the catch-block default is ON.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/phase_arc_strip.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_phase_arc');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  Future<void> seedPlan(List<String> waves) async {
    await HiveService.instance.workoutBox.put('current_plan', {
      'week_plans': [
        for (final w in waves) {'week_character': w},
      ],
    });
  }

  group('currentWaveCharacters — reads week_character from the blob', () {
    test('4-week wave → [baseline, overreach, peak, deload]', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      expect(WorkoutScheduleService.instance.currentWaveCharacters(),
          ['baseline', 'overreach', 'peak', 'deload']);
    });
    test('no plan → const []', () async {
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('malformed blob (week_plans not a List) → const []', () async {
      await HiveService.instance.workoutBox
          .put('current_plan', {'week_plans': 'oops'});
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('non-Map blob → const []', () async {
      await HiveService.instance.workoutBox.put('current_plan', 'garbage');
      expect(WorkoutScheduleService.instance.currentWaveCharacters(), isEmpty);
    });
    test('week entry missing week_character → empty-string slot (no crash)',
        () async {
      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          {'week_character': 'baseline'},
          {'foo': 'bar'},
        ],
      });
      expect(WorkoutScheduleService.instance.currentWaveCharacters(),
          ['baseline', '']);
    });
  });

  group('phaseArcProvider — LIVE, kill-switch reversible (flipped 2026-09-05)', () {
    test('default (no key) → renders, because the flag now defaults ON', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final arc = c.read(phaseArcProvider);
      expect(arc, isNotNull,
          reason: 'the flip inverted the default; absent key must mean ON');
      expect(arc!.waves, ['baseline', 'overreach', 'peak', 'deload']);
      expect(arc.currentWeek, inInclusiveRange(1, 4));
    });

    // THE MIRROR. Every pre-flip test proved the ON path; nothing proved the
    // kill-switch, and the kill-switch IS the entire rollback path.
    test('disable_phase_arc = true → null (the rollback path actually works)',
        () async {
      await HiveService.instance.configBox.put('disable_phase_arc', true);
      await seedPlan(['baseline', 'overreach', 'peak', 'deload']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider), isNull);
    });

    test('no plan → null (degenerate guard, unchanged by the flip)', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider), isNull);
    });

    // R11/F3: the highlight is clamped to 1..4, so a blob with fewer than 4
    // weeks renders a strip on which NO node can ever be marked "now" — every
    // node dim, which reads as a rendering fault rather than as missing data.
    test('short blob (3 weeks) → null, not an un-highlightable strip', () async {
      await seedPlan(['baseline', 'overreach', 'peak']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider), isNull);
    });

    // >= 4 deliberately matches deload_evaluator.dart:228. A 5-week blob is
    // still maintained by the evaluator, so the strip must not vanish for it —
    // it renders the first 4, which is all the clamp can address.
    test('over-long blob (5 weeks) → renders exactly the first 4', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'deload', 'working']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final arc = c.read(phaseArcProvider);
      expect(arc, isNotNull);
      expect(arc!.waves, ['baseline', 'overreach', 'peak', 'deload']);
      expect(arc.waves.length, 4);
    });

    // The lifted-deload state. `working` is written by deload_evaluator.dart:231
    // and that evaluator is LIVE, so this is a producible blob, not a synthetic.
    test('lifted deload (working in week 4) survives to the reader', () async {
      await seedPlan(['baseline', 'overreach', 'peak', 'working']);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(phaseArcProvider)!.waves.last, 'working');
    });
  });

  group('PhaseArcStrip.labelFor — all six states, normalised once', () {
    test('the five real tokens map to deliberate labels', () {
      expect(PhaseArcStrip.labelFor('baseline'), 'BASELINE');
      expect(PhaseArcStrip.labelFor('overreach'), 'OVERREACH');
      expect(PhaseArcStrip.labelFor('peak'), 'PEAK');
      expect(PhaseArcStrip.labelFor('deload'), 'DELOAD');
      // The fifth. Rendered correctly before it was mapped, via the fallback —
      // by luck, not decision.
      expect(PhaseArcStrip.labelFor('working'), 'WORKING');
    });

    // R10: the lookup trimmed while the fallback did not, so '  ' missed the
    // map, fell through UNTRIMMED, and '  '.isEmpty is FALSE — a dot with no
    // label. An isEmpty-only floor does not catch this; normalising once does.
    test('whitespace-only token floors to the em dash, not a blank node', () {
      expect(PhaseArcStrip.labelFor('   '), '—');
      expect(PhaseArcStrip.labelFor('\t'), '—');
    });

    test('empty token (synthesised by the reader) floors to the em dash', () {
      expect(PhaseArcStrip.labelFor(''), '—');
    });

    test('case and padding are normalised before lookup', () {
      expect(PhaseArcStrip.labelFor('  DeLoAd  '), 'DELOAD');
    });

    test('an unknown token still renders, upper-cased and trimmed', () {
      expect(PhaseArcStrip.labelFor(' taper '), 'TAPER');
    });
  });

  group('deload reason line — LIVE since 2026-09-06 (Unit B flip)', () {
    test('default ON → the strip asks for a reason', () {
      expect(PlanEngineFlags.deloadReasonLineEnabled, isTrue);
    });
    test('kill-switch set → OFF; deleting the key restores the default',
        () async {
      final cfg = HiveService.instance.configBox;
      await cfg.put('disable_deload_reason_line', true);
      expect(PlanEngineFlags.deloadReasonLineEnabled, isFalse);
      await cfg.delete('disable_deload_reason_line');
      expect(PlanEngineFlags.deloadReasonLineEnabled, isTrue);
    });
    test('the retired enable_ key is inert — it must not gate anything',
        () async {
      final cfg = HiveService.instance.configBox;
      await cfg.put('enable_deload_reason_line', false);
      expect(PlanEngineFlags.deloadReasonLineEnabled, isTrue);
      await cfg.delete('enable_deload_reason_line');
    });
  });
}
