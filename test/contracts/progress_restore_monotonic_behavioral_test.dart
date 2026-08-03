// OI-83 (2026-08-03) — BEHAVIORAL contract for the cloud→Hive `progress`
// restore merge.
//
// WHAT THIS EXISTS TO CATCH. `grep -rn "put('progress'" lib/` returns SEVEN
// direct writers of the whole progress map. Five are read-modify-write over a
// narrow key set (freeze fields, `streak_progress_version`) and cannot demote
// anything. TWO copied the PostgREST row in wholesale:
//
//   sync/sync_profile.dart          _restoreUserProgress
//   auth_session_bootstrapper.dart  the post-auth progress pull
//
// both shaped `{...local, for (e in cloud.entries) if (e.value != null) e.key: e.value}`
// — cloud-non-null-wins for EVERY key. A device that advanced locally and had
// not yet pushed got its own `current_phase` (and the two other lifetime
// counters) silently lowered by its own restore: no guard, no telemetry, no
// trace. `feedback_monotonic_field_recompute_demotion`; siblings 3a7b9f (rank
// demoted by a recompute) and c8f3d1 (the advance-side guard, which lives on
// `commitPhaseAdvance` — a function neither of these writers calls).
//
// WHY THE ADVANCE-SIDE GUARD DID NOT ALREADY COVER IT. c8f3d1 made the ADVANCE
// operation monotonic. These are the RESTORE operation: a different writer, a
// different correct answer, and the answer was a founder product call
// (2026-08-03) — **local-max-wins on the monotonic fields, with telemetry**. The
// set is THREE, not the four OI-83 proposed: round-1 review removed
// `longest_gap_days` as an inverted field (higher is worse, gates a rank, no
// client writer), where max-wins could only ever refuse a server correction.
//
// HOW EACH TEST DISCRIMINATES (rule 21 — a test that cannot fail is not a
// regression test). Group A carries the PRE-FIX merge expression inline as a
// negative control and asserts, on the identical input, that the old shape
// demotes and the new one does not. That is a real discriminator, not a
// restatement: if `mergeCloudProgress` ever regresses to cloud-wins the two
// halves converge and the test fails. Group B fails if the guard is correct in
// the pure helper but the Hive round-trip drops it. Group C fails if a refused
// demotion stops being observable — the "silent" half of the bug. Group D
// fails if the declined-advance condition stops being REPORTED. Group E pins
// why that condition is reported rather than repaired: the reconciler's symptom
// gate cannot see it, and the three repair mechanisms that were designed all
// turned out to be wrong (see reportDeclinedAdvanceLeftStaleRows' doc). Group E
// is what stops a future reader "simplifying" that decision away.
//
// COVERAGE HONESTY. The two restore writers are private and network-bound, so
// neither is driven end-to-end here; Group B covers the exact merge→Hive→read
// chain they now perform, and their ROUTING through the shared helper is
// source-pinned by `restore_progress_uses_shared_merge_test.dart`. Presence
// coverage for the wiring, behavioral coverage for the merge — stated plainly
// rather than implied (`feedback_source_grep_false_confidence`).
//
// Run: flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
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

/// The EXACT pre-fix merge, kept verbatim as the negative control for Group A.
/// Both restore writers built this expression inline.
Map<String, dynamic> _preFixMerge(
  Map<String, dynamic> local,
  Map<String, dynamic> cloud,
) =>
    <String, dynamic>{
      ...local,
      for (final e in cloud.entries)
        if (e.value != null) e.key: e.value,
    };

void main() {
  late Directory tempDir;
  const testUser = 'b17ec0de-1111-4444-8888-0f18d5c0ffee';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('progress_restore_monotonic_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    ErrorTelemetry.debugOnLogEventForTests = null;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.configBox.clear();
  });

  // ─────────────── A — the pure merge, vs the pre-fix control ───────────────

  group('mergeCloudProgress (pure)', () {
    test('a LOWER cloud current_phase is refused — pre-fix took it', () {
      final local = <String, dynamic>{'current_phase': 5};
      final cloud = <String, dynamic>{'current_phase': 2};

      // Negative control: this is what shipped, on this exact input.
      expect(_preFixMerge(local, cloud)['current_phase'], 2,
          reason: 'control must reproduce the demotion, else it proves nothing');

      final r = UserRepository.mergeCloudProgress(local: local, cloud: cloud);
      expect(r.merged['current_phase'], 5);
      expect(r.declinedFields.single.field, 'current_phase');
      expect(r.declinedFields.single.localValue, 5);
      expect(r.declinedFields.single.cloudValue, 2);
    });

    test('every monotonic field is guarded, not just current_phase', () {
      final local = <String, dynamic>{
        'current_phase': 4,
        'deployments_complete': 3,
        'total_workouts_done': 120,
      };
      final cloud = <String, dynamic>{
        'current_phase': 1,
        'deployments_complete': 0,
        'total_workouts_done': 12,
      };

      final control = _preFixMerge(local, cloud);
      final r = UserRepository.mergeCloudProgress(local: local, cloud: cloud);

      for (final f in UserRepository.monotonicProgressFields) {
        expect(control[f], cloud[f], reason: 'control: $f was demoted pre-fix');
        expect(r.merged[f], local[f], reason: '$f must hold its local max');
      }
      expect(r.declinedFields, hasLength(3));
    });

    test('longest_gap_days is NOT guarded — the guard would point backwards',
        () {
      // Round-1 review P2. OI-83 listed this field, and it is inverted: higher
      // is WORSE and it gates a rank (rank_service.dart:506 fails the rung when
      // longestGapDays > maxGapDays, and a failed rung blocks every rung above
      // it). No client writer populates it, and migration 115 already GREATESTs
      // it server-side — so local-max-wins could only ever REFUSE a server
      // correction and pin the ladder shut.
      expect(UserRepository.monotonicProgressFields,
          isNot(contains('longest_gap_days')));
      final r = UserRepository.mergeCloudProgress(
        local: {'longest_gap_days': 30},
        cloud: {'longest_gap_days': 3},
      );
      expect(r.merged['longest_gap_days'], 3,
          reason: 'a server correction downward MUST land');
      expect(r.hasDeclined, isFalse);
    });

    test('kill-switch restores the pre-fix expression verbatim (§4.6)', () async {
      final local = <String, dynamic>{'current_phase': 5};
      final cloud = <String, dynamic>{'current_phase': 2};

      await HiveService.instance.configBox.put(
          UserRepository.kDisableProgressRestoreMonotonicMergeKey, true);
      addTearDown(() => HiveService.instance.configBox
          .delete(UserRepository.kDisableProgressRestoreMonotonicMergeKey));

      final off = UserRepository.mergeCloudProgress(local: local, cloud: cloud);
      expect(off.merged, equals(_preFixMerge(local, cloud)),
          reason: 'switch closed must be byte-identical to the old merge');
      expect(off.hasDeclined, isFalse);

      await HiveService.instance.configBox
          .delete(UserRepository.kDisableProgressRestoreMonotonicMergeKey);
      final on = UserRepository.mergeCloudProgress(local: local, cloud: cloud);
      expect(on.merged['current_phase'], 5,
          reason: 'switch open (default) must guard — else this test is inert');
    });

    test('a HIGHER cloud value still wins — this is a guard, not a freeze', () {
      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 2, 'total_workouts_done': 10},
        cloud: {'current_phase': 6, 'total_workouts_done': 99},
      );
      expect(r.merged['current_phase'], 6);
      expect(r.merged['total_workouts_done'], 99);
      expect(r.hasDeclined, isFalse);
    });

    test('NON-monotonic fields still take cloud — including a genuine 0', () {
      // A streak legitimately resets. Max-wins here would make a broken streak
      // un-resettable from the cloud, which is why the set is exactly 3.
      final r = UserRepository.mergeCloudProgress(
        local: {'current_streak_days': 30, 'current_streak_weeks': 4},
        cloud: {'current_streak_days': 0, 'current_streak_weeks': 0},
      );
      expect(r.merged['current_streak_days'], 0);
      expect(r.merged['current_streak_weeks'], 0);
      expect(r.hasDeclined, isFalse);
    });

    test('streak_progress_version stays cloud-always-wins (Unit 3b e6b9c4)', () {
      // The server owns this counter; adopting a higher LOCAL value would make
      // the next optimistic-lock RPC fail its version check.
      final r = UserRepository.mergeCloudProgress(
        local: {'streak_progress_version': 9},
        cloud: {'streak_progress_version': 4},
      );
      expect(r.merged['streak_progress_version'], 4);
      expect(r.hasDeclined, isFalse);
    });

    test('a fresh reinstall (empty local) adopts cloud verbatim', () {
      final cloud = <String, dynamic>{
        'current_phase': 7,
        'deployments_complete': 6,
        'total_workouts_done': 240,
        'longest_gap_days': 11,
        'current_streak_days': 3,
      };
      final r =
          UserRepository.mergeCloudProgress(local: const {}, cloud: cloud);
      expect(r.merged, equals(cloud));
      expect(r.hasDeclined, isFalse,
          reason: 'nothing to demote when there is no local value');
      // The whole point of local-max-wins being safe: identical to pre-fix.
      expect(r.merged, equals(_preFixMerge(const {}, cloud)));
    });

    test('cloud nulls never win, monotonic or not (unchanged semantics)', () {
      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 3, 'plan_generated_at': 'x'},
        cloud: {'current_phase': null, 'plan_generated_at': null},
      );
      expect(r.merged['current_phase'], 3);
      expect(r.merged['plan_generated_at'], 'x');
      expect(r.hasDeclined, isFalse);
    });

    test('a non-numeric side keeps LOCAL and reports, never throws', () {
      // Round-1 review P3: the first version wrote the cloud value through, so
      // the merge did not throw but every downstream reader would — both
      // pro_phase_advance and rank_service.dart:448 read this family
      // `as int?`, which throws on a String rather than yielding null.
      // Persisting garbage just moves the crash one hop.
      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 4},
        cloud: {'current_phase': 'garbage'},
      );
      expect(r.merged['current_phase'], 4, reason: 'local is kept, not clobbered');
      expect(r.malformedFields, ['current_phase']);
      expect(r.hasDeclined, isFalse,
          reason: '"could not compare" is a different fact from "refused a demotion"');
    });

    test('a numeric cloud value REPAIRS a corrupt local one, and reports', () {
      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 'garbage'},
        cloud: {'current_phase': 3},
      );
      expect(r.merged['current_phase'], 3,
          reason: 'pinning the garbage would keep the crash forever');
      expect(r.malformedFields, ['current_phase']);
    });

    test('an ABSENT local value is not malformed — it is a reinstall', () {
      // ⚠ Regression pin for a P0 introduced (and caught here) while fixing
      // round-1's P3: treating `null is! num` as malformed dropped every
      // monotonic key from the merged map, so a reinstalling user restored
      // with NO current_phase at all.
      final r = UserRepository.mergeCloudProgress(
        local: const {},
        cloud: {'current_phase': 6, 'deployments_complete': 5},
      );
      expect(r.merged['current_phase'], 6);
      expect(r.merged['deployments_complete'], 5);
      expect(r.malformedFields, isEmpty);
    });

    test('a JSON double from PostgREST compares numerically, not by type', () {
      // The cloud side has been through JSON — read as num, per the
      // sync_profile.dart:100 idiom rather than commitPhaseAdvance's `as int?`.
      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 5},
        cloud: {'current_phase': 2.0},
      );
      expect(r.merged['current_phase'], 5);
      expect(r.declinedFields.single.cloudValue, 2);
    });
  });

  // ──────────── B — the merge → Hive → read chain the writers run ───────────

  group('restore merge round-trips through Hive', () {
    test('a locally-advanced phase survives a stale cloud restore', () async {
      await UserRepository.instance.saveProgress({
        'current_phase': 5,
        'current_week': 2,
        'total_workouts_done': 80,
      });

      // Exactly what both restore writers now do.
      final existing = HiveService.instance.userBox.get('progress');
      final local = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      final result = UserRepository.mergeCloudProgress(
        local: local,
        cloud: {'current_phase': 2, 'total_workouts_done': 10, 'current_week': 1},
      );
      await HiveService.instance.userBox.put('progress', result.merged);

      final readBack = UserRepository.instance.getProgress()!;
      expect(readBack['current_phase'], 5);
      expect(readBack['total_workouts_done'], 80);
      // Non-monotonic field still took the cloud value — the merge is scoped,
      // not a blanket local-wins.
      expect(readBack['current_week'], 1);
    });
  });

  // ───────────────── C — the refusal is observable (telemetry) ──────────────

  group('progress_restore_demotion_declined telemetry', () {
    test('one event per declined field, with both values', () {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');

      final r = UserRepository.mergeCloudProgress(
        local: {'current_phase': 4, 'total_workouts_done': 50},
        cloud: {'current_phase': 1, 'total_workouts_done': 5},
      );
      reportProgressDemotionsDeclined(r, source: 'unit_test');

      expect(seen, hasLength(2),
          reason: 'two distinct facts must not collapse into one event');
      expect(
          seen.every((s) => s.startsWith('progress_restore_demotion_declined')),
          isTrue);
      expect(seen.any((s) => s.contains('field=current_phase local=4 cloud=1')),
          isTrue);
      expect(
          seen.any(
              (s) => s.contains('field=total_workouts_done local=50 cloud=5')),
          isTrue);
      expect(seen.every((s) => s.contains('source=unit_test')), isTrue);
    });

    test('nothing declined → no event at all', () {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add(op);

      reportProgressDemotionsDeclined(
        UserRepository.mergeCloudProgress(
          local: {'current_phase': 1},
          cloud: {'current_phase': 3},
        ),
        source: 'unit_test',
      );
      expect(seen, isEmpty);
    });
  });

  // ──────── D — the declined-advance repair (OI-83 second-order half) ───────

  group('declined advance is reported', () {
    test('commitPhaseAdvance still declines a stale intent', () async {
      await UserRepository.instance.saveProgress({'current_phase': 5});
      final committed = await commitPhaseAdvance(
          intendedPhase: 2, source: 'progress_restore_monotonic_test');
      expect(committed, isFalse,
          reason: 'the decline is what makes the counter correct');
      expect(UserRepository.instance.getProgress()!['current_phase'], 5);
    });

    test('the stale-rows condition emits a distinct, self-describing event',
        () async {
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');

      await reportDeclinedAdvanceLeftStaleRows(
        source: 'progress_restore_monotonic_test',
        intendedPhase: 2,
        livePhase: 5,
      );

      expect(seen, hasLength(1));
      expect(seen.single, startsWith('phase_advance_declined_rows_stale'));
      expect(seen.single, contains('intended=2 live=5'),
          reason: 'both phases must be in the payload — the gap IS the signal');
    });

    test('reporting never throws back at the caller', () async {
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => throw StateError('sink exploded');
      await expectLater(
        reportDeclinedAdvanceLeftStaleRows(
            source: 'test', intendedPhase: 1, livePhase: 2),
        completes,
        reason: 'a telemetry failure must not surface as an advance failure',
      );
    });
  });

  // ───── E — why the repair needs force: the symptom gate cannot see it ─────

  group('PlanIntegrityReconciler.needsHeal is blind to stale-phase rows', () {
    test('a fully-populated generated week reports healthy', () {
      // These rows are what generateAndSchedule wrote for the phase the
      // counter did NOT advance to. They have their exercises, so the a7d3f1
      // symptom check passes them — which is exactly why the caller that saw
      // the decline must pass force: true.
      final generated = [
        {
          'type': 'workout',
          'status': 'planned',
          'exercises': [
            {'name': 'Back Squat'}
          ],
        },
        {'type': 'rest', 'status': 'planned'},
      ];
      expect(PlanIntegrityReconciler.needsHeal(generated), isFalse);
    });

    test('the symptom it CAN see still fires (control)', () {
      final broken = [
        {'type': 'workout', 'status': 'planned', 'exercises': <dynamic>[]},
      ];
      expect(PlanIntegrityReconciler.needsHeal(broken), isTrue);
    });

    // ── why this is REPORTED, not repaired ───────────────────────────────
    //
    // needsHeal is the reconciler's symptom gate, and these two tests are the
    // record of why forcing past it was not enough. `mergeScheduleEntry` then
    // applies the SAME predicate per row, so every superseded workout day comes
    // back unchanged. Overriding that too (`preferSnapshot`) plus deleting rows
    // past the re-anchored window was built, reviewed, and REVERTED: cloud
    // `plan_json` is pushed only by the DAILY full sync, so the snapshot can be
    // 24h stale and the sweep would delete the WINNER's fresh rows; and the
    // snapshot spans every schedule_* key box-wide, so it would revert an
    // un-synced local swap. Both refutations are in
    // reportDeclinedAdvanceLeftStaleRows' doc comment. Left as a test so the
    // fourth attempt starts from the evidence.

    test('the default merge keeps a populated local row — the swap guard', () {
      final local = {
        'type': 'workout',
        'status': 'planned',
        'exercises': [
          {'name': 'User swapped this in, not yet synced'}
        ],
      };
      final snapshot = {
        'type': 'workout',
        'status': 'planned',
        'exercises': [
          {'name': 'Frozen snapshot'}
        ],
      };
      final merged =
          PlanIntegrityReconciler.mergeScheduleEntry(local, snapshot);
      final firstEx = (merged['exercises'] as List).first as Map;
      expect(firstEx['name'], 'User swapped this in, not yet synced',
          reason: 'reverting an un-synced swap is why preferSnapshot was '
              'refuted — this pin is what stops it coming back');
    });

    test('a completed day is never overwritten by the snapshot', () {
      final merged = PlanIntegrityReconciler.mergeScheduleEntry(
        {
          'type': 'workout',
          'status': 'completed',
          'exercises': [
            {'name': 'What the user actually did'}
          ],
        },
        {'type': 'workout', 'status': 'planned', 'exercises': <dynamic>[]},
      );
      expect(merged['status'], 'completed');
      final doneEx = (merged['exercises'] as List).first as Map;
      expect(doneEx['name'], 'What the user actually did');
    });
  });
}
