// OI-45 finding 5 / Unit 3c + task #41 (2026-08-01) — BEHAVIORAL contract for
// the phase-advance write path.
//
// WHAT THIS EXISTS TO CATCH. `current_phase` is the one progress field with NO
// monotonic guard anywhere: `UserRepository.saveProgress` guards
// `deployments_complete` (`max(prior, phase-1)`) and writes `current_phase`
// straight through. All three advance paths compute their target BEFORE a real,
// slow plan-generation `await` and write it after:
//
//   pro_phase_advance.dart      read :72   → generate :90-101 → write :117
//   graduation_screen.dart      read :568  → generate :663    → write :707
//   simulation_service.dart     read :536  → generate :549    → write :565
//
// So a concurrent advancer landing inside that window — the splash's unawaited
// `advanceProPhaseIfExpired`, the Home/Train card CTA, `PhaseProgressReconciler`'s
// boot heal (which can jump more than +1), the dev sim — used to be silently
// overwritten by a stale, LOWER number.
//
// WHY IT DID NOT EXIST BEFORE (B-pass finding 4 of diagnose d5c8a3, task #41).
// Unit 3a fixed the sibling bug (a whole-map `saveProgress(staleSnapshot)`
// clobbering OTHER fields) but its regression test proved the bug PATTERN using
// `UserRepository`'s own primitives — it never called the production functions.
// The blocker was narrower than that finding recorded: driving real plan
// generation in a test is already established (see
// `repeat_content_scheduling_test.dart`, which seeds the real
// `assets/data/exercise_library.json` and calls the real `generateAndSchedule`).
// The actual blocker was the auth seam — `advanceProPhaseIfExpired` calls
// `HiveUserSession.ensureOpenedForCurrentSession()`, which reads
// `SupabaseService.instance.currentUser` and returns null when Supabase was
// never initialised, so the function returned `false` before reaching anything
// worth testing. Unit 3c hoists those two lines into the public wrapper, leaving
// `runProPhaseAdvance` (@visibleForTesting) as the drivable core. Same
// "extract the testable core, keep the shell thin" shape as
// `PhaseProgressReconciler.reconciledPhase` and
// `WorkoutScheduleReadService.isPhaseExpiredFrom`.
//
// HOW EACH TEST DISCRIMINATES (rule 21 — a test that cannot fail is not a
// regression test):
//   • Group D's `current_phase` assertion FAILS against the pre-fix code, which
//     wrote `currentPhase + 1` from the pre-await read (2, demoting the
//     interposed 3).
//   • Group D's interposed-field assertion FAILS if Unit 3a's
//     `updateProgress(delta)` fix is ever reverted to `saveProgress(wholeMap)`.
//   • Group C fails if the shared lock stops excluding a second entrant.
//
// COVERAGE HONESTY. `simulation_service._maybeAdvancePhase` is kDebugMode
// dev-harness code and `graduation_screen._onPro` is a full screen behind a
// router; neither is driven end-to-end here. Their WRITE semantics are covered
// because they now route through the same `commitPhaseAdvance` that Group B
// tests behaviorally; Group E pins that routing by source. That is presence
// coverage for the wiring and behavioral coverage for the writer — stated
// plainly rather than implied (`feedback_source_grep_false_confidence`).
//
// Run: flutter test test/contracts/pro_phase_advance_behavioral_test.dart

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
    tempDir = Directory.systemTemp.createTempSync('pro_phase_advance_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);

    // Real exercise library — plan generation must actually produce a plan, the
    // same harness repeat_content_scheduling_test.dart established.
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
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
  });

  // ───────────────────────── A — pure decision ──────────────────────────────

  group('phaseAdvanceTarget (pure, monotonic)', () {
    test('normal +1 advance writes the intended phase', () {
      expect(phaseAdvanceTarget(livePhase: 1, intendedPhase: 2), 2);
      expect(phaseAdvanceTarget(livePhase: 7, intendedPhase: 8), 8);
    });

    test('live == intended → null (someone already advanced us there)', () {
      expect(phaseAdvanceTarget(livePhase: 2, intendedPhase: 2), isNull);
    });

    test('live > intended → null — THE demotion case', () {
      // PhaseProgressReconciler can heal 1 → 3 in one write; an advance that
      // read 1 pre-await must not drag the counter back to 2.
      expect(phaseAdvanceTarget(livePhase: 3, intendedPhase: 2), isNull);
      expect(phaseAdvanceTarget(livePhase: 12, intendedPhase: 5), isNull);
    });
  });

  // ─────────────────── B — commitPhaseAdvance against Hive ──────────────────

  group('commitPhaseAdvance (behavioral, real Hive)', () {
    test('writes the full delta when nobody else advanced', () async {
      await UserRepository.instance
          .saveProgress({'current_phase': 1, 'current_week': 3});

      final wrote = await commitPhaseAdvance(
        intendedPhase: 2,
        source: 'test',
        now: DateTime.utc(2026, 8, 1, 12),
      );

      final p = UserRepository.instance.getProgress()!;
      expect(wrote, isTrue);
      expect(p['current_phase'], 2);
      expect(p['current_week'], 1, reason: 'a real advance resets the week');
      expect(p['phase_started_at'], '2026-08-01T12:00:00.000Z');
      expect(p['plan_generated_at'], p['phase_started_at'],
          reason: 'both timestamps describe ONE event and come from one instant');
    });

    test('SKIPS THE WHOLE DELTA when the live phase already reached it',
        () async {
      await UserRepository.instance.saveProgress({
        'current_phase': 2,
        'current_week': 3,
        'phase_started_at': 'ORIGINAL',
      });

      final wrote =
          await commitPhaseAdvance(intendedPhase: 2, source: 'test');

      final p = UserRepository.instance.getProgress()!;
      expect(wrote, isFalse);
      expect(p['current_phase'], 2);
      expect(p['current_week'], 3,
          reason: 'skipping must not reset the week under the other advancer');
      expect(p['phase_started_at'], 'ORIGINAL',
          reason: 'nor restamp the phase start');
    });

    test('never demotes: live 3, intended 2 → no write', () async {
      await UserRepository.instance
          .saveProgress({'current_phase': 3, 'current_week': 2});

      final wrote =
          await commitPhaseAdvance(intendedPhase: 2, source: 'test');

      expect(wrote, isFalse);
      expect(UserRepository.instance.getProgress()!['current_phase'], 3);
    });

    // A "current_phase stored as a DOUBLE" case was WRITTEN HERE and REMOVED
    // after testing the hypothesis instead of shipping the defence: the live
    // column is `integer`, and `saveProgress` (user_repository.dart:129) casts
    // `as int?` on this field and THROWS on a double before any read here could
    // see it — so the collapse-to-phase-1 failure the case was written to pin
    // cannot occur. Recorded rather than silently dropped, because the
    // defensive read it justified was also removed.

    test('missing progress map defaults to phase 1 and still advances',
        () async {
      expect(UserRepository.instance.getProgress(), isNull,
          reason: 'precondition: setUp cleared userBox');

      final wrote =
          await commitPhaseAdvance(intendedPhase: 2, source: 'test');

      expect(wrote, isTrue);
      expect(UserRepository.instance.getProgress()!['current_phase'], 2);
    });
  });

  // ───────────────────── C — the shared advance lock ────────────────────────

  group('withPhaseAdvanceLock', () {
    test('a second entrant gets ifBusy while the first holds the lock',
        () async {
      final release = Completer<void>();
      // The lock is a MODULE-LEVEL bool: if an expect below throws before
      // release.complete(), it stays held for the rest of the file and every
      // later test silently takes the ifBusy path. Release it unconditionally.
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var firstRan = false;
      var secondRan = false;

      final first = withPhaseAdvanceLock<bool?>(
        () async {
          firstRan = true;
          await release.future;
          return true;
        },
        ifBusy: null,
      );

      // The first call has already suspended on `release`, so the lock is held.
      final second = await withPhaseAdvanceLock<bool?>(
        () async {
          secondRan = true;
          return true;
        },
        ifBusy: null,
      );

      expect(firstRan, isTrue);
      expect(second, isNull, reason: 'second entrant must be turned away');
      expect(secondRan, isFalse,
          reason: 'and its body must never run — this is the assertion that '
              'fails if the shared lock stops excluding');

      release.complete();
      expect(await first, isTrue);
    });

    test('the kill-switch turns it into a pass-through', () async {
      // configBox['disable_phase_advance_lock'] — the platform-tier
      // feature_flag requirement. Default absent = lock ACTIVE (proved by the
      // test above); set true = every caller runs, nobody is turned away.
      await HiveService.instance.configBox
          .put(kDisablePhaseAdvanceLockKey, true);
      addTearDown(() =>
          HiveService.instance.configBox.delete(kDisablePhaseAdvanceLockKey));

      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var secondRan = false;

      final first = withPhaseAdvanceLock<bool?>(
        () async {
          await release.future;
          return true;
        },
        ifBusy: null,
      );
      final second = await withPhaseAdvanceLock<bool?>(
        () async {
          secondRan = true;
          return true;
        },
        ifBusy: null,
      );

      expect(secondRan, isTrue,
          reason: 'with the switch ON the second body MUST run — this is the '
              'assertion that fails if the kill-switch stops working');
      expect(second, isTrue);
      release.complete();
      expect(await first, isTrue);
    });

    test('the lock is released for the next caller, including after a throw',
        () async {
      await expectLater(
        withPhaseAdvanceLock<bool?>(
          () async => throw StateError('generation blew up'),
          ifBusy: null,
        ),
        throwsStateError,
      );

      final after = await withPhaseAdvanceLock<bool?>(
        () async => true,
        ifBusy: null,
      );
      expect(after, isTrue,
          reason: 'a thrown generation must not wedge the lock forever');
    });
  });

  // ────────── D — the real advance path with an interposed writer ───────────

  group('runProPhaseAdvance (real plan generation, concurrent writer)', () {
    testWidgets(
        'a higher-phase write landing during generation is NOT demoted, and '
        'its other fields survive', (tester) async {
      await tester.runAsync(() async {
        await _seedProAndExpiredPhase();
        await UserRepository.instance.saveProgress({
          'current_phase': 1,
          'current_week': 4,
          'total_workouts_done': 11,
        });
      });

      final refCompleter =
          Completer<({WidgetRef ref, ProviderContainer container})>();
      await tester.pumpWidget(
        ProviderScope(child: _RefCaptureWidget(onCapture: refCompleter.complete)),
      );
      await tester.pump();
      final captured = await tester.runAsync(() => refCompleter.future);

      late bool generated;
      await tester.runAsync(() async {
        // Start the advance; it reads current_phase = 1 and then goes into real
        // plan generation (hundreds of Hive writes — a genuine await window).
        var advanceDone = false;
        final advancing = runProPhaseAdvance(captured!.ref)
            .whenComplete(() => advanceDone = true);

        // Interpose the kind of write PhaseProgressReconciler's boot heal
        // makes: a HIGHER phase, plus a second field that only survives a
        // delta merge.
        // A single event-loop yield, NOT a wall-clock sleep. A LONGER delay is
        // strictly worse here: it risks the advance finishing first, which
        // turns the assertions below into a false green (an earlier draft used
        // 20ms and did exactly that once, caught by the precondition).
        //
        // Honest about what this is (round-1 review): a zero-duration timer is
        // an EVENT-QUEUE item, so it fires after the microtask queue drains —
        // this is a strong ordering ASSUMPTION, not a guarantee. It holds
        // because generateAndSchedule's suspends are real Hive file I/O. If it
        // ever stopped holding, the precondition below fails loudly rather than
        // the test passing vacuously, which is the property that matters.
        await Future<void>.delayed(Duration.zero);

        // WITHOUT this precondition the whole test is a false green: if
        // generation finished first, the interposed write would simply be the
        // LAST writer and `current_phase == 3` would hold even against the
        // pre-fix code. The assertions below only mean something while the
        // advance is still in its await window.
        expect(advanceDone, isFalse,
            reason: 'precondition: the interposed write must land DURING '
                'generation, not after it');

        await UserRepository.instance.updateProgress({
          'current_phase': 3,
          'total_workouts_done': 12,
        });

        generated = await advancing;
      });

      final p = UserRepository.instance.getProgress()!;

      expect(generated, isTrue,
          reason: 'precondition: the PRO + expired gates passed and a plan was '
              'actually generated — otherwise this test proves nothing');
      expect(p['current_phase'], 3,
          reason: 'THE regression assertion. Pre-fix this wrote currentPhase+1 '
              '= 2 from the pre-await read, demoting the interposed 3.');
      expect(p['total_workouts_done'], 12,
          reason: 'the interposed write must survive');
    });

    testWidgets(
        'an UNRELATED field written during generation survives the advance '
        '(pins Unit 3a\'s updateProgress(delta) fix)', (tester) async {
      // Deliberately NO phase conflict here — the advance really does write
      // current_phase 1 → 2. That is what makes this test discriminate where
      // the one above cannot: under the monotonic guard a demotion scenario
      // ends in NO write at all, so it can never expose a whole-map clobber.
      // Verified by negative control: reverting the write to
      // saveProgress(Map.from(preAwaitSnapshot)..addAll(...)) fails this test
      // with total_workouts_done == 11 while the phase assertion still passes.
      await tester.runAsync(() async {
        await _seedProAndExpiredPhase();
        await UserRepository.instance.saveProgress({
          'current_phase': 1,
          'current_week': 4,
          'total_workouts_done': 11,
        });
      });

      final refCompleter =
          Completer<({WidgetRef ref, ProviderContainer container})>();
      await tester.pumpWidget(
        ProviderScope(
            child: _RefCaptureWidget(onCapture: refCompleter.complete)),
      );
      await tester.pump();
      final captured = await tester.runAsync(() => refCompleter.future);

      late bool generated;
      await tester.runAsync(() async {
        var advanceDone = false;
        final advancing = runProPhaseAdvance(captured!.ref)
            .whenComplete(() => advanceDone = true);

        // A single event-loop yield, NOT a wall-clock sleep. A LONGER delay is
        // strictly worse here: it risks the advance finishing first, which
        // turns the assertions below into a false green (an earlier draft used
        // 20ms and did exactly that once, caught by the precondition).
        //
        // Honest about what this is (round-1 review): a zero-duration timer is
        // an EVENT-QUEUE item, so it fires after the microtask queue drains —
        // this is a strong ordering ASSUMPTION, not a guarantee. It holds
        // because generateAndSchedule's suspends are real Hive file I/O. If it
        // ever stopped holding, the precondition below fails loudly rather than
        // the test passing vacuously, which is the property that matters.
        await Future<void>.delayed(Duration.zero);
        expect(advanceDone, isFalse,
            reason: 'precondition: interposed DURING generation');

        await UserRepository.instance
            .updateProgress({'total_workouts_done': 12});

        generated = await advancing;
      });

      final p = UserRepository.instance.getProgress()!;
      expect(generated, isTrue);
      expect(p['current_phase'], 2, reason: 'the advance itself still lands');
      expect(p['total_workouts_done'], 12,
          reason: 'THE Unit 3a assertion: a whole-map save from the pre-await '
              'snapshot would put this back to 11');
    });
  });

  // ───────────────────────── E — wiring (source) ────────────────────────────

  group('every advance writer routes through the shared helper', () {
    // Presence-only by construction; the write SEMANTICS are Group B's job.
    // Comments are STRIPPED first (`feedback_source_grep_strip_comments_first`)
    // — none of the literals below currently appear in a comment in these
    // files, but a future comment mentioning `commitPhaseAdvance(` would make
    // every assertion here vacuous without stripping.
    String src(String p) => File(p)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('graduation_screen._onPro commits through commitPhaseAdvance under '
        'the shared lock', () {
      final s = src('lib/features/train/screens/graduation_screen.dart');
      expect(s.contains('withPhaseAdvanceLock<bool?>('), isTrue);
      expect(s.contains('commitPhaseAdvance('), isTrue);
      expect(s.contains("source: 'graduation_screen'"), isTrue);
      expect(s.contains("'current_phase': nextPhase"), isFalse,
          reason: 'the direct pre-await write must be gone, not merely wrapped');
    });

    test('simulation_service._maybeAdvancePhase commits through '
        'commitPhaseAdvance with its clock seam', () {
      final s = src('lib/features/dev/simulation_service.dart');
      expect(s.contains('commitPhaseAdvance('), isTrue);
      expect(s.contains("source: 'simulation_service'"), isTrue);
      expect(s.contains('now: nowWall()'), isTrue,
          reason: 'the sim must keep stamping simulated time, not wall time');
      expect(s.contains("'current_phase': currentPhase + 1"), isFalse);
    });

    test('pro_phase_advance keeps the session bootstrap in the locked wrapper',
        () {
      final s = src('lib/shared/services/pro_phase_advance.dart');
      final wrapperStart = s.indexOf('Future<bool> advanceProPhaseIfExpired');
      final coreStart = s.indexOf('Future<bool> runProPhaseAdvance');
      expect(wrapperStart, greaterThan(-1));
      expect(coreStart, greaterThan(wrapperStart));
      expect(
        s
            .substring(wrapperStart, coreStart)
            .contains('ensureOpenedForCurrentSession()'),
        isTrue,
        reason: 'the bootstrap must stay on the production entry point — the '
            'test-drivable core deliberately does not have it',
      );
    });
  });
}

/// PRO + an expired phase + a generatable profile, seeded through the same
/// `MigratedKey` / `UserRepository` the production readers use — no provider
/// overrides, so the gates in `runProPhaseAdvance` are exercised for real.
Future<void> _seedProAndExpiredPhase() async {
  await MigratedKey.write('isPro', true);
  await MigratedKey.write('expiresAt',
      DateTime.now().add(const Duration(days: 30)).toIso8601String());
  await MigratedKey.write('plan_end_date',
      DateTime.now().subtract(const Duration(days: 3)).toIso8601String());
  await MigratedKey.write('plan_start_date',
      DateTime.now().subtract(const Duration(days: 31)).toIso8601String());
  await UserRepository.instance.saveProfile({
    'primary_goal': 'build_muscle',
    'equipment_access': 'full_gym',
    'days_per_week': 4,
    'fitness_experience': 'intermediate',
  });
}

// Widget bridge to obtain a real WidgetRef — mirrors
// day_rollover_provider_invalidation_behavioral_test.dart. WidgetRef is sealed
// in flutter_riverpod and cannot be built outside a widget tree.
typedef _CaptureCallback = void Function(
    ({WidgetRef ref, ProviderContainer container}) captured);

class _RefCaptureWidget extends ConsumerStatefulWidget {
  const _RefCaptureWidget({required this.onCapture});
  final _CaptureCallback onCapture;

  @override
  ConsumerState<_RefCaptureWidget> createState() => _RefCaptureWidgetState();
}

class _RefCaptureWidgetState extends ConsumerState<_RefCaptureWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCapture(
          (ref: ref, container: ProviderScope.containerOf(context)));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
