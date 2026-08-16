// BEHAVIORAL TEST — streaks (weekly-streak identity during a hold + the
// custom_template/logged day-count asymmetry)
//
// Concept:  streaks
// Writer:   lib/features/train/providers/train_provider.dart
//           ActiveWorkoutNotifier.completeWorkout — the weekly-streak block
//           (last_streak_week + current_streak_weeks + the healthBox 'streaks'
//           row keyed streak_<Monday>), via the extracted
//           resolveStreakWeekState()
// Reader:   the same block's `as int?` cast on last_streak_week;
//           sync/sync_workout.dart _syncStreaks (upsert onConflict
//           user_id,week_start)
//
// Pins TWO defects (diagnose <6hex>):
//
//  1. FOB-2 — getCurrentWeekNumber() clamps to [1,4] and a hold starts at
//     plan_start+28, so the dedup gate was `4 != 4` (streak froze for the whole
//     hold) and the row key was always week 4's Monday (every hold completion
//     overwrote that one row; cloud streaks is UNIQUE(user_id, week_start)).
//  2. The `planned`/`completedCount` asymmetry — `planned` filtered
//     `type == 'workout'` while the numerator filtered nothing, so at 100%
//     template conversion planned==0 and the caller's `planned > 0` gates
//     suppressed BOTH the increment and the row write.
//
// Every case calls resolveStreakWeekState() directly against a REAL
// WorkoutScheduleReadService over seeded Hive, with holds materialized by the
// REAL holdWeek() writer. It deliberately does NOT drive completeWorkout(),
// which needs full startWorkout state and fans out to Sync/Rank/Badge — the
// same reason resolveSessionDate was extracted. Asserting on the returned
// record is what makes these able to redden at all: an earlier draft of this
// batch asserted on values written only inside completeWorkout and was
// therefore unwritable.
//
// This is the FIRST test coverage this block has ever had — no test in the repo
// drove it before.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show resolveStreakWeekState;
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000047';

  // plan_start = Monday 2026-06-01; plan_end = +27 = Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));
  final hold1Start = DateTime(2026, 6, 29); // Monday after plan_end

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('holdstreak_identity_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    resetTestClock();
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Seeds one `schedule_<date>` row. [type] defaults to a normal workout day.
  Future<void> seedDay(
    DateTime date, {
    String type = 'workout',
    String status = 'planned',
    int week = 1,
  }) async {
    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'type': type,
        'date': formatDateKey(date),
        'week': week,
        'phase': 1,
        'status': status,
        'workout_name': 'Upper Body',
        'exercises': <Map<String, dynamic>>[
          {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0},
        ],
      },
      source: WriteSource.schedSwap,
    );
  }

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        await seedDay(planStart.add(Duration(days: (week - 1) * 7 + d)),
            week: week);
      }
    }
  });

  tearDown(() async {
    resetTestClock();
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList()) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  /// Materializes [count] consecutive holds via the REAL writer, one per week.
  Future<void> takeHolds(int count) async {
    await HiveService.instance.configBox.put('enable_hold_weeks', true);
    for (var i = 0; i < count; i++) {
      setTestClockTo(hold1Start.add(Duration(days: 7 * i, hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
    }
  }

  /// Calls the subject for a completion performed on [on], holding at [ordinal].
  ({int streakWeekId, DateTime? weekStartDate, int planned, int completedCount})
      resolve(DateTime on, {int? ordinal}) => resolveStreakWeekState(
            readSvc: read,
            planStart: planStart,
            holdOrdinal: ordinal,
            workoutDate: on,
          );

  Future<void> markCompleted(DateTime date) async {
    final box = HiveService.instance.workoutBox;
    final key = 'schedule_${formatDateKey(date)}';
    final row = Map<String, dynamic>.from(box.get(key) as Map);
    row['status'] = 'completed';
    await box.put(key, row);
  }

  group('hold week identity — derived BY DATE, never clamped, never 4+ordinal',
      () {
    test('contiguous hold 1 → id 5, row key = the hold Monday', () async {
      await takeHolds(1);
      final r = resolve(hold1Start.add(const Duration(hours: 10)), ordinal: 1);

      // Reddens if the hold arm re-adds .clamp(1,4) — it would report 4.
      expect(r.streakWeekId, 5,
          reason: 'hold 1 sits at plan_start+28 = date-week 5; a clamped '
              'value (4) collides with the real week 4 and freezes the streak');
      expect(r.weekStartDate, hold1Start);
    });

    test('LATE RETURN: ordinal 1 at date-week 8 → id 8, not 5', () async {
      // The user returns three weeks late, so holdWeek() backdates into THIS
      // calendar week — leaving a genuine date gap. hold_ordinal is still 1.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      final lateStart = DateTime(2026, 7, 20); // plan_start + 49 → week 8
      setTestClockTo(lateStart.add(const Duration(hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();

      final r = resolve(lateStart.add(const Duration(hours: 10)), ordinal: 1);

      // Reddens on `4 + ordinal`, which would report 5 — the ordinal is a
      // LABEL, not a date offset.
      expect(r.streakWeekId, 8,
          reason: 'ordinal 1 but date-week 8; identity must follow the DATE');
      expect(r.weekStartDate, lateStart);
    });

    test('three consecutive holds → 5, 6, 7: distinct, all > 4, never -1',
        () async {
      await takeHolds(3);
      final ids = <int>[
        for (var i = 0; i < 3; i++)
          resolve(hold1Start.add(Duration(days: 7 * i, hours: 10)),
                  ordinal: i + 1)
              .streakWeekId,
      ];

      // Reddens if the hold arm is clamped: all three collapse to 4, so the
      // caller's `id != lastStreakWeek` gate fires once and then freezes.
      expect(ids, [5, 6, 7]);
      expect(ids.toSet(), hasLength(3), reason: 'each hold is its own week');
      expect(ids.every((i) => i > 4), isTrue);
      expect(ids.contains(-1), isFalse, reason: '-1 is the init sentinel');
    });

    test('each hold gets its OWN streaks row key, not week 4\'s Monday',
        () async {
      await takeHolds(2);
      final k1 = resolve(hold1Start.add(const Duration(hours: 10)), ordinal: 1)
          .weekStartDate;
      final k2 = resolve(hold1Start.add(const Duration(days: 7, hours: 10)),
              ordinal: 2)
          .weekStartDate;

      // Reddens on restoring `plan_start + 7*(id-1)` with a clamped id: both
      // become 2026-06-22 (week 4's Monday) and the second upsert OVERWRITES
      // the first, because cloud streaks is UNIQUE(user_id, week_start).
      expect(formatDateKey(k1!), '2026-06-29');
      expect(formatDateKey(k2!), '2026-07-06');
      expect(k1, isNot(k2));
    });

    test('hold day source is non-empty — never getWeek(unclamped id)',
        () async {
      await takeHolds(1);
      final r = resolve(hold1Start.add(const Duration(hours: 10)), ordinal: 1);

      // Reddens if the hold arm sources days via getWeek(streakWeekId):
      // getWeek is a plan_start-offset date walk, so getWeek(5) for a hold that
      // is NOT on the plan grid returns [] → planned==0 → the caller's
      // `planned > 0` gates suppress BOTH the increment and the row write,
      // which is strictly worse than the freeze this fixes.
      expect(r.planned, greaterThan(0),
          reason: 'a hold week has 7 materialized training days');
      expect(r.planned, 7);
    });

    test('row key is the MONDAY even when the hold has no Monday row',
        () async {
      // Delete the SOURCE week's Monday BEFORE holding, so holdWeek() skips
      // that offset and the hold week genuinely lacks a Monday row. Without
      // this ordering the case is vacuous — holdWeek writes all 7 offsets.
      final peakMonday = planStart.add(const Duration(days: 14));
      await HiveService.instance.workoutBox
          .delete('schedule_${formatDateKey(peakMonday)}');
      await takeHolds(1);

      final r = resolve(hold1Start.add(const Duration(days: 1, hours: 10)),
          ordinal: 1);

      // HoldWeekInfo.weekStart is the first SURVIVING hold date (the Tuesday);
      // the row key must still be the Monday. Reddens on sourcing the key from
      // HoldWeekInfo.weekStart.
      final info = read.holdWeeks().firstWhere((h) => h.ordinal == 1);
      expect(formatDateKey(info.weekStart), '2026-06-30',
          reason: 'guard: the Monday row really is absent');
      expect(formatDateKey(r.weekStartDate!), '2026-06-29',
          reason: 'the row key is normalizeToMonday(workoutDate)');
    });
  });

  group('day counts — one predicate on BOTH sides of the ratio', () {
    // The non-hold arm reads getCurrentWeekNumber(), which derives from the
    // CLOCK, not from `workoutDate` — so every case here must pin the clock
    // inside week 1 or the resolver reads week 4's untouched setUp rows.
    final inWeek1 = planStart.add(const Duration(days: 3, hours: 10));

    test('custom_template blackout: an all-template week counts 5, not 0',
        () async {
      // 5 training days + 2 rest, every training day converted to a user
      // template, all completed — 100% adherence.
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: d));
        final isRest = d >= 5;
        await seedDay(date,
            type: isRest ? 'rest' : 'custom_template',
            status: isRest ? 'rest' : 'completed');
      }
      setTestClockTo(inWeek1);
      final r = resolve(inWeek1);

      // Reddens on restoring `type == 'workout'` for planned: it yields 0,
      // and the caller gates BOTH the streak increment and the streaks-row
      // write on `planned > 0` — so a PRO user with a fully self-built week
      // and perfect adherence got zero credit and no cloud row.
      expect(r.planned, 5, reason: 'custom_template days are training days');
      expect(r.completedCount, 5);
      expect(r.completedCount >= (r.planned * 0.8).ceil(), isTrue,
          reason: '100% adherence must clear the 80% gate');
    });

    test("a `logged` day counts as training", () async {
      // The shape markCompleted's no-prior-schedule branch and the restore
      // synthesize path write; sync_workout's own comment says a logged row
      // "counts as a workout day in the streak walk".
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: d));
        await seedDay(date,
            type: d == 0 ? 'logged' : (d >= 5 ? 'rest' : 'workout'),
            status: d >= 5 ? 'rest' : 'planned');
      }
      setTestClockTo(inWeek1);
      final r = resolve(inWeek1);

      // Reddens on an inclusion predicate (workout | custom_template): it
      // drops the logged day and reports 4.
      expect(r.planned, 5,
          reason: 'logged is a training day, not a rest day');
    });

    test('a completed REST row inflates neither side', () async {
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: d));
        final isRest = d >= 5;
        await seedDay(date,
            type: isRest ? 'rest' : 'workout',
            // The restore path sets status='completed' on ANY existing row,
            // rest included — so this is representable, not hypothetical.
            status: 'completed');
      }
      setTestClockTo(inWeek1);
      final r = resolve(inWeek1);

      // Reddens on dropping the numerator's type filter: completedCount
      // becomes 7 > planned 5, and `workouts_completed > workouts_planned`
      // ships to the cloud streaks row.
      expect(r.planned, 5);
      expect(r.completedCount, 5);
      expect(r.completedCount, lessThanOrEqualTo(r.planned));
    });
  });

  group('the ordinal driving the COUNTS is re-derived from workoutDate', () {
    test('a STALE injected ordinal does not populate another week\'s counts',
        () async {
      // B-pass finding 1. holdStatusProvider derives todayHoldOrdinal from
      // nowWall() at provider-BUILD time and is cached until
      // currentPlanProvider invalidates — which completeWorkout does only at
      // its last statement. A session left foregrounded across a Sunday→Monday
      // rollover therefore hands in an ordinal for the PREVIOUS hold week while
      // workoutDate is already in the next one.
      await takeHolds(2);

      // Make the two hold weeks distinguishable: complete 3 days of hold 1,
      // none of hold 2. Without re-derivation the row would be keyed to hold
      // 2's Monday but carry hold 1's completed count.
      for (var d = 0; d < 3; d++) {
        await markCompleted(hold1Start.add(Duration(days: d)));
      }

      final inHold2 = hold1Start.add(const Duration(days: 7, hours: 10));
      setTestClockTo(inHold2);
      // Inject the STALE ordinal 1 while performing a workout inside hold 2.
      final r = resolve(inHold2, ordinal: 1);

      // Reddens on passing the injected `holdOrdinal` to
      // holdWeekSessionProgress instead of the re-derived one: completedCount
      // would be 3 (hold 1's) against a row keyed to hold 2's Monday.
      expect(formatDateKey(r.weekStartDate!), '2026-07-06',
          reason: 'the key follows workoutDate');
      expect(r.streakWeekId, 6, reason: 'the identity follows workoutDate');
      expect(r.completedCount, 0,
          reason: 'the counts must describe the SAME week as the key — '
              'hold 2 has no completed days');
      expect(r.planned, 7);
    });

    test('workoutDate outside any hold week falls back to the clamped arm',
        () async {
      // The mirror case: a non-null injected ordinal but workoutDate is not a
      // hold day (the hold elapsed / the user rolled out of it).
      await takeHolds(1);
      final inPlanWeek1 = planStart.add(const Duration(days: 2, hours: 10));
      setTestClockTo(inPlanWeek1);

      final r = resolve(inPlanWeek1, ordinal: 1);

      expect(r.streakWeekId, lessThanOrEqualTo(4),
          reason: 'not a hold day → clamped arm, never a hold identity');
    });
  });

  group('flag OFF / non-hold arm stays CLAMPED', () {
    test('hold rows on disk but holdOrdinal null → non-hold arm, id <= 4',
        () async {
      // Materialize holds, then simulate the flag being OFF: holdStatusProvider
      // returns HoldStatusData.empty, so the caller passes holdOrdinal: null.
      await takeHolds(2);
      await HiveService.instance.configBox.put('enable_hold_weeks', false);

      final r = resolve(hold1Start.add(const Duration(hours: 10)));

      // Reddens if the function branches on PlanEngineFlags or
      // holdOrdinalForDate() instead of the injected ordinal — it would take
      // the hold arm and report 5 despite the flag being off.
      expect(r.streakWeekId, lessThanOrEqualTo(4),
          reason: 'flag OFF must reach the clamped arm');
    });

    test('REGRESSION: plan_end rolled +1 week (redoWeek4) keeps id 4', () async {
      // redoWeek4 extends ONLY plan_end — it never writes plan_start — so a
      // user who rolled week 4 sits at a true date-index of 5 while
      // getCurrentWeekNumber() reports 4. Materialize that state directly.
      await MigratedKey.write('plan_end_date',
          planEnd.add(const Duration(days: 7)).toIso8601String());
      for (int d = 0; d < 7; d++) {
        await seedDay(hold1Start.add(Duration(days: d)), week: 5);
      }

      // Pin the clock INSIDE the rolled week so the true date-index is exactly
      // 5 — that is the state where an unclamped read diverges from a clamped
      // one. Left to the wall clock the index would be arbitrary.
      final inRolledWeek = hold1Start.add(const Duration(hours: 10));
      setTestClockTo(inRolledWeek);
      final r = resolve(inRolledWeek);

      // Reddens if the non-hold arm uses the UNCLAMPED index: it would report
      // 5 and key the row on 2026-06-29 instead of 2026-06-22 — a live
      // regression for a flag-OFF user.
      expect(r.streakWeekId, 4,
          reason: 'the non-hold arm must stay clamped to [1,4]');
      expect(formatDateKey(r.weekStartDate!), '2026-06-22',
          reason: "week 4's Monday, exactly as before this fix");
    });
  });

  group('wiring (PRESENCE-ONLY — cannot catch a behavioural revert)', () {
    test('the streak block branches via holdStatusProvider, not the flag', () {
      final src = File('lib/features/train/providers/train_provider.dart')
          .readAsStringSync();
      // Strip comments so prose mentioning a symbol cannot satisfy the check.
      final stripped = src
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
          .join('\n');

      expect(stripped.contains('resolveStreakWeekState('), isTrue);
      expect(stripped.contains('ref.read(holdStatusProvider)'), isTrue);

      // The single flag-OFF guarantee point is holdStatusProvider; the streak
      // path must not re-derive hold state from the flag or from Hive.
      // ⚠️ Extract from the end of the PARAMETER LIST, not from the signature.
      // The obvious spelling — indexOf('\n}', fnStart) — stops at `}) {` (the
      // named-parameter list's closing brace, which sits at column 0), so
      // `body` was only the six-line signature and every isFalse assertion
      // below passed VACUOUSLY: a window that contains no code contains no
      // violation either. Caught only because an isTrue assertion was added
      // later and could not pass against an empty window. If you change this
      // extraction, re-check that the isFalse assertions can still fail.
      final fnStart = stripped.indexOf('resolveStreakWeekState({');
      expect(fnStart, greaterThan(-1), reason: 'the helper must exist');
      final sigEnd = stripped.indexOf('}) {', fnStart);
      expect(sigEnd, greaterThan(fnStart));
      final fnEnd = stripped.indexOf('\n}', sigEnd + 4);
      final body = stripped.substring(sigEnd, fnEnd);
      // Guard the guard: the window must be the real body, not a sliver.
      expect(body.length, greaterThan(400),
          reason: 'body window looks truncated — the isFalse assertions below '
              'would pass vacuously');
      expect(body.contains('holdWeekSessionProgress('), isTrue,
          reason: 'sanity: the window really does span the hold arm');
      expect(body.contains('PlanEngineFlags'), isFalse,
          reason: 'the helper must never read the flag directly — the flag-OFF '
              'guarantee lives solely in holdStatusProvider');

      // NOTE: this deliberately does NOT forbid holdOrdinalForDate(. An earlier
      // draft asserted its ABSENCE, on the theory that the ordinal should be
      // purely injected. B-pass finding 1 showed that was wrong: the injected
      // ordinal can be stale relative to workoutDate across a midnight
      // rollover, so the counts MUST be driven by a re-derived ordinal. The
      // real invariant — flag OFF never reaches the hold arm — is pinned
      // behaviourally by the 'flag OFF / non-hold arm stays CLAMPED' group,
      // which is stronger than any source grep. Kept as a comment because
      // silently dropping an assertion is how a guard gets lost.
      expect(body.contains('effectiveOrdinal'), isTrue,
          reason: 'the counts must come from the re-derived ordinal');
    });
  });
}
