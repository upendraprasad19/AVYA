// BEHAVIORAL TEST — hold_week_identity (FOB-1 / OI-60)
//
// Concept:  hold_week_identity
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
//           (stamps `is_hold` / `hold_ordinal` on each schedule_* row)
// Reader:   lib/core/services/workout_schedule_read_service.dart
//           weekIdentity() / activeHoldWeeks() / activeHoldOrdinalFor()
//           → weekIdentityProvider (train_provider) → the four surfaces that
//             print a week counter: home eyebrow, journey timeline,
//             phase roadmap header, share-as-video stamp.
//
// THE RULE UNDER TEST: "a hold suppresses the week number; Hn is the identity."
// getCurrentWeekNumber() clamps to [1,4] and a hold starts at plan_start+28, so
// every one of those surfaces printed week 4 to a holder at every ordinal,
// forever. The fix must NOT project `4 + ordinal` — that manufactures the value
// the UI ruled dishonest and demotes a phase-2 holder from program week 8 to 5
// (diagnose c9f4a2). So the hold arm asserts weekInPhase is NULL, not that it
// carries some other number.
//
// Every hold is materialized by the REAL holdWeek() writer, so these assertions
// fail if the writer's field names or cadence drift from what the identity
// reads — the recurring writer/reader-drift class.
//
// Ship-dark evidence (§4.12.4): the `flag OFF` group proves that with
// `enable_hold_weeks` OFF the identity is byte-identical to the pre-fix
// getCurrentWeekNumber() value EVEN WITH hold rows on disk, so every surface
// renders exactly as it did before this batch.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:icanbefitter/core/utils/hold_week_labels.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show holdStatusProvider, weekIdentityProvider;
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000060';

  // plan_start = Monday 2026-06-01; plan_end = +27 = Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));
  final hold1Start = DateTime(2026, 6, 29);

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('holdweekidentity_');
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

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: (week - 1) * 7 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': week,
            'phase': 1,
            'status': 'planned',
            'workout_name': 'Upper Body',
            'exercises': <Map<String, dynamic>>[
              {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0 + week},
            ],
          },
          source: WriteSource.schedSwap,
        );
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

  /// Materializes [count] consecutive holds, one per week from the Monday after
  /// plan_end — the real user path (open the app during each hold week). Leaves
  /// the test clock inside the LAST hold taken.
  Future<void> takeHolds(int count) async {
    for (var i = 0; i < count; i++) {
      setTestClockTo(hold1Start.add(Duration(days: 7 * i, hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
    }
  }

  group('flag ON — a hold suppresses the week number', () {
    test('weekIdentity carries the hold ordinal and NO week number', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);

      final id = read.weekIdentity();

      expect(id.isHolding, isTrue);
      expect(id.holdOrdinal, 1);
      expect(id.weekInPhase, isNull,
          reason: 'THE core FOB-1 assertion. A hold week sits outside the '
              'phase, so there is no honest week-in-phase for it. If this ever '
              'returns a number, some caller has reintroduced a projection.');
    });

    test('the identity NEVER projects 4 + ordinal at any ordinal', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(3);

      // Walk each hold week by date, not just today's.
      for (var ordinal = 1; ordinal <= 3; ordinal++) {
        final inHold = hold1Start.add(Duration(days: 7 * (ordinal - 1), hours: 10));
        setTestClockTo(inHold);
        final id = read.weekIdentity();
        expect(id.holdOrdinal, ordinal,
            reason: 'H$ordinal must be addressed by ordinal, not by the '
                'row-stamped week = 4 + ordinal');
        expect(id.weekInPhase, isNull,
            reason: 'a projected 4 + $ordinal would demote a phase-2 holder '
                'from program week 8 to 5 — the c9f4a2 drift');
      }
    });

    test('a NON-hold day inside the plan window still takes the week arm',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);

      // Week 3 of the plan — hold rows exist on disk, but today is not one.
      setTestClockTo(planStart.add(const Duration(days: 15, hours: 10)));
      final id = read.weekIdentity();

      expect(id.isHolding, isFalse);
      expect(id.holdOrdinal, isNull);
      expect(id.weekInPhase, 3,
          reason: 'the presence of hold rows must not hijack a normal week');
    });

    test('a day AFTER the hold elapses falls back to the clamped week arm',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);

      // Two weeks past hold 1 — no hold row covers this date.
      setTestClockTo(hold1Start.add(const Duration(days: 14, hours: 10)));
      final id = read.weekIdentity();

      expect(id.isHolding, isFalse);
      expect(id.weekInPhase, 4,
          reason: 'outside any hold the clamp is the pre-fix behaviour, '
              'unchanged');
    });
  });

  group('flag OFF — the ship-dark byte-identical negative control', () {
    test('weekIdentity equals the raw clamp EVEN WITH hold rows on disk',
        () async {
      // Materialize real holds with the flag ON, then turn it OFF — the exact
      // shape of a user who held before an operator reverted the kill-switch.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);
      await HiveService.instance.configBox.delete('enable_hold_weeks');

      // Clock is still inside hold 2.
      final id = read.weekIdentity();

      expect(id.isHolding, isFalse,
          reason: 'the flag gate must fire before any is_hold row is read');
      expect(id.holdOrdinal, isNull);
      expect(id.weekInPhase, read.getCurrentWeekNumber(),
          reason: 'byte-identical to the pre-fix value — this IS the '
              '§4.12.4 ship-dark evidence for every surface that reads it');
    });

    test('activeHoldWeeks / activeHoldOrdinalFor are the ONE gate', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);
      await HiveService.instance.configBox.delete('enable_hold_weeks');

      expect(read.activeHoldWeeks(), isEmpty);
      expect(read.activeHoldOrdinalFor(nowWall()), isNull);
      // The RAW readers still see the rows — proving the gate lives in the
      // active* pair and not in the row readers, so a test can still exercise
      // the row contract directly.
      expect(read.holdWeeks(), hasLength(2),
          reason: 'holdWeeks() is deliberately ungated; if this ever returns '
              'empty the gate has been pushed down into the row reader and '
              'the raw contract is no longer testable');
      expect(read.holdOrdinalForDate(nowWall()), 2);
    });
  });

  group('provider seam', () {
    test('weekIdentityProvider mirrors the service while holding', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final id = container.read(weekIdentityProvider);

      expect(id.isHolding, isTrue);
      expect(id.holdOrdinal, 1);
      expect(id.weekInPhase, isNull);
    });

    test('weekIdentityProvider is inert with the flag OFF', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      await HiveService.instance.configBox.delete('enable_hold_weeks');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final id = container.read(weekIdentityProvider);

      expect(id.isHolding, isFalse);
      expect(id.weekInPhase, read.getCurrentWeekNumber());
    });

    test(
        'holdStatusProvider still gates correctly after delegating to active*',
        () async {
      // Guards the refactor that MOVED the flag check out of the provider and
      // into the service: if activeHoldWeeks() ever stops gating, this is the
      // test that reddens rather than the provider silently going live.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      await HiveService.instance.configBox.delete('enable_hold_weeks');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final status = container.read(holdStatusProvider);

      expect(status.isHolding, isFalse);
      expect(status.holds, isEmpty);
      expect(status.todayHoldOrdinal, isNull);
    });
  });

  // ── WIRING, BEHAVIOURALLY (Hermes 2026-08-20 P1-B) ────────────────────────
  //
  // The presence-only group below could not fail on the defect that mattered.
  // Hermes mutated `profile_provider` to pass `holdOrdinal: null` and the FULL
  // 4757-test suite stayed green; the same held for the home eyebrow, the recap
  // video and the journey label, singly and together. Its grep tokens
  // (`weekIdentityProvider`, `journeyWeekLabel(`, `profileWeekSegment(`) all
  // SURVIVE that defect, because the defect is in the ARGUMENT, not the call —
  // one mutation kept `ref.read(weekIdentityProvider).holdOrdinal` literally
  // present while sending null, and passed.
  //
  // Rule 21 requires a behavioral test to fail when the runtime path breaks
  // even if the source text is intact. These do.
  group('wiring — identity actually REACHES the consumers', () {
    test('userStatsProvider carries the hold ordinal through a real container',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final stats = container.read(userStatsProvider);

      expect(stats.holdOrdinal, 2,
          reason: 'the hold identity must survive the trip through '
              'UserStatsNotifier.build. Passing a literal null here — the exact '
              'Hermes mutation — left the whole suite green, because the only '
              'coverage was a grep for a token that the mutation preserved.');
      expect(stats.isHolding, isTrue);
    });

    test('userStatsProvider reports NO hold when the flag is off', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      await HiveService.instance.configBox.delete('enable_hold_weeks');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final stats = container.read(userStatsProvider);
      expect(stats.holdOrdinal, isNull);
      expect(stats.isHolding, isFalse);
      expect(stats.currentWeek, read.getCurrentWeekNumber(),
          reason: 'ship-dark: byte-identical to pre-batch with the flag off, '
              'even with real hold rows on disk');
    });

    test('the PERSISTED row never renders its 4+ordinal stamp', () async {
      // The row-derived surfaces (Home today-card, day-detail sheet) read
      // `row['week']`, which holdWeek() stamps as 4+n. Drive the REAL writer,
      // then push its real output through the real formatters.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(3);

      final box = HiveService.instance.workoutBox;
      final holdRows = box.keys
          .where((k) => k.toString().startsWith('schedule_'))
          .map((k) => box.get(k))
          .whereType<Map>()
          .where((r) => r['is_hold'] == true)
          .toList();

      expect(holdRows, isNotEmpty,
          reason: 'takeHolds(3) must have materialized hold rows');

      for (final row in holdRows) {
        final ordinal = row['hold_ordinal'] as int;
        final stamped = row['week'] as int;

        expect(stamped, 4 + ordinal,
            reason: 'pins the writer contract this guards against: if the '
                'stamp ever stops being 4+ordinal, these labels need rechecking');

        expect(todayCardWeekLabel(row), 'Holding · H$ordinal');
        expect(dayDetailWeekLabel(row), 'HOLDING · H$ordinal');
        expect(todayCardWeekLabel(row), isNot(contains('$stamped')));
        expect(dayDetailWeekLabel(row), isNot(contains('$stamped')));
      }
    });
  });

  // FORBIDDEN-PATTERN control for the two row-derived surfaces.
  //
  // Honest about what this is: a NEGATIVE source assertion, not a render
  // assertion. It is here because the three behavioural tests above still could
  // not catch a revert of the CALL SITE — verified by mutation: restoring
  // `workoutMode: 'Week ${schedule?['week']}'` in home_screen, or
  // `'WEEK ${schedule?['week']}'` in day_detail_sheet, left every one of them
  // green. That is the same shape as the gap Hermes found, one layer over, and
  // pretending otherwise would repeat the mistake.
  //
  // A negative grep on the FORBIDDEN token is strictly stronger than the
  // positive grep it replaces: a positive grep passes as long as the desired
  // call survives ANYWHERE in the file, which is what let mutation 13b keep
  // `ref.read(weekIdentityProvider).holdOrdinal` present while sending null. A
  // reverted call site must re-introduce a raw `['week']` read to render the
  // stamp, and that is what this catches.
  //
  // It does NOT prove what the widgets render. A third spelling that reaches
  // the stamp some other way would slip it. The real closure is a pumped-widget
  // test for both surfaces; neither has one today and neither is currently
  // pumpable without a full Riverpod+Hive home harness.
  //
  // Comments are stripped first — the sibling tests in this batch all do, and
  // this file's own explanatory comment above names `['week']` twice, which
  // would satisfy a raw-text match and silently neuter the check (Hermes L8
  // P2-3 flagged exactly that against the Remotion assertion).
  group('row-derived surfaces must not read the 4+ordinal stamp directly', () {
    String stripDartComments(String src) => src
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    const rowSurfaces = <String>[
      'lib/features/home/screens/home_screen.dart',
      'lib/features/home/widgets/day_detail_sheet.dart',
    ];

    for (final path in rowSurfaces) {
      test('${path.split('/').last} delegates to the row formatters', () {
        final code = stripDartComments(File(path).readAsStringSync());

        expect(code.contains("['week']"), isFalse,
            reason: '$path must not read the raw `week` field: holdWeek() '
                'stamps it 4+ordinal, so rendering it prints "Week 5" to a '
                'holder while the eyebrow says "HOLDING · H1" (Hermes P1-A). '
                'Use todayCardWeekLabel(row) / dayDetailWeekLabel(row), which '
                'take the ROW so the projected number is not reachable.');

        expect(
            RegExp(r'(todayCardWeekLabel|dayDetailWeekLabel)\(')
                .hasMatch(code),
            isTrue,
            reason: '$path must still call a row formatter');
      });
    }
  });

  group('surface wiring (PRESENCE-ONLY — cannot catch a behavioural revert)',
      () {
    // The four surfaces are thin ternaries over weekIdentity, so their VALUE
    // logic is covered above. These guard the wiring itself: a surface that
    // silently reverts to getCurrentWeekNumber() would print week 4 to a holder
    // again while every behavioural assertion above still passed.
    const surfaces = <String, String>{
      'lib/features/home/screens/home_screen.dart': 'weekIdentityProvider',
      // MUST be the provider, not the singleton `weekIdentity()` call this
      // started as — see the B-pass P1 note at the call site. A revert to the
      // singleton silently un-links userStatsProvider from the hold write.
      'lib/features/profile/providers/profile_provider.dart':
          'ref.watch(weekIdentityProvider)',
      'lib/features/profile/screens/profile/journey_timeline.dart':
          'journeyWeekLabel(',
      'lib/features/profile/screens/profile/profile_content.dart':
          'profileWeekSegment(',
      'lib/features/train/screens/phase_roadmap_screen.dart':
          'weekIdentityProvider',
      'lib/core/utils/hold_week_labels.dart': 'journeyPhaseOneMilestone',
      'lib/features/profile/screens/reports_screen.dart': 'weekIdentityProvider',
    };

    for (final entry in surfaces.entries) {
      test('${entry.key.split('/').last} reads the honest identity', () {
        final body = File(entry.key).readAsStringSync();
        expect(body.contains(entry.value), isTrue,
            reason: '${entry.key} must source its week label from the shared '
                'identity, not from a second getCurrentWeekNumber() call');
      });
    }

    test('the Remotion recap composition accepts a hold ordinal', () {
      final body =
          File('remotion/src/components/WeeklyRecapVideo.tsx').readAsStringSync();
      expect(body.contains('holdOrdinal'), isTrue);
      expect(body.contains('HOLD H'), isTrue,
          reason: 'the video stamped "WEEK 4 RECAP" for every hold; the '
              'composition needs the hold branch or the Dart-side prop is '
              'silently dropped');
    });
  });
}
