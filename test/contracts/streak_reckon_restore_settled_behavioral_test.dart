// b4e7a1 (2026-10-06) — BEHAVIORAL contract for the per-account "the restore
// settled" marker that opens the streak-decay persist.
//
// WHAT THIS EXISTS TO CATCH. `WorkoutRepository.reckonStreakDecayAndPersist`
// persisted a missed-day freeze debit only when `SyncService.restoreCompletedTick
// > 0` — a PROCESS-lifetime counter that (F1) the background heal bumps only
// AFTER the cold-start rollover already ran, so a returning user's idle-day debit
// never persisted on a cold start (the founder's "16 days / 2 freezes",
// 2026-10-06), and (F2) was never reset on an account swap, so a tick inherited
// from account A let the reckon persist a debit against B's PRE-RESTORE rows
// (2026-09-17: 09-16 was debited 0.39 s before B's `restore_started`).
//
// The gate is now `SyncService.restoreSettledForCurrentUser`: a marker naming the
// account whose full restore finished with NO streak-critical op REPORTING a
// failure (`RestoreFailureCollector`, a zone-scoped sink fed by the one
// `_reportSyncFailure` funnel), equal to the live account AND the open Hive
// session, cleared by `_onUserChanged`.
//
// HOW EACH GROUP DISCRIMINATES (rule 21). T2/T3 flip the marker against the old
// tick: T3 (a tick > 0 with the marker null/another account) FAILS pre-fix. T4's
// listener reads the freeze count AT CALLBACK TIME, so a bump-before-reckon
// mutation reddens it. T5 drives a REAL op failure through the REAL funnel, per
// op family. T7 runs the real `restoreFromCloudForUser()` under `SyncHarness` —
// LEGACY FAN-OUT ONLY (the harness has no Supabase session, so the single-call
// path faults and falls back; T8's static enumeration covers that path). T10 is
// the settle decision as a pure table so every clause is mutation-killable.
//
// Run: flutter test test/contracts/streak_reckon_restore_settled_behavioral_test.dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/screens/restoring_screen.dart'
    show healAfterRestoreWhenSucceeded;
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart' show StubReadReply;
import '../sync/sync_domain_skip_harness.dart';

const _otherUser = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  final today = nowWall();
  DateTime daysAgo(int n) => today.subtract(Duration(days: n));
  String key(DateTime d) => istDateStr(d);

  /// 1 freeze, day-0 pending (never penalised), day-1 MISSED, day-2 completed.
  Future<void> seedMissedDay() async {
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at': daysAgo(20).toIso8601String(),
    });
    final wb = HiveService.instance.workoutBox;
    await wb.put('schedule_${key(daysAgo(0))}',
        {'type': 'PUSH', 'status': 'pending'});
    await wb.put('schedule_${key(daysAgo(1))}',
        {'type': 'PUSH', 'status': 'pending'});
    await wb.put('schedule_${key(daysAgo(2))}',
        {'type': 'PUSH', 'status': 'completed'});
    await HiveService.instance.userBox.put('progress', {
      'streak_freezes_available': 1,
      'streak_freeze_used_dates': <String>[],
    });
  }

  Map progress() => HiveService.instance.userBox.get('progress') as Map;

  void settle(String? uid) =>
      SyncService.instance.debugSetRestoreSettledUserIdForTest(uid);

  // ── T1 — the collector (pure; no Hive) ───────────────────────────────────
  group('T1. RestoreFailureCollector', () {
    test('a note inside run() records an allowlisted opType', () async {
      final sink = <String>{};
      await RestoreFailureCollector.run(sink, () async {
        RestoreFailureCollector.note('restore_scheduled_workouts');
      });
      expect(sink, {'restore_scheduled_workouts'});
      expect(restoreSettlesStreak(sink), isFalse);
      expect(restoreSettlesStreak(<String>{}), isTrue);
    });

    test('it ignores push-side `restore_sync_*` and every non-allowlisted '
        'opType (an EXACT list, never a `restore_` prefix)', () async {
      final sink = <String>{};
      await RestoreFailureCollector.run(sink, () async {
        RestoreFailureCollector.note('restore_sync_weight');
        RestoreFailureCollector.note('restore_weight_logs');
        RestoreFailureCollector.note('restore_workout_templates');
        RestoreFailureCollector.note('');
      });
      expect(sink, isEmpty);
    });

    test('a note OUTSIDE any zone is a silent no-op (never throws)', () {
      expect(() => RestoreFailureCollector.note('restore_freezes'), returnsNormally);
    });

    test('the zone survives await / timeout / Future.wait / Timer', () async {
      final sink = <String>{};
      await RestoreFailureCollector.run(sink, () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        RestoreFailureCollector.note('restore_workout_logs');
        await Future.wait([
          Future<void>.delayed(const Duration(milliseconds: 5)).then(
              (_) => RestoreFailureCollector.note('restore_user_progress')),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 5))
            .timeout(const Duration(seconds: 1))
            .then((_) => RestoreFailureCollector.note('restore_freezes'));
        final c = Completer<void>();
        Timer(const Duration(milliseconds: 5), () {
          RestoreFailureCollector.note('restore_user_profile');
          c.complete();
        });
        await c.future;
      });
      expect(sink, {
        'restore_workout_logs',
        'restore_user_progress',
        'restore_freezes',
        'restore_user_profile',
      });
    });

    test('clear() empties ONLY the active zone sink (the single-call attempt '
        'faulted; the legacy fan-out re-reports for itself) and is a silent '
        'no-op outside a zone (B-pass F4)', () async {
      final a = <String>{};
      final b = <String>{};
      await Future.wait([
        RestoreFailureCollector.run(a, () async {
          RestoreFailureCollector.note('restore_workout_plan');
          RestoreFailureCollector.clear();
          RestoreFailureCollector.note('restore_freezes');
        }),
        RestoreFailureCollector.run(b, () async {
          RestoreFailureCollector.note('restore_user_profile');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }),
      ]);
      expect(a, {'restore_freezes'},
          reason: 'what was noted BEFORE clear() is gone, what is noted after '
              'it is recorded');
      expect(b, {'restore_user_profile'},
          reason: 'a concurrent zone sink is never cleared by another zone');
      expect(RestoreFailureCollector.clear, returnsNormally);
    });

    test('two CONCURRENT runs keep separate sinks (a lightweight restore or a '
        'push sweep cannot pollute a full restore)', () async {
      final a = <String>{};
      final b = <String>{};
      await Future.wait([
        RestoreFailureCollector.run(a, () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          RestoreFailureCollector.note('restore_freezes');
        }),
        RestoreFailureCollector.run(b, () async {
          RestoreFailureCollector.note('restore_workout_plan');
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }),
      ]);
      expect(a, {'restore_freezes'});
      expect(b, {'restore_workout_plan'});
    });
  });

  // ── T10 — the settle decision, one row per clause (pure) ────────────────
  group('T10. shouldSettleRestoreMarker — each clause is load-bearing', () {
    bool decide({
      String? uid = 'A',
      String? liveUid = 'A',
      String? ownerUid = 'A',
      RestoreResult? result,
      Set<String> failures = const {},
    }) =>
        SyncService.shouldSettleRestoreMarker(
          uid: uid,
          liveUid: liveUid,
          ownerUid: ownerUid,
          result: result ?? RestoreResult.success(),
          failures: failures,
        );

    test('all clauses true => settles', () => expect(decide(), isTrue));
    test('a FAILED restore does not settle',
        () => expect(decide(result: RestoreResult.failed('x')), isFalse));
    test('a CANCELLED restore does not settle',
        () => expect(decide(result: RestoreResult.cancelled()), isFalse));
    test('ANY reported streak-critical failure withholds',
        () => expect(decide(failures: {'restore_scheduled_workouts'}), isFalse));
    test('no captured uid does not settle',
        () => expect(decide(uid: null, liveUid: null, ownerUid: null), isFalse));
    test('the live account changed during the restore does not settle',
        () => expect(decide(liveUid: 'B'), isFalse));
    test('the open Hive session belongs to someone else does not settle',
        () => expect(decide(ownerUid: 'B'), isFalse));
  });

  // ── T2/T3/T4/T6 — the gate and the post-restore reckon (real Hive) ──────
  group('gate + reckonAndNotifyAfterRestore', () {
    late Directory dir;
    setUp(() async {
      dir = await setUpHiveForTests();
      // Touch the singleton so its constructor registers `_onUserChanged`.
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      SyncService.instance.restoreCompletedTick.value = 0;
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
    });
    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      SyncService.instance.restoreCompletedTick.value = 0;
      HiveUserSession.debugCurrentUidResolverForTests = null;
      await tearDownHiveForTests(dir);
    });

    test('T2: marker = the live account, tick pinned at 0, missed day => the '
        'reckon PERSISTS the debit, the ledger entry and the notice flag',
        () async {
      await seedMissedDay();
      settle(kTestUserId);
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue);
      expect(SyncService.instance.restoreCompletedTick.value, 0);
      final streak = WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(streak, 1);
      expect(progress()['streak_freezes_available'], 0);
      expect(progress()['streak_freeze_used_dates'] as List,
          contains(key(daysAgo(1))));
      expect(progress()['streak_freeze_just_used'], isTrue,
          reason: 'the Home notice flag (F5) is set by the persisted consume');
    });

    test('T3: marker = account A but the live account is B, tick > 0 => NO '
        'persist (the F2 repro; FAILS pre-fix)', () async {
      await seedMissedDay();
      settle(kTestUserId);
      HiveUserSession.debugCurrentUidResolverForTests = () => _otherUser;
      SyncService.instance.restoreCompletedTick.value = 1; // inherited tick
      expect(SyncService.instance.restoreSettledForCurrentUser, isFalse);
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(progress()['streak_freezes_available'], 1,
          reason: 'a debit against the new account\'s pre-restore rows is the '
              '2026-09-17 spurious debit');
      expect(progress()['streak_freeze_used_dates'] as List, isEmpty);
    });

    test('T3b: _onUserChanged CLEARS the marker (same uid: only a real swap '
        'notification clears it)', () async {
      settle(kTestUserId);
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue);
      SingletonLifecycleRegistry.notifyUserChanged();
      expect(SyncService.instance.restoreSettledForCurrentUser, isFalse,
          reason: 'the marker must not survive an account-change notification');
    });

    test('T3c: marker null, tick > 0 => NO persist (the F1 cold-start repro; '
        'FAILS pre-fix)', () async {
      await seedMissedDay();
      SyncService.instance.restoreCompletedTick.value = 1;
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(progress()['streak_freezes_available'], 1);
    });

    test('the marker is NOT trusted when the Hive session is open for another '
        'account (the second uid clause)', () async {
      settle(_otherUser);
      HiveUserSession.debugCurrentUidResolverForTests = () => _otherUser;
      // live == marker, but the open session is kTestUserId.
      expect(HiveUserSession.currentOwnerFullId, kTestUserId);
      expect(SyncService.instance.restoreSettledForCurrentUser, isFalse);
    });

    test('T4: reckonAndNotifyAfterRestore reckons FIRST, bumps LAST — a tick '
        'listener already sees the debited ledger', () async {
      await seedMissedDay();
      settle(kTestUserId);
      int? availableAtCallback;
      void listener() {
        availableAtCallback = progress()['streak_freezes_available'] as int?;
      }

      SyncService.instance.restoreCompletedTick.addListener(listener);
      addTearDown(
          () => SyncService.instance.restoreCompletedTick.removeListener(listener));
      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      expect(availableAtCallback, 0,
          reason: 'a bump BEFORE the reckon would repaint from the pre-debit '
              'ledger (Home would keep showing 2 freezes)');
      expect(SyncService.instance.restoreCompletedTick.value, 1);
    });

    test('T4b: marker NOT settled => no persist, but the repaint tick is STILL '
        'bumped (listeners must refresh from the cloud-restored data), and no '
        'event fires when there is no withheld reason', () async {
      await seedMissedDay();
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      expect(progress()['streak_freezes_available'], 1, reason: 'no persist');
      expect(SyncService.instance.restoreCompletedTick.value, 1);
      expect(seen.where((e) => e.startsWith('streak_reckon_withheld')), isEmpty,
          reason: 'no restore has been withheld in this process');
    });

    test('T6: kill switch disable_streak_reckon_user_gate => the pre-fix TICK '
        'gate, verbatim (and the post-restore call only bumps)', () async {
      await HiveService.instance.configBox
          .put('disable_streak_reckon_user_gate', true);
      await seedMissedDay();

      // Marker set, tick 0: the pre-fix gate is closed.
      settle(kTestUserId);
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(progress()['streak_freezes_available'], 1);

      // reckonAndNotifyAfterRestore only bumps (it must not reckon).
      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      expect(progress()['streak_freezes_available'], 1);
      expect(SyncService.instance.restoreCompletedTick.value, 1);

      // Tick > 0, marker null: the pre-fix gate is OPEN.
      settle(null);
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(progress()['streak_freezes_available'], 0,
          reason: 'switch set => `restoreCompletedTick > 0` is the gate again');
    });
  });

  // ── T5 — a REAL op failure through the REAL funnel, per op family ────────
  group('T5. every streak-critical op reports through the funnel', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      // The harness's stub server is SHARED across tests (readReplies and
      // requests persist) — a 500 stubbed by one test must not leak into the next.
      h.server.readReplies.clear();
      h.server.clear();
    });
    tearDown(h.tearDown);

    Future<Set<String>> failuresOf(Future<void> Function() body) async {
      final sink = <String>{};
      await RestoreFailureCollector.run(sink, body);
      return sink;
    }

    test('restore_freezes (a malformed `freezes` payload)', () async {
      final sink = await failuresOf(() => SyncService.instance
          .restoreFreezesForTest(kTestUserId, preFetched: 'malformed'));
      expect(sink, contains('restore_freezes'));
      expect(restoreSettlesStreak(sink), isFalse);
    });

    test('restore_user_progress (a malformed rows payload)', () async {
      final sink = await failuresOf(() => SyncService.instance
          .restoreUserProgressForTest(kTestUserId, preFetched: 'malformed'));
      expect(sink, contains('restore_user_progress'));
    });

    test('restore_user_profile (a malformed rows payload)', () async {
      final sink = await failuresOf(() => SyncService.instance
          .restoreUserProfileForTest(kTestUserId,
              preFetched: 'malformed', preFetchedUsers: null));
      expect(sink, contains('restore_user_profile'));
    });

    test('restore_scheduled_workouts (a malformed rows payload)', () async {
      final sink = await failuresOf(() => SyncService.instance
          .restoreScheduledWorkoutsForTest(kTestUserId, preFetched: 'malformed'));
      expect(sink, contains('restore_scheduled_workouts'));
    });

    test('restore_workout_plan (a malformed rows payload)', () async {
      final sink = await failuresOf(() => SyncService.instance
          .restoreWorkoutPlanForTest(kTestUserId, preFetched: 'malformed'));
      expect(sink, contains('restore_workout_plan'));
    });

    test('restore_deleted_template_ids: a lookup that cannot ANSWER tells the '
        'collector and the forwarder returns NULL, never {} (B-pass F1)',
        () async {
      h.server.readReplies['workout_templates'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      final sink = await failuresOf(() async {
        final ids =
            await SyncService.instance.deletedTemplateCloudIdsForUser(kTestUserId);
        expect(ids, isNull,
            reason: 'the plan reconciler must be able to tell "could not '
                'answer" from "answered: none deleted"');
      });
      expect(sink, contains('restore_deleted_template_ids'));

      // Outside a restore zone (the boot / heal forwarder) the collector is
      // untouched, but the answer is STILL null.
      final ids2 =
          await SyncService.instance.deletedTemplateCloudIdsForUser(kTestUserId);
      expect(ids2, isNull);
    });

    test('MIRROR: an ANSWERED lookup is a set — empty when nothing is deleted, '
        'carrying the id when one is — and never touches the collector',
        () async {
      const deletedId = '11111111-2222-3333-4444-555555555555';
      addTearDown(h.server.getResponders.clear);
      h.server.getResponders['workout_templates'] = (_) => const [];
      final emptySink = await failuresOf(() async {
        final none =
            await SyncService.instance.deletedTemplateCloudIdsForUser(kTestUserId);
        expect(none, isNotNull);
        expect(none, isEmpty);
      });
      expect(emptySink, isEmpty);

      h.server.getResponders['workout_templates'] = (_) => const [
            {'id': deletedId, 'deleted_at': '2026-10-01T00:00:00Z'},
          ];
      final one =
          await SyncService.instance.deletedTemplateCloudIdsForUser(kTestUserId);
      expect(one, {deletedId});
    });

    test('the restore-side fail-EMPTY wrapper is unchanged: a failed lookup '
        'still reaches the restore filter as {} (the day is written) and still '
        'tells the collector, which is what withholds the marker', () async {
      const date = '2026-12-10';
      const cloudId = '11111111-2222-3333-4444-555555555555';
      h.server.readReplies['workout_templates'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      final sink = await failuresOf(() => SyncService.instance
              .restoreWorkoutPlanForTest(kTestUserId, preFetched: [
            {
              'plan_json': {
                'plan': null,
                'plan_start_date': null,
                'plan_end_date': null,
                'schedules': {
                  'schedule_$date': {
                    'date': date,
                    'workout_name': 'From snapshot',
                    'type': 'custom_template',
                    'template_id': 'tmpl_$cloudId',
                    'status': 'planned',
                  },
                },
              },
            },
          ]));
      expect(sink, contains('restore_deleted_template_ids'));
      expect(HiveService.instance.workoutBox.get('schedule_$date'), isNotNull,
          reason: 'fail-empty on the RESTORE side is by design; the collector '
              '(not this filter) keeps the streak persist closed');
    });
  });

  // ── T7 — the REAL restoreFromCloudForUser(), legacy fan-out only ─────────
  group('T7. restoreFromCloudForUser() sets / withholds the marker', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      h.server.readReplies.clear();
      h.server.clear();
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    });
    tearDown(() async {
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      await h.tearDown();
    });

    test('(a) every read OK => the marker is set to the live account',
        () async {
      final r = await SyncService.instance.restoreFromCloudForUser();
      expect(r.succeeded, isTrue, reason: 'error=${r.error}');
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue,
          reason: SyncService.instance.lastRestoreWithheldReason);
    });

    test('(b) scheduled_workouts answers 500 => the marker is WITHHELD and '
        'the reason names the op', () async {
      h.server.readReplies['scheduled_workouts'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      final r = await SyncService.instance.restoreFromCloudForUser();
      expect(r.succeeded, isTrue,
          reason: 'the restore itself still "succeeds" — that is exactly why '
              'the failure collector exists');
      expect(SyncService.instance.restoreSettledForCurrentUser, isFalse);
      expect(SyncService.instance.lastRestoreWithheldReason,
          contains('restore_scheduled_workouts'));
    });

    // B-pass F2: (b) proved ONE critical read through the real wrapper. The
    // completion ledger and the log summaries feed the walk's "was this day
    // done" answer, and `user_progress` feeds the freeze state — each must hold
    // the marker closed on its own failure, through the real restore.
    for (final c in const {
      'workout_logs': 'restore_workout_logs',
      'workout_schedule_completions': 'restore_schedule_completions',
      'user_progress': 'restore_user_progress',
    }.entries) {
      test('(b-${c.key}) ${c.key} answers 500 => the marker is WITHHELD and '
          'the reason names ${c.value}', () async {
        h.server.readReplies[c.key] =
            const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
        final r = await SyncService.instance.restoreFromCloudForUser();
        expect(r.succeeded, isTrue, reason: 'error=${r.error}');
        expect(SyncService.instance.restoreSettledForCurrentUser, isFalse,
            reason: '${c.key} failed; the walk input may be incomplete');
        expect(SyncService.instance.lastRestoreWithheldReason,
            contains(c.value));
      });
    }

    test('(c) a NON-streak-critical read failing (weight_logs) does NOT '
        'withhold the marker', () async {
      h.server.readReplies['weight_logs'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      final r = await SyncService.instance.restoreFromCloudForUser();
      expect(r.succeeded, isTrue, reason: 'error=${r.error}');
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue,
          reason: SyncService.instance.lastRestoreWithheldReason);
    });

    test('(d) end to end: a withheld restore => reckonAndNotifyAfterRestore '
        'persists NOTHING, still bumps, and emits ONE event naming the failing '
        'op', () async {
      await seedMissedDay();
      h.server.readReplies['scheduled_workouts'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      await SyncService.instance.restoreFromCloudForUser();
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);
      final tickBefore = SyncService.instance.restoreCompletedTick.value;

      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();

      expect(progress()['streak_freezes_available'], 1,
          reason: 'a restore that reported a streak-critical failure persists '
              'no debit');
      expect(SyncService.instance.restoreCompletedTick.value, tickBefore + 1);
      final events = seen.where((e) => e.startsWith('streak_reckon_withheld'));
      expect(events, hasLength(1));
      expect(events.single, contains('restore_scheduled_workouts'));
    });

    test('(e) end to end: a SETTLED restore => the same call PERSISTS the '
        'idle-day debit (the founder\'s 16-days / 2-freezes morning)', () async {
      await seedMissedDay();
      await SyncService.instance.restoreFromCloudForUser();
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue);
      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      expect(progress()['streak_freezes_available'], 0);
      expect(progress()['streak_freeze_used_dates'] as List,
          contains(key(daysAgo(1))));
    });

    test('a later FAILED restore never clears an earlier success for the same '
        'account', () async {
      await SyncService.instance.restoreFromCloudForUser();
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue);
      h.server.readReplies['scheduled_workouts'] =
          const StubReadReply(500, {'message': 'stub', 'code': 'XX000'});
      await SyncService.instance.restoreFromCloudForUser();
      expect(SyncService.instance.restoreSettledForCurrentUser, isTrue,
          reason: 'an earlier success for this account stays valid');
      expect(SyncService.instance.lastRestoreWithheldReason, isNotNull,
          reason: 'but the withheld reason of the latest call is recorded');
    });
  });

  // ── T8 — forcing function: a future op cannot silently not gate ──────────
  group('T8. every _safeRestoreOp label is classified', () {
    const critical = <String>{
      'workout_plan',
      'workout_logs',
      'schedule_completions',
      'scheduled_workouts',
      'user_progress',
      'user_profile',
      'freezes',
    };
    // Every OTHER label: reviewed as NOT feeding the streak walk.
    const nonCritical = <String>{
      'custom_exercises',
      'custom_foods',
      'workout_templates',
      'user_preferences',
      'exercise_logs',
      'weight_logs',
      'steps_logs',
      'nutrition_logs',
      'measurements',
      'water_logs',
      'sleep_logs',
      'readiness_daily',
      'streaks',
      'saved_meals',
      'coach_interactions',
      'coach_memory',
      'notifications_inbox',
      'saved_diet_plan',
      'rank_promotions',
      'referral_codes',
      'referral_redemptions',
    };

    late String src;
    setUpAll(() => src =
        _strip(File('lib/core/services/sync_service.dart').readAsStringSync()));

    String slice(String from, String to) {
      final a = src.indexOf(from);
      final b = src.indexOf(to, a + 1);
      expect(a, greaterThan(-1), reason: from);
      expect(b, greaterThan(a), reason: to);
      return src.substring(a, b);
    }

    Set<String> labels(String body) => RegExp(r"_safeRestoreOp\(\s*'(\w+)'")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();

    test('the NEWLINE-tolerant scan finds the labels a literal scan misses',
        () {
      // 15 calls put the label on the next line; a literal
      // `_safeRestoreOp('<label>'` scan would pass vacuously for them.
      expect(RegExp(r'_safeRestoreOp\(\s*$', multiLine: true).allMatches(src),
          isNotEmpty);
    });

    for (final entry in {
      'core (legacy fan-out)': [
        'Future<RestoreResult> _restoreFromCloudForUserCore()',
        'Future<RestoreResult?> _attemptSingleCallRestore('
      ],
      'single-call': [
        'Future<RestoreResult?> _attemptSingleCallRestore(',
        'static Map? validatedSnapshotTables('
      ],
    }.entries) {
      test('${entry.key}: all seven streak-critical labels are FOUND and every '
          'label is classified', () {
        final found = labels(slice(entry.value[0], entry.value[1]));
        expect(found.intersection(critical), critical,
            reason: 'a vacuous scan must fail — the critical labels missing '
                'from ${entry.key}: ${critical.difference(found)}');
        final unclassified = found.difference(critical).difference(nonCritical);
        expect(unclassified, isEmpty,
            reason: 'a NEW restore op must be classified: does it feed the '
                'streak walk? add `restore_<label>` to '
                'kStreakCriticalRestoreOpTypes or to nonCritical here — '
                'unclassified: $unclassified');
      });
    }

    test('each critical opType is emitted through the funnel under exactly '
        'that spelling (presence pin)', () {
      final syncDir = Directory('lib/core/services/sync');
      final all = syncDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => _strip(f.readAsStringSync()))
          .join('\n');
      for (final op in kStreakCriticalRestoreOpTypes) {
        if (op == 'restore_deleted_template_ids') continue;
        expect(all, contains("opType: '$op'"), reason: op);
      }
      expect(all, contains("RestoreFailureCollector.note('restore_deleted_template_ids')"));
    });
  });

  // ── T9 — source pins (PRESENCE only; the behaviour is T2-T7) ─────────────
  group('T9. wiring pins (presence)', () {
    String read(String p) => _strip(File(p).readAsStringSync());

    test('_reportSyncFailure\'s FIRST statement notes the collector', () {
      final src = read('lib/core/services/sync_service.dart');
      final i = src.indexOf('Future<void> _reportSyncFailure({');
      final open = src.indexOf('{', src.indexOf(') async', i));
      final firstStmt = src.substring(open + 1).trimLeft();
      expect(firstStmt, startsWith('RestoreFailureCollector.note(opType);'));
    });

    test('reckonAndNotifyAfterRestore reckons, then reports, then bumps LAST',
        () {
      final src = read('lib/core/services/day_rollover_service.dart');
      final a = src.indexOf('void reckonAndNotifyAfterRestore()');
      final body = src.substring(a, src.indexOf('Future<void> _doRollover(', a));
      final reckon = body.indexOf('reckonStreakDecayAndPersist()');
      final event = body.indexOf("'streak_reckon_withheld'");
      final bump = body.lastIndexOf('bumpRestoreCompleted()');
      expect(reckon, greaterThan(-1));
      expect(event, greaterThan(reckon));
      expect(bump, greaterThan(event), reason: 'the bump must be LAST');
    });

    test('Home overrides invalidateOnBackgroundRestore and re-checks the '
        'freeze notice (F5)', () {
      final src = read('lib/features/home/screens/home_screen.dart');
      final a = src.indexOf('void invalidateOnBackgroundRestore(WidgetRef ref)');
      expect(a, greaterThan(-1));
      final body = src.substring(a, a + 220);
      expect(body, contains('invalidateOnRetry(ref)'));
      expect(body, contains('_checkStreakFreezeUsed()'));
    });

    test('_onUserChanged clears the marker FIRST, before any step that can '
        'throw (B-pass F3)', () {
      final src = read('lib/core/services/sync_service.dart');
      final i = src.indexOf('void _onUserChanged() {');
      expect(i, greaterThan(-1));
      final body = src.substring(i + 'void _onUserChanged() {'.length).trimLeft();
      expect(body, startsWith('_restoreSettledUserId = null;'));
      expect(body.substring(0, 140), contains('_lastRestoreWithheldReason = null;'));
    });

    test('a single-call FAULT clears the failure sink before the legacy '
        'fan-out re-runs the ops (B-pass F4, presence)', () {
      final src = read('lib/core/services/sync_service.dart');
      final attempt = src.indexOf('await _attemptSingleCallRestore(userId, since)');
      final clear = src.indexOf('RestoreFailureCollector.clear();', attempt);
      final stepA = src.indexOf("restoreProgressLabel.value = 'Loading profile & plan'", attempt);
      expect(attempt, greaterThan(-1));
      expect(clear, greaterThan(attempt));
      expect(clear, lessThan(stepA),
          reason: 'the clear must precede the legacy Step A');
    });

    test('the wrapper keeps its pinned shape and settles AFTER the heal', () {
      final src = read('lib/core/services/sync_service.dart');
      final a = src.indexOf('Future<RestoreResult> restoreFromCloudForUser()');
      final body = src.substring(a, src.indexOf('static bool shouldHealAfterRestore', a));
      expect(body, contains('() => _restoreFromCloudForUserCore()'));
      expect(body.indexOf('_settleRestoreMarker('),
          greaterThan(body.indexOf('healCompletedTitlesAfterRestore()')));
    });
  });

  // ── T11 — the plan reconciler's ghost-day filter (B-pass F1) ─────────────
  // `PlanIntegrityReconciler.reconcile` writes `schedule_*` rows AFTER a restore
  // settled, outside any failure collector. Its ghost-day lookup used to FAIL
  // EMPTY, so a failed lookup let a deleted template's day back in as a past
  // `planned` row that the next reckon debited for good.
  group('T11. PlanIntegrityReconciler.filterGhostScheduleEntries', () {
    const liveId = '11111111-2222-3333-4444-555555555555';
    const goneId = '99999999-8888-7777-6666-555555555555';
    Map<String, dynamic> day(String date, {String? templateKey}) => {
          'date': date,
          'type': templateKey == null ? 'rest' : 'custom_template',
          if (templateKey != null) 'template_id': templateKey,
          'status': 'planned',
        };
    final bundle = <String, dynamic>{
      'schedule_2026-12-10': day('2026-12-10'),
      'schedule_2026-12-11': day('2026-12-11', templateKey: 'tmpl_$liveId'),
      'schedule_2026-12-12': day('2026-12-12', templateKey: 'tmpl_$goneId'),
    };

    test('a lookup that CANNOT ANSWER (null) skips every template-bearing day '
        'and keeps the plain one — the pre-fix {} let the ghost in', () async {
      final r = await PlanIntegrityReconciler.filterGhostScheduleEntries(
          bundle, () async => null);
      expect(r.live.keys, ['schedule_2026-12-10']);
      expect(r.unvettedSkipped, 2);
    });

    test('MIRROR: an ANSWERED empty set keeps every day (nothing is deleted)',
        () async {
      final r = await PlanIntegrityReconciler.filterGhostScheduleEntries(
          bundle, () async => <String>{});
      expect(r.live.keys, bundle.keys);
      expect(r.unvettedSkipped, 0);
    });

    test('MIRROR: an answered set drops exactly the ghost and keeps the live '
        'template day', () async {
      final r = await PlanIntegrityReconciler.filterGhostScheduleEntries(
          bundle, () async => {goneId});
      expect(r.live.keys, ['schedule_2026-12-10', 'schedule_2026-12-11']);
      expect(r.unvettedSkipped, 0);
    });

    test('the lookup runs ONCE however many template days there are, and NEVER '
        'when none carries a resolvable template', () async {
      var calls = 0;
      await PlanIntegrityReconciler.filterGhostScheduleEntries(bundle, () async {
        calls++;
        return <String>{};
      });
      expect(calls, 1);

      calls = 0;
      final plain = await PlanIntegrityReconciler.filterGhostScheduleEntries({
        'schedule_2026-12-10': day('2026-12-10'),
        // legacy `tmpl_<ms>` key: not UUID-shaped, can never be a ghost.
        'schedule_2026-12-13': day('2026-12-13', templateKey: 'tmpl_1700000000'),
      }, () async {
        calls++;
        return null;
      });
      expect(calls, 0);
      expect(plain.live, hasLength(2),
          reason: 'a legacy key is kept under a failed lookup — it is kept '
              'under an answered one too');
      expect(plain.unvettedSkipped, 0);
    });

    test('reconcile() routes its bundle through the filter and merges ONLY the '
        'filtered days (presence pin)', () {
      final src = _strip(
          File('lib/core/services/plan_integrity_reconciler.dart')
              .readAsStringSync());
      final a = src.indexOf('static Future<PlanReconcileOutcome> reconcile(');
      expect(a, greaterThan(-1));
      final body = src.substring(a);
      expect(body, contains('filterGhostScheduleEntries('));
      expect(body, contains('deletedTemplateCloudIdsForUser(userId)'));
      expect(body, contains('mergeScheduleBundleIntoHive(filtered.live)'));
    });
  });

  // ── T12 — the CONTINUE escape also heals + reckons (B-pass reviewer C F1) ──
  // `_goHome` attaches the post-restore heal only while the screen is mounted;
  // `_onContinueAnyway` leaves while the restore is still running, so that
  // cohort's restore could settle the marker and never reckon.
  group('T12. healAfterRestoreWhenSucceeded', () {
    Future<int> run(Future<RestoreResult>? restore) async {
      var calls = 0;
      healAfterRestoreWhenSucceeded(restore, heal: () async => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return calls;
    }

    test('a SUCCEEDED restore heals exactly once', () async {
      expect(await run(Future.value(RestoreResult.success())), 1);
    });

    test('MIRROR: a failed or cancelled restore never heals (partial Hive '
        'state)', () async {
      expect(await run(Future.value(RestoreResult.failed('boom'))), 0);
      expect(await run(Future.value(RestoreResult.cancelled())), 0);
    });

    test('MIRROR: a null future, or one that throws, is swallowed — it must '
        'never become an unhandled async error', () async {
      expect(await run(null), 0);
      expect(await run(Future<RestoreResult>.error(StateError('x'))), 0);
    });

    test('the heal waits for the restore to finish (a pending future does not '
        'heal yet)', () async {
      final c = Completer<RestoreResult>();
      var calls = 0;
      healAfterRestoreWhenSucceeded(c.future, heal: () async => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 0);
      c.complete(RestoreResult.success());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);
    });

    test('_onContinueAnyway attaches it AFTER navigating, only when the Hive '
        'session is open (presence pin)', () {
      final src = _strip(
          File('lib/features/auth/screens/restoring_screen.dart')
              .readAsStringSync());
      final a = src.indexOf('Future<void> _onContinueAnyway()');
      final b = src.indexOf('void dispose()', a);
      expect(a, greaterThan(-1));
      final body = src.substring(a, b);
      final go = body.lastIndexOf('context.go(');
      final heal = body.indexOf('healAfterRestoreWhenSucceeded(_restoreFuture)');
      expect(heal, greaterThan(go));
      expect(body.substring(heal - 40, heal), contains('ownershipOpen'));
      expect(src, contains('_restoreFuture = restoreFuture;'));
    });
  });

  // keep the import used: UserRepository reads the seeded progress elsewhere.
  test('sanity: the progress helper reads the seeded map', () async {
    final dir = await setUpHiveForTests();
    addTearDown(() => tearDownHiveForTests(dir));
    await seedMissedDay();
    expect(UserRepository.instance.getProgress()!['streak_freezes_available'], 1);
  });
}
