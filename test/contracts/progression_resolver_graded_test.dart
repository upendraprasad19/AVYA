// Behavioral regression — W2.1 (Batch 3b-ii): graded double progression in
// ProgressionResolver, behind `enable_graded_progression` (default OFF, ship
// dark). Rep-range-aware banding + 2-consecutive-below-range back-off gate +
// beginner auto-linear window. Sessions seeded at a ≤7d gap so ⑦a decay is 1.0
// (base == logged weight) and the band math is clean.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/progression_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final fixedNow = DateTime(2026, 7, 13, 12, 0);
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_graded_prog');
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
    setTestClockTo(fixedNow);
  });

  tearDown(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
  });

  // One exlog session: [reps] @ [weight]kg, [daysAgo] IST-days back. [suffix]
  // lets two rows share a calendar day (same-day dupe test).
  Future<void> seedExlog(String name,
      {required double weight,
      required int reps,
      required int daysAgo,
      String suffix = ''}) async {
    final dateStr = istDateStr(fixedNow.subtract(Duration(days: daysAgo)));
    await HiveService.instance.workoutBox.put('exlog_${dateStr}_$name$suffix', {
      'exercise_name': name,
      'date': dateStr,
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': weight, 'reps_completed': reps}
      ],
    });
  }

  Future<void> setProfile(String experience, {int? onboardedDaysAgo}) async {
    final p = <String, dynamic>{'fitness_experience': experience};
    if (onboardedDaysAgo != null) {
      p['onboarding_completed_at'] =
          fixedNow.subtract(Duration(days: onboardedDaysAgo)).toUtc().toIso8601String();
    }
    await HiveService.instance.userBox.put('profile', p);
  }

  Future<void> enableGraded() async =>
      HiveService.instance.configBox.put('enable_graded_progression', true);

  double? resolved(String name, {String? repRange}) => ProgressionResolver.resolve(
        phase: 2,
        exerciseNames: [name],
        repRanges: {name: repRange},
      )[name];

  group('rep-range-aware banding (flag ON, non-beginner)', () {
    setUp(() async {
      await enableGraded();
      await setProfile('intermediate', onboardedDaysAgo: 400);
    });

    test('reps ≥ hi → progress', () async {
      await seedExlog('Bench', weight: 100, reps: 13, daysAgo: 3);
      expect(resolved('Bench', repRange: '8-12'), 102.5); // +2.5 upper
    });

    test('within range (reps=10 in 8-12) → HOLD (old fixed rule would progress)',
        () async {
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 3);
      expect(resolved('Bench', repRange: '8-12'), 100.0);
    });

    test('one below-range session → HOLD (never back off on one off day)',
        () async {
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 6); // prior: in-range
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 2); // recent: below
      expect(resolved('Bench', repRange: '8-12'), 100.0);
    });

    test('two consecutive DISTINCT-day below-range → back off', () async {
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 5);
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 2);
      // −1.25 upper back-off → 98.75, rounded to 1 decimal by resolve() → 98.8.
      expect(resolved('Bench', repRange: '8-12'), 98.8);
    });

    test('two SAME-day below-range logs → HOLD (dedupe by calendar day)',
        () async {
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 2, suffix: '_a');
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 2, suffix: '_b');
      expect(resolved('Bench', repRange: '8-12'), 100.0);
    });

    test('no/invalid rep range → verbatim fixed-10/5 semantics', () async {
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 3);
      expect(resolved('Bench', repRange: null), 102.5); // 10 ≥ 10 → progress
    });
  });

  group('beginner auto-linear window (flag ON)', () {
    setUp(enableGraded);

    test('beginner + <120d training-age → always progress (mid-range reps)',
        () async {
      await setProfile('beginner', onboardedDaysAgo: 30);
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 3); // below-range
      expect(resolved('Bench', repRange: '8-12'), 102.5); // linear → progress
    });

    test('beginner + ≥120d → normal range rule (below-range, 1 session → hold)',
        () async {
      await setProfile('beginner', onboardedDaysAgo: 200);
      await seedExlog('Bench', weight: 100, reps: 7, daysAgo: 3);
      expect(resolved('Bench', repRange: '8-12'), 100.0);
    });

    test('null onboarding_completed_at → not-linear, range rule, NO empty map',
        () async {
      await setProfile('beginner'); // no onboarding_completed_at
      await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 3);
      expect(resolved('Bench', repRange: '8-12'), 100.0); // range hold, not null
    });
  });

  test('kill-switch OFF (default) → verbatim fixed-10/5 (byte-identical)',
      () async {
    // No enable flag; reps=10 in "8-12" → OFF fixed rule progresses (≥10),
    // ON would HOLD → proves the flag genuinely gates.
    await setProfile('intermediate', onboardedDaysAgo: 400);
    await seedExlog('Bench', weight: 100, reps: 10, daysAgo: 3);
    expect(resolved('Bench', repRange: '8-12'), 102.5);
  });
}
