// Piece B (d7a3e5) — the freeze zero rides the REAL PRO advance and only after
// the phase counter commit succeeded (review round 1, findings 1 and 3).
//
// Harness copied from pro_phase_advance_behavioral_test.dart (real plan
// generation, a real WidgetRef). The clock is pinned to Thu 2026-11-12 10:00
// IST; the old window ended Sun 2026-09-27 (a 6-week blank gap).
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/gap_policy.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/services/pro_phase_advance.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;
  const testUser = 'ad0a11ce-3c3c-4141-9999-c0ffeec0ffee';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('lapse_gap_freeze_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
        File('assets/data/exercise_library.json').readAsStringSync()) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put(
          (r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.configBox.clear();
    SyncService.pausedForSimulation = true;
    setTestClockTo(DateTime.utc(2026, 11, 12, 4, 30));
  });

  tearDown(() {
    resetTestClock();
    SyncService.pausedForSimulation = false;
  });

  Future<void> seed({int freezes = 3}) async {
    await MigratedKey.write('isPro', true);
    await MigratedKey.write(
        'expiresAt', DateTime(2027, 6, 1).toIso8601String());
    await MigratedKey.write(
        'plan_start_date', DateTime(2026, 8, 31).toIso8601String());
    await MigratedKey.write(
        'plan_end_date', DateTime(2026, 9, 27).toIso8601String());
    await UserRepository.instance.saveProfile({
      'primary_goal': 'build_muscle',
      'equipment_access': 'full_gym',
      'days_per_week': 4,
      'fitness_experience': 'intermediate',
    });
    await UserRepository.instance.saveProgress({
      'current_phase': 1,
      'streak_freezes_available': freezes,
      'streak_freeze_used_dates': <String>[],
      'streak_freezes_last_refill': '2026-11-09',
    });
  }

  Future<({WidgetRef ref, ProviderContainer container})> capture(
      WidgetTester tester) async {
    final c = Completer<({WidgetRef ref, ProviderContainer container})>();
    await tester.pumpWidget(ProviderScope(child: _Capture(onCapture: c.complete)));
    await tester.pump();
    return (await tester.runAsync(() => c.future))!;
  }

  testWidgets('committed advance after a 6-week blank gap zeroes the freezes',
      (tester) async {
    await tester.runAsync(seed);
    final cap = await capture(tester);
    late bool generated;
    await tester.runAsync(() async {
      generated = await runProPhaseAdvance(cap.ref);
    });
    final p = UserRepository.instance.getProgress()!;
    expect(generated, isTrue, reason: 'precondition: a phase was generated');
    expect(p['current_phase'], 2, reason: 'precondition: the commit landed');
    expect(p['streak_freezes_available'], 0);
  });

  testWidgets('KILL SWITCH: the same advance leaves the freezes alone',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await HiveService.instance.configBox.put(kDisableLapseGapPolicyKey, true);
    });
    final cap = await capture(tester);
    await tester.runAsync(() async => runProPhaseAdvance(cap.ref));
    expect(UserRepository.instance.getProgress()!['streak_freezes_available'], 3);
  });

  testWidgets('a DECLINED commit (higher phase landed mid-generation) keeps '
      'the freezes', (tester) async {
    await tester.runAsync(seed);
    final cap = await capture(tester);
    await tester.runAsync(() async {
      var done = false;
      final advancing = runProPhaseAdvance(cap.ref).whenComplete(() => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse,
          reason: 'precondition: the write must land DURING generation');
      await UserRepository.instance.updateProgress({'current_phase': 5});
      await advancing;
    });
    final p = UserRepository.instance.getProgress()!;
    expect(p['current_phase'], 5, reason: 'precondition: commit was declined');
    expect(p['streak_freezes_available'], 3,
        reason: 'a declined advance must not zero anyone\'s freezes');
  });

  Map<dynamic, dynamic> gradProfile() => {
        'primary_goal': 'build_muscle',
        'equipment_access': 'full_gym',
        'days_per_week': 4,
        'fitness_experience': 'intermediate',
      };

  testWidgets('graduation unlock after a 6-week blank gap zeroes the freezes '
      'and starts THIS Monday (fresh start)', (tester) async {
    await tester.runAsync(seed);
    final cap = await capture(tester);
    late GraduationAdvanceResult r;
    await tester.runAsync(() async {
      r = await runGraduationPhaseAdvance(
          ref: cap.ref,
          profile: gradProfile(),
          nextPhase: 2,
          repeat: false,
          stopwatch: Stopwatch());
    });
    expect(r.outcome, GraduationAdvanceOutcome.committed,
        reason: 'precondition: the graduation advance committed');
    expect(WorkoutScheduleReadService.instance.getPlanStartDate(),
        DateTime(2026, 11, 9));
    expect(UserRepository.instance.getProgress()!['streak_freezes_available'], 0);
  });

  testWidgets('graduation right after the phase ended (no blank gap) keeps '
      'the freezes', (tester) async {
    await tester.runAsync(() async {
      await seed();
      await MigratedKey.write(
          'plan_end_date', DateTime(2026, 11, 8).toIso8601String());
    });
    final cap = await capture(tester);
    await tester.runAsync(() async {
      await runGraduationPhaseAdvance(
          ref: cap.ref,
          profile: gradProfile(),
          nextPhase: 2,
          repeat: false,
          stopwatch: Stopwatch());
    });
    expect(WorkoutScheduleReadService.instance.getPlanStartDate(),
        DateTime(2026, 11, 9));
    expect(UserRepository.instance.getProgress()!['streak_freezes_available'], 3);
  });

  testWidgets('graduation with a DECLINED commit keeps the freezes',
      (tester) async {
    await tester.runAsync(seed);
    final cap = await capture(tester);
    late GraduationAdvanceResult r;
    await tester.runAsync(() async {
      var done = false;
      final advancing = runGraduationPhaseAdvance(
              ref: cap.ref,
              profile: gradProfile(),
              nextPhase: 2,
              repeat: false,
              stopwatch: Stopwatch())
          .whenComplete(() => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse,
          reason: 'precondition: the write must land DURING generation');
      await UserRepository.instance.updateProgress({'current_phase': 5});
      r = await advancing;
    });
    expect(r.outcome, isNot(GraduationAdvanceOutcome.committed),
        reason: 'precondition: the commit was declined');
    expect(UserRepository.instance.getProgress()!['streak_freezes_available'], 3);
  });
}

class _Capture extends ConsumerStatefulWidget {
  const _Capture({required this.onCapture});
  final void Function(({WidgetRef ref, ProviderContainer container})) onCapture;
  @override
  ConsumerState<_Capture> createState() => _CaptureState();
}

class _CaptureState extends ConsumerState<_Capture> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCapture((ref: ref, container: ProviderScope.containerOf(context)));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
