// 8300e1: the coach's plateau insight runs on the plan engine's ONE plateau
// scan (`PlateauScan.flatCompoundLifts`): best-set Epley e1RM per session,
// >= 3 sessions over >= 28 days inside 63, within 5 %, exact library names,
// readiness fatigue means recover, and (founder D7) the lift's last session is
// within 14 days. Real Hive `exlog_*` rows through `PatternDetector.analyze`.
// Plan docs/plans/pr-card-unify.md section 7.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box wb, hb, cb;
  final fixedToday = DateTime(2026, 6, 1, 12);
  String dk(DateTime d) => istDateStr(d);
  var seq = 0;

  /// One session per (weight, reps, days-ago).
  Future<void> seed(String name, List<(num, int, int)> sessions) async {
    for (final (w, r, ago) in sessions) {
      final d = fixedToday.subtract(Duration(days: ago));
      await wb.put('exlog_${dk(d)}_${seq++}', {
        'exercise_name': name,
        'date': dk(d),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': w, 'reps_completed': r}
        ],
      });
    }
  }

  Future<void> seedReadiness(int n, {required bool flagged}) async {
    for (var i = 1; i <= n; i++) {
      final d = fixedToday.subtract(Duration(days: i));
      await hb.put('readiness_${dk(d)}', {
        'date': dk(d),
        'sleep': 0,
        'soreness': flagged ? 2 : 0,
        'energy': 0,
        'level': flagged ? 'yellow' : 'green',
      });
    }
  }

  List<CoachingInsight> plateaus() => [
        for (final i in PatternDetector.instance.analyze())
          if (i.patternId.startsWith('plateau_')) i,
      ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('coach_plateau');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put(
          (r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    wb = HiveService.instance.workoutBox;
    hb = HiveService.instance.healthBox;
    cb = HiveService.instance.configBox;
    setTestClockTo(fixedToday);
  });

  tearDownAll(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await hb.clear();
    await cb.clear();
  });

  test('(a) a flat bench, 3 sessions over 5 weeks: one insight, exact name, exact text',
      () async {
    // 40 x 8 every time: e1RM 40 x (1 + 8/30) = 50.67 -> "~50.5".
    await seed('Barbell Bench Press', [(40, 8, 40), (40, 8, 20), (40, 8, 5)]);
    final got = plateaus();
    expect(got, hasLength(1));
    final i = got.single;
    expect(i.patternId, 'plateau_barbell bench press');
    expect(i.severity, InsightSeverity.high);
    expect(i.pushWorthy, isTrue);
    expect(i.userMessage,
        'Barbell Bench Press: no real progress over your last 5 weeks '
        '(est. 1RM ~50.5 kg). Time to adjust!');
    expect(i.coachNotice,
        'Barbell Bench Press est. 1RM flat at ~50.5kg across 3 sessions '
        'over the last 5 weeks.');
  });

  test('(b) same weight, reps rising 6 -> 8 -> 10: progress, no insight',
      () async {
    await seed('Barbell Bench Press', [(40, 6, 40), (40, 8, 20), (40, 10, 5)]);
    expect(plateaus(), isEmpty);
  });

  test('(c) exact names: a flat Dumbbell Bench is named, a rising Barbell Bench is not',
      () async {
    await seed('Dumbbell Bench Press', [(20, 8, 40), (20, 8, 20), (20, 8, 5)]);
    await seed('Barbell Bench Press', [(40, 5, 40), (45, 5, 20), (50, 5, 5)]);
    expect(plateaus().single.patternId, 'plateau_dumbbell bench press');
  });

  test('(d) bench flat, deadlift rising: only the bench', () async {
    await seed('Barbell Bench Press', [(40, 8, 40), (40, 8, 20), (40, 8, 5)]);
    await seed('Deadlift', [(80, 5, 40), (90, 5, 20), (100, 5, 5)]);
    expect([for (final i in plateaus()) i.patternId],
        ['plateau_barbell bench press']);
  });

  test('(e) a decline over 5 % is not a plateau', () async {
    await seed('Barbell Bench Press', [(50, 5, 40), (45, 5, 20), (40, 5, 5)]);
    expect(plateaus(), isEmpty);
  });

  test('(f) bodyweight and timed rows only: nothing', () async {
    for (final ago in const [40, 20, 5]) {
      final d = fixedToday.subtract(Duration(days: ago));
      await wb.put('exlog_${dk(d)}_pu$ago', {
        'exercise_name': 'Push Up',
        'date': dk(d),
        'logging_type': 'bodyweight_reps',
        'sets': [
          {'weight_kg': 0, 'reps_completed': 15}
        ],
      });
    }
    expect(plateaus(), isEmpty);
  });

  test('(g) readiness fatigue: recover, no plateau; readiness OFF: the insight',
      () async {
    await seed('Barbell Bench Press', [(40, 8, 40), (40, 8, 20), (40, 8, 5)]);
    await seedReadiness(4, flagged: true);
    expect(plateaus(), isEmpty);
    await cb.put('disable_readiness', true);
    expect(plateaus(), hasLength(1));
  });

  test('(h) two sessions are not enough', () async {
    await seed('Barbell Bench Press', [(40, 8, 40), (40, 8, 5)]);
    expect(plateaus(), isEmpty);
  });

  test('(i) a 21-day span is not enough', () async {
    await seed('Barbell Bench Press', [(40, 8, 26), (40, 8, 15), (40, 8, 5)]);
    expect(plateaus(), isEmpty);
  });

  test('(j) last session exactly 14 days ago counts; 15 days ago does not (D7)',
      () async {
    await seed('Barbell Bench Press', [(40, 8, 50), (40, 8, 30), (40, 8, 14)]);
    expect(plateaus(), hasLength(1));
    await wb.clear();
    await seed('Barbell Bench Press', [(40, 8, 51), (40, 8, 30), (40, 8, 15)]);
    expect(plateaus(), isEmpty);
  });

  test('(k) weeks = whole weeks of the flat span: 40 days -> 5, 49 days -> 7',
      () async {
    await seed('Barbell Bench Press', [(40, 8, 45), (40, 8, 20), (40, 8, 5)]);
    expect(plateaus().single.userMessage, contains('last 5 weeks'));
    await wb.clear();
    await seed('Barbell Bench Press', [(40, 8, 54), (40, 8, 20), (40, 8, 5)]);
    expect(plateaus().single.userMessage, contains('last 7 weeks'));
  });

  test('(l) the longest flat span wins; an equal span goes to the first name',
      () {
    FlatLift lift(String n, int span) => FlatLift(
        name: n, sessions: 3, spanDays: span, bestE1rm: 50, lastDate: '2026-06-01');
    expect(
        PatternDetector.pickPlateauLift(
            [lift('Barbell Bench Press', 35), lift('Deadlift', 49)]).name,
        'Deadlift');
    expect(
        PatternDetector.pickPlateauLift(
            [lift('Deadlift', 35), lift('Barbell Bench Press', 35)]).name,
        'Barbell Bench Press');
  });

  test('(l2) end to end: two flat lifts, the longer span is named', () async {
    await seed('Barbell Bench Press', [(40, 8, 40), (40, 8, 20), (40, 8, 5)]);
    await seed('Deadlift', [(80, 5, 54), (80, 5, 20), (80, 5, 5)]);
    expect(plateaus().single.patternId, 'plateau_deadlift');
  });

  test('(m) the best e1RM is shown to the nearest 0.5 kg', () {
    String msg(double e) => PatternDetector.plateauInsightFor(FlatLift(
            name: 'Deadlift',
            sessions: 3,
            spanDays: 35,
            bestE1rm: e,
            lastDate: '2026-06-01'))
        .userMessage;
    expect(msg(100.2), contains('~100 kg'));
    expect(msg(100.3), contains('~100.5 kg'));
    expect(msg(100.8), contains('~101 kg'));
  });

  test('(n) sessions older than 63 days are outside the window', () async {
    // In window: 40 x 8 on days 50, 30, 5 (flat). Outside: a 60 x 8 at day 70
    // that would break the flatness if it counted.
    await seed('Barbell Bench Press',
        [(60, 8, 70), (40, 8, 50), (40, 8, 30), (40, 8, 5)]);
    final got = plateaus();
    expect(got, hasLength(1));
    expect(got.single.coachNotice, contains('across 3 sessions'));
  });
}
