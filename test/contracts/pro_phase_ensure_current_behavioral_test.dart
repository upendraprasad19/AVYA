// BEHAVIORAL contract — PRO next phase builds itself after a restore
// (plan docs/plans/2026-10-16-pro-phase-advance-ensure-current.md, Piece A;
// concept `pro_phase_ensure_current`).
//
// THE FOUNDER'S CASE (2026-10-16, iPhone Safari, new tab): PRO, Phase III, the
// four weeks done, `plan_end` Sun Oct 11, today Fri Oct 16. The only automatic
// advance was a cold-start splash call that ran BEFORE the restore, saw an empty
// store, and returned quietly; nothing re-ran it after the restore. Train showed
// "Complete Phase III to unlock Phase IV". `ensureProPhaseAfterRestore` is the
// post-restore trigger; these tests drive the REAL function against a real Hive
// and the real plan generator, with the clock pinned (never the authoring day).
//
// WHAT EACH GROUP DISCRIMINATES (rule 21 — mutated, see the diagnose doc):
//   A  the founder fixture: exactly one phase, starting Mon Oct 12, one
//      `current_phase` bump, one event, the tabs repainted;
//   B  idempotence / concurrency: a second ensure is a no-op, two concurrent
//      ensures build one phase;
//   C  the gates: marker, PRO, expiry, kill switch, simulation, owner;
//   D  the local-evidence witness: a settled marker with a MINTED default
//      progress map (`current_phase: 1`) must never build "Phase 2" for a
//      Phase III user;
//   E  events: only after PRO + expired are proven, deduped, `not_pro` only at
//      the heal site;
//   F  the pure evidence function; G  the call-site wiring.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/pro_phase_ensure_current_behavioral_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/app_events_service.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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

const _user = 'ad0a11ce-3c3c-4141-9999-c0ffeec0ffee';

/// Fri 2026-10-16, 09:30 — the founder's moment. A pinned seam, never the
/// authoring day, so this test cannot go red tomorrow morning.
final _today = DateTime(2026, 10, 16, 9, 30);

/// Waits until the workout box stops changing for [quiet]: Train's repair is
/// fire-and-forget and keeps writing rows after the first one appears; the next
/// test's setUp must not close the boxes under it.
Future<void> _settleHive({
  Duration quiet = const Duration(milliseconds: 1500),
}) async {
  var last = -1;
  var stableSince = DateTime.now();
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(end)) {
    final n = HiveService.instance.workoutBox.length;
    if (n != last) {
      last = n;
      stableSince = DateTime.now();
    } else if (DateTime.now().difference(stableSince) >= quiet) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tempDir;
  late List<({String event, Map<String, dynamic>? metadata})> events;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('pro_phase_ensure_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows =
        jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put(
        (r['id'] ?? r['name']).toString(),
        Map<String, dynamic>.from(r),
      );
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
    await HiveUserSession.openForUser(_user);
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.configBox.clear();
    setTestClockTo(_today);
    HiveUserSession.debugCurrentUidResolverForTests = () => _user;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(_user);
    SyncService.instance.debugSetLastRestoreWithheldReasonForTest(null);
    SyncService.pausedForSimulation = false;
    debugResetProPhaseEnsureState();
    events = <({String event, Map<String, dynamic>? metadata})>[];
    AppEventsService.debugCapture = events;
  });

  tearDown(() async {
    final pending = DayRolloverObserver.debugLastEnsure;
    if (pending != null) await pending;
    AppEventsService.debugCapture = null;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    SyncService.instance.debugSetLastRestoreWithheldReasonForTest(null);
    SyncService.pausedForSimulation = false;
    HiveUserSession.debugCurrentUidResolverForTests = null;
    resetTestClock();
  });

  List<String> outcomes() => [
    for (final e in events)
      if (e.event == 'pro_phase_ensure') e.metadata!['outcome'] as String,
  ];

  int phaseNow() =>
      (UserRepository.instance.getProgress()!['current_phase'] as num).toInt();

  // ─────────────── A — the founder's case, end to end ──────────────────────

  group('A. the founder fixture (restored PRO user, expired Phase III)', () {
    test('builds exactly Phase IV from Mon Oct 12, bumps current_phase once, '
        'emits one event, repaints', () async {
      await _seedRestoredProUser();
      final tickBefore = SyncService.instance.restoreCompletedTick.value;

      final out = await ensureProPhaseAfterRestore(site: 'rollover');

      expect(out, ProPhaseEnsureOutcome.generated);
      expect(phaseNow(), 4, reason: 'exactly one phase advance');
      final start = WorkoutScheduleReadService.instance.getPlanStartDate()!;
      expect(
        DateTime(start.year, start.month, start.day),
        DateTime(2026, 10, 12),
        reason: 'D1: the new phase starts at plan_end+1, not "today"',
      );
      final end = WorkoutScheduleReadService.instance.getPlanEndDate()!;
      expect(DateTime(end.year, end.month, end.day), DateTime(2026, 11, 8));
      // The completed Phase III days are untouched by the new phase.
      final box = HiveService.instance.workoutBox;
      expect((box.get('schedule_2026-10-09') as Map)['status'], 'completed');
      expect((box.get('schedule_2026-10-07') as Map)['status'], 'completed');
      // The gap days Oct 12-15 are never written as completed.
      for (final d in [
        '2026-10-12',
        '2026-10-13',
        '2026-10-14',
        '2026-10-15',
      ]) {
        final row = box.get('schedule_$d') as Map?;
        expect(row?['status'], isNot('completed'), reason: d);
      }
      expect(
        SyncService.instance.restoreCompletedTick.value,
        greaterThan(tickBefore),
        reason: 'the tabs are repainted through the tick',
      );
      expect(outcomes(), ['generated']);
      expect(events.single.metadata!['site'], 'rollover');
    });

    test('the gap days debit the streak freeze, persisted (the post-build '
        'reckon): 1 freeze before, 0 after, the used-dates ledger holds the '
        'covered day', () async {
      await _seedRestoredProUser();
      expect(
        UserRepository.instance.getProgress()!['streak_freezes_available'],
        1,
      );

      await ensureProPhaseAfterRestore(site: 'rollover');

      final progress = UserRepository.instance.getProgress()!;
      expect(progress['streak_freezes_available'], 0);
      expect((progress['streak_freeze_used_dates'] as List), isNotEmpty);
    });

    test(
      'a plan push that never answers does not hold the build: the ensure '
      'still completes (bounded push), and the new phase is in Hive',
      () async {
        await _seedRestoredProUser();
        SyncService.debugPlanPushOverride = () => Completer<void>().future;
        WorkoutScheduleReadService.planPushTimeout = const Duration(
          milliseconds: 300,
        );
        addTearDown(() {
          SyncService.debugPlanPushOverride = null;
          WorkoutScheduleReadService.planPushTimeout = const Duration(
            seconds: 20,
          );
        });

        final out = await ensureProPhaseAfterRestore(
          site: 'rollover',
        ).timeout(const Duration(seconds: 30));

        expect(out, ProPhaseEnsureOutcome.generated);
        expect(phaseNow(), 4);
      },
    );

    test('the heal call site (reckonAndNotifyAfterRestore) reaches the same '
        'build', () async {
      await _seedRestoredProUser();

      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      await DayRolloverObserver.debugLastEnsure;

      expect(phaseNow(), 4);
      expect(outcomes(), ['generated']);
      expect(events.single.metadata!['site'], 'heal');
    });
  });

  group('A2. heal site keeps its unconditional repaint', () {
    test('a non-expired PRO user: reckonAndNotifyAfterRestore still bumps the '
        'tick and builds nothing', () async {
      await _seedRestoredProUser();
      await MigratedKey.write(
        'plan_end_date',
        DateTime(2026, 10, 25).toIso8601String(),
      );
      final before = SyncService.instance.restoreCompletedTick.value;

      DayRolloverObserver.instance.reckonAndNotifyAfterRestore();
      await DayRolloverObserver.debugLastEnsure;

      expect(SyncService.instance.restoreCompletedTick.value, before + 1);
      expect(phaseNow(), 3);
      expect(events, isEmpty);
    });
  });

  // ─────────────── A3 — a Train rebuild landing MID-generation ──────────────

  group('A3. Train rebuild during the build (B-pass finding 1)', () {
    test(
      'currentPlanProvider invalidated in the same stretch the ensure starts '
      '(the tick-driven refresh) never regenerates the OLD phase over the new '
      'one: every row from the new start and the plan blob say phase 4',
      () async {
        await _seedRestoredProUser();
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.listen(currentPlanProvider, (_, _) {}, fireImmediately: true);

        // Production order at the heal site: the tick bump invalidates the
        // listened provider, then the ensure starts in the same synchronous
        // stretch. The rebuild itself runs lazily, after the ensure first yields.
        container.invalidate(currentPlanProvider);
        final f = ensureProPhaseAfterRestore(site: 'heal');
        final out = await f;
        // Let any fire-and-forget Train repair settle (it needs real I/O).
        await Future<void>.delayed(const Duration(seconds: 2));

        expect(out, ProPhaseEnsureOutcome.generated);
        expect(phaseNow(), 4);
        final box = HiveService.instance.workoutBox;
        final phases = <int>{};
        for (final k in box.keys) {
          final key = k.toString();
          if (!key.startsWith('schedule_')) continue;
          final date = key.substring('schedule_'.length);
          if (date.compareTo('2026-10-12') < 0) continue;
          phases.add(((box.get(k) as Map)['phase'] as num).toInt());
        }
        expect(phases, {
          4,
        }, reason: 'no row of the new window may carry the old phase');
        expect(
          ((box.get('current_plan') as Map)['phase'] as num).toInt(),
          4,
          reason: 'the plan blob must be the new phase too',
        );
        expect(
          container.read(currentPlanProvider).isGenerating,
          isFalse,
          reason:
              'the deferred Train rebuild must run once the advance ends, '
              'not leave the screen on "Generating"',
        );
        await _settleHive();
      },
    );

    test('a repair that starts while NO advance runs is untouched: an emptied '
        'schedule is still regenerated by Train', () async {
      await _seedRestoredProUser();
      await MigratedKey.write(
        'plan_end_date',
        DateTime(2026, 10, 25).toIso8601String(),
      );
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.toList()) {
        if (k.toString().startsWith('schedule_2026-09-1')) {
          await box.delete(k);
        }
      }
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(currentPlanProvider, (_, _) {}, fireImmediately: true);
      // Poll (bounded) instead of a fixed sleep: a loaded runner needs longer.
      final pollEnd = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(pollEnd) &&
          !box.keys.any(
            (k) =>
                k.toString().startsWith('schedule_') &&
                k.toString().compareTo('schedule_2026-10-12') >= 0,
          )) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // The repair generates from the wall-clock week (any day after the seeded
      // window ended on 2026-10-11 qualifies), so rows beyond it appear.
      final regenerated = box.keys
          .where(
            (k) =>
                k.toString().startsWith('schedule_') &&
                k.toString().compareTo('schedule_2026-10-12') >= 0,
          )
          .isNotEmpty;
      expect(
        regenerated,
        isTrue,
        reason: 'with no advance in flight the pre-existing repair runs',
      );
      await _settleHive();
    });
  });

  group('A4. owner change during the build (B-pass finding 2)', () {
    test(
      'the account switches while the plan push is awaited: the commit is '
      'refused, the other account receives no phase advance and no event',
      () async {
        await _seedRestoredProUser();
        const other = 'bbbbbbbb-3c3c-4141-9999-c0ffeec0ffee';
        SyncService.debugPlanPushOverride = () async {
          await HiveUserSession.closeAll();
          await HiveUserSession.openForUser(other);
        };
        addTearDown(() => SyncService.debugPlanPushOverride = null);

        final tickBefore = SyncService.instance.restoreCompletedTick.value;
        final out = await ensureProPhaseAfterRestore(site: 'heal');
        expect(
          SyncService.instance.restoreCompletedTick.value,
          greaterThan(tickBefore),
          reason: 'the rows were rewritten: a declined build still repaints',
        );

        expect(
          out,
          ProPhaseEnsureOutcome.declined,
          reason: 'the commit saw a different Hive owner and refused',
        );
        expect(HiveUserSession.currentOwnerFullId, other);
        expect(
          outcomes(),
          isEmpty,
          reason: 'no event is attributed to the new account',
        );
        // Back to account A: its counter was not advanced either (the commit is
        // all-or-nothing), and no write reached it through the other session.
        await HiveUserSession.closeAll();
        await HiveUserSession.openForUser(_user);
        expect(phaseNow(), 3);
      },
    );

    test('the ensure hands its uid down to the commit (presence)', () {
      final s = File(
        'lib/shared/services/pro_phase_advance.dart',
      ).readAsStringSync();
      expect(s, contains('expectedUid: uid,'));
      expect(s, contains('expectedUid: expectedUid,'));
    });

    test(
      'commitPhaseAdvance refuses a mismatched expectedUid, accepts a match',
      () async {
        await _seedRestoredProUser();
        expect(
          await commitPhaseAdvance(
            intendedPhase: 4,
            source: 't',
            expectedUid: 'someone-else',
          ),
          isFalse,
        );
        expect(phaseNow(), 3);
        expect(
          await commitPhaseAdvance(
            intendedPhase: 4,
            source: 't',
            expectedUid: _user,
          ),
          isTrue,
        );
        expect(phaseNow(), 4);
      },
    );
  });

  group('A5. the in-flight pin and the Train wait (deterministic, no race)', () {
    Future<bool> until(
      bool Function() cond, {
      Duration timeout = const Duration(seconds: 40),
    }) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        if (cond()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return cond();
    }

    bool newWindowRows() => HiveService.instance.workoutBox.keys.any(
      (k) =>
          k.toString().startsWith('schedule_') &&
          k.toString().compareTo('schedule_2026-10-12') >= 0,
    );

    Future<void> emptyWeekOne() async {
      await _seedRestoredProUser();
      await MigratedKey.write(
        'plan_end_date',
        DateTime(2026, 10, 25).toIso8601String(),
      );
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.toList()) {
        if (k.toString().startsWith('schedule_2026-09-1')) await box.delete(k);
      }
    }

    test('planWindowPinnedByAdvance: false when idle, true only while the lock '
        'is held, false under either kill switch', () async {
      expect(planWindowPinnedByAdvance, isFalse);
      final gate = Completer<void>();
      final held = withPhaseAdvanceLock<void>(() => gate.future, ifBusy: null);
      expect(planWindowPinnedByAdvance, isTrue);
      await HiveService.instance.configBox.put(
        'disable_plan_window_newer_local_guard',
        true,
      );
      expect(planWindowPinnedByAdvance, isFalse);
      await HiveService.instance.configBox.delete(
        'disable_plan_window_newer_local_guard',
      );
      await HiveService.instance.configBox.put(
        'disable_pro_phase_ensure',
        true,
      );
      expect(planWindowPinnedByAdvance, isFalse);
      await HiveService.instance.configBox.delete('disable_pro_phase_ensure');
      gate.complete();
      await held;
      expect(planWindowPinnedByAdvance, isFalse);
    });

    test('Train does NOT regenerate while an advance holds the lock, and does '
        'once it ends (never stuck on Generating)', () async {
      await emptyWeekOne();
      final gate = Completer<void>();
      final held = withPhaseAdvanceLock<void>(() => gate.future, ifBusy: null);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(currentPlanProvider, (_, _) {}, fireImmediately: true);

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        newWindowRows(),
        isFalse,
        reason: 'the repair must wait for the advance, not run beside it',
      );
      expect(container.read(currentPlanProvider).isGenerating, isTrue);

      gate.complete();
      await held;
      expect(
        await until(newWindowRows),
        isTrue,
        reason: 'after the advance ends the deferred rebuild runs the repair',
      );
      expect(
        await until(() => !container.read(currentPlanProvider).isGenerating),
        isTrue,
      );
      await _settleHive();
    });

    test(
      'kill switch disable_pro_phase_ensure: the old path is reachable - Train '
      'repairs even while the lock is held',
      () async {
        await emptyWeekOne();
        await HiveService.instance.configBox.put(
          'disable_pro_phase_ensure',
          true,
        );
        final gate = Completer<void>();
        final held = withPhaseAdvanceLock<void>(
          () => gate.future,
          ifBusy: null,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.listen(currentPlanProvider, (_, _) {}, fireImmediately: true);

        expect(await until(newWindowRows), isTrue);
        gate.complete();
        await held;
        await _settleHive();
      },
    );

    test('generated events are NOT deduped (deferred / skipped are)', () {
      debugEmitEnsureEvent(_user, 'heal', 'generated');
      debugEmitEnsureEvent(_user, 'heal', 'generated');
      debugEmitEnsureEvent(_user, 'heal', 'deferred:restore_pending');
      debugEmitEnsureEvent(_user, 'heal', 'deferred:restore_pending');
      expect(outcomes(), [
        'generated',
        'generated',
        'deferred:restore_pending',
      ]);
    });
  });

  // ─────────────── B — idempotence and concurrency ─────────────────────────

  group('B. idempotence', () {
    test('a second ensure after a build is a no-op (phase stays 4)', () async {
      await _seedRestoredProUser();
      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.generated,
      );
      expect(
        await ensureProPhaseAfterRestore(site: 'rollover'),
        ProPhaseEnsureOutcome.notExpired,
      );
      expect(phaseNow(), 4);
    });

    test('two concurrent ensures build ONE phase; the other is busy', () async {
      await _seedRestoredProUser();
      final a = ensureProPhaseAfterRestore(site: 'heal');
      final b = ensureProPhaseAfterRestore(site: 'rollover');
      final results = [await a, await b];
      expect(
        results.where((r) => r == ProPhaseEnsureOutcome.generated).length,
        1,
      );
      expect(results.where((r) => r == ProPhaseEnsureOutcome.busy).length, 1);
      expect(phaseNow(), 4);
    });
  });

  // ─────────────── C — the gates ───────────────────────────────────────────

  group('C. gates', () {
    test('restore marker unsettled → deferred, nothing built', () async {
      await _seedRestoredProUser();
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);

      final out = await ensureProPhaseAfterRestore(site: 'rollover');

      expect(out, ProPhaseEnsureOutcome.deferredRestorePending);
      expect(phaseNow(), 3);
      expect(
        events,
        isEmpty,
        reason: 'a pre-restore call has no withheld reason: silent',
      );
    });

    test('a restore that FINISHED and withheld the marker is reported once per '
        'site', () async {
      await _seedRestoredProUser();
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      SyncService.instance.debugSetLastRestoreWithheldReasonForTest(
        'restore_scheduled_workouts',
      );

      await ensureProPhaseAfterRestore(site: 'rollover');
      await ensureProPhaseAfterRestore(site: 'rollover');
      await ensureProPhaseAfterRestore(site: 'heal');

      expect(phaseNow(), 3);
      expect(outcomes(), [
        'deferred:restore_pending',
        'deferred:restore_pending',
      ], reason: 'deduped per (uid, site, outcome): one per site');
      expect(events.map((e) => e.metadata!['site']).toList(), [
        'rollover',
        'heal',
      ]);
    });

    test(
      'a failed critical restore op later settled → the next call builds',
      () async {
        await _seedRestoredProUser();
        SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
        expect(
          await ensureProPhaseAfterRestore(site: 'rollover'),
          ProPhaseEnsureOutcome.deferredRestorePending,
        );

        SyncService.instance.debugSetRestoreSettledUserIdForTest(_user);

        expect(
          await ensureProPhaseAfterRestore(site: 'rollover'),
          ProPhaseEnsureOutcome.generated,
        );
        expect(phaseNow(), 4);
      },
    );

    test(
      'a PRO user whose plan is NOT expired is left alone, silently',
      () async {
        await _seedRestoredProUser();
        await MigratedKey.write(
          'plan_end_date',
          DateTime(2026, 10, 25).toIso8601String(),
        );

        expect(
          await ensureProPhaseAfterRestore(site: 'heal'),
          ProPhaseEnsureOutcome.notExpired,
        );
        expect(phaseNow(), 3);
        expect(events, isEmpty);
      },
    );

    test('kill switch disable_pro_phase_ensure → nothing happens', () async {
      await _seedRestoredProUser();
      await HiveService.instance.configBox.put(
        'disable_pro_phase_ensure',
        true,
      );

      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.disabled,
      );
      expect(phaseNow(), 3);
      expect(events, isEmpty);
    });

    test('simulation paused → nothing happens', () async {
      await _seedRestoredProUser();
      SyncService.pausedForSimulation = true;

      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.simulation,
      );
      expect(phaseNow(), 3);
    });

    test(
      'no Hive owner (signed out / mid-swap) → nothing happens, no events',
      () async {
        await _seedRestoredProUser();
        await HiveUserSession.closeAll();

        expect(
          await ensureProPhaseAfterRestore(site: 'heal'),
          ProPhaseEnsureOutcome.ownerMissing,
        );
        expect(events, isEmpty);
      },
    );
  });

  // ─────────────── D — the local-evidence witness ──────────────────────────

  group('D. local-evidence witness (never "Phase 2" for a Phase III user)', () {
    test('settled marker + a MINTED default progress map (current_phase 1) → '
        'deferred:restore_incomplete, nothing built', () async {
      await _seedRestoredProUser();
      // What `refillIfNewWeek` -> `updateProgress` mints when the progress
      // read answered quietly empty.
      await HiveService.instance.userBox.delete('progress');
      await UserRepository.instance.saveProgress({
        'current_phase': 1,
        'current_week': 1,
      });
      expect(phaseNow(), 1, reason: 'precondition: the minted default');

      final out = await ensureProPhaseAfterRestore(site: 'heal');

      expect(out, ProPhaseEnsureOutcome.deferredRestoreIncomplete);
      expect(phaseNow(), 1, reason: 'no advance from a defaulted phase');
      expect(outcomes(), ['deferred:restore_incomplete']);
    });

    test(
      'no plan blob (window restored without the blob) → deferred',
      () async {
        await _seedRestoredProUser();
        await HiveService.instance.workoutBox.delete('current_plan');

        expect(
          await ensureProPhaseAfterRestore(site: 'heal'),
          ProPhaseEnsureOutcome.deferredRestoreIncomplete,
        );
        expect(phaseNow(), 3);
      },
    );

    test('a blob stamped phase 1 (Edit Profile reschedule) never wrongly '
        'defers a Phase III user whose progress is correct', () async {
      await _seedRestoredProUser(blobPhase: 1);

      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.generated,
      );
      expect(phaseNow(), 4);
    });

    test('no profile → deferred', () async {
      await _seedRestoredProUser();
      await HiveService.instance.userBox.delete('profile');

      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.deferredRestoreIncomplete,
      );
    });

    test('no schedule rows at all → deferred', () async {
      await _seedRestoredProUser();
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.toList()) {
        if (k.toString().startsWith('schedule_')) await box.delete(k);
      }

      expect(
        await ensureProPhaseAfterRestore(site: 'heal'),
        ProPhaseEnsureOutcome.deferredRestoreIncomplete,
      );
    });
  });

  // ─────────────── E — events ──────────────────────────────────────────────

  group('E. events', () {
    test(
      'a FREE user with an expired plan: one skipped:not_pro, heal site only',
      () async {
        await _seedRestoredProUser(pro: false);

        expect(
          await ensureProPhaseAfterRestore(site: 'rollover'),
          ProPhaseEnsureOutcome.notPro,
        );
        expect(events, isEmpty, reason: 'rollover site is silent for not-PRO');

        await ensureProPhaseAfterRestore(site: 'heal');
        await ensureProPhaseAfterRestore(site: 'heal');

        expect(outcomes(), ['skipped:not_pro'], reason: 'deduped');
        expect(phaseNow(), 3, reason: 'a free user is never advanced');
      },
    );

    test('a FREE user, expired plan, restore NOT settled: no event', () async {
      await _seedRestoredProUser(pro: false);
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);

      await ensureProPhaseAfterRestore(site: 'heal');

      expect(events, isEmpty);
    });

    test('an event for an account that is no longer the Hive owner is dropped; '
        'for the owner it is sent', () {
      debugEmitEnsureEvent('some-other-account', 'heal', 'generated');
      expect(events, isEmpty);
      debugEmitEnsureEvent(_user, 'heal', 'generated');
      expect(outcomes(), ['generated']);
    });

    test('a FREE user with a NON-expired plan: no event, no work', () async {
      await _seedRestoredProUser(pro: false);
      await MigratedKey.write(
        'plan_end_date',
        DateTime(2026, 10, 25).toIso8601String(),
      );

      await ensureProPhaseAfterRestore(site: 'heal');

      expect(events, isEmpty);
    });
  });

  // ─────────────── F — the pure evidence function ──────────────────────────

  group('F. proPhaseEvidenceGap (pure)', () {
    String? gap({
      Map<String, dynamic>? progress = const {'current_phase': 3},
      Map<String, dynamic>? profile = const {'primary_goal': 'build_muscle'},
      bool rows = true,
      int? blob = 3,
      int blocks = 2,
    }) => proPhaseEvidenceGap(
      progress: progress,
      profile: profile,
      hasScheduleRows: rows,
      blobPhase: blob,
      pastBlockCount: blocks,
    );

    test('complete state → no gap', () => expect(gap(), isNull));
    test('no progress / non-numeric phase', () {
      expect(gap(progress: null), 'no_progress_phase');
      expect(gap(progress: {'current_phase': 'x'}), 'no_progress_phase');
    });
    test(
      'a double is NOT accepted: the advance reads the phase as an int and '
      'would throw after this check passed',
      () => expect(gap(progress: {'current_phase': 3.0}), 'no_progress_phase'),
    );
    test(
      'a fractional phase is not an int',
      () => expect(gap(progress: {'current_phase': 3.5}), 'no_progress_phase'),
    );
    test('profile missing or empty', () {
      expect(gap(profile: null), 'no_profile');
      expect(gap(profile: {}), 'no_profile');
    });
    test(
      'no schedule rows',
      () => expect(gap(rows: false), 'no_schedule_rows'),
    );
    test('no blob phase', () => expect(gap(blob: null), 'no_plan_blob_phase'));
    test('a minted phase 1 against a Phase III blob', () {
      expect(gap(progress: {'current_phase': 1}), 'phase_behind_evidence');
    });
    test('a minted phase 1 against past blocks only (blob 1)', () {
      expect(
        gap(progress: {'current_phase': 1}, blob: 1, blocks: 2),
        'phase_behind_evidence',
      );
    });
    test('boundary: phase == max(blob, blocks+1) passes; one below fails', () {
      expect(gap(progress: {'current_phase': 3}, blob: 3, blocks: 2), isNull);
      expect(
        gap(progress: {'current_phase': 2}, blob: 3, blocks: 2),
        'phase_behind_evidence',
      );
      expect(gap(progress: {'current_phase': 4}, blob: 1, blocks: 3), isNull);
      expect(
        gap(progress: {'current_phase': 3}, blob: 1, blocks: 3),
        'phase_behind_evidence',
      );
    });
  });

  // ─────────────── G — call-site wiring (presence; behavior is in A) ───────

  group('G. wiring', () {
    final src = File(
      'lib/core/services/day_rollover_service.dart',
    ).readAsStringSync();

    test(
      'the heal site calls the ensure AFTER the tick bump, fire-and-forget',
      () {
        final i = src.indexOf('void reckonAndNotifyAfterRestore()');
        final j = src.indexOf('static Future<void>? debugLastEnsure');
        expect(i, isNot(-1));
        expect(j, greaterThan(i));
        final body = src.substring(i, j);
        expect(body, contains("unawaited(_runEnsure(site: 'heal'))"));
        expect(body, contains('bumpRestoreCompleted()'));
        expect(
          body.indexOf("_runEnsure(site: 'heal')"),
          greaterThan(body.indexOf('bumpRestoreCompleted()')),
          reason: 'after the bump: the repaint never waits on generation',
        );
      },
    );

    test('the rollover site calls the ensure AFTER the provider invalidations, '
        'unawaited (the restoring screen awaits this method before /home)', () {
      final i = src.indexOf('Future<void> _doRolloverWithRef(');
      final body = src.substring(i);
      final inval = body.indexOf('ref.invalidate(currentPlanProvider)');
      final call = body.indexOf("unawaited(_runEnsure(site: 'rollover'))");
      expect(inval, isNot(-1));
      expect(call, greaterThan(inval));
      expect(body.contains('await _runEnsure('), isFalse);
    });

    test('Edit Profile reschedules at the phase stored in user_progress, never '
        'a profile-map current_phase (the users row has no such column)', () {
      final s = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();
      expect(s, contains("getProgress()?['current_phase']"));
      expect(s.contains("profile['current_phase']"), isFalse);
    });

    test('the stale-rows report inside the lock is bounded (presence)', () {
      final s = File(
        'lib/shared/services/pro_phase_advance.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r"'phase_advance_declined_rows_stale',[\s\S]{0,160}\)\.timeout\(",
        ).hasMatch(s),
        isTrue,
      );
    });

    test('the plan push in generateAndSchedule is bounded', () {
      final s = File(
        'lib/core/services/workout_schedule_read_service.dart',
      ).readAsStringSync();
      expect(s, contains('planPushTimeout = const Duration(seconds: 20)'));
    });
  });
}

/// A RESTORED PRO user in the founder's state: Phase III window Mon 2026-09-14
/// → Sun 2026-10-11, progress at phase 3, the plan blob stamped [blobPhase],
/// past-phase rows for I and II, Phase III rows (the last completed on Oct 9),
/// nothing from today onward — so `isPhaseExpired()` is true on 2026-10-16.
Future<void> _seedRestoredProUser({bool pro = true, int blobPhase = 3}) async {
  if (pro) {
    await MigratedKey.write('isPro', true);
    await MigratedKey.write(
      'expiresAt',
      DateTime.now().add(const Duration(days: 365)).toIso8601String(),
    );
  }
  await MigratedKey.write(
    'plan_start_date',
    DateTime(2026, 9, 14).toIso8601String(),
  );
  await MigratedKey.write(
    'plan_end_date',
    DateTime(2026, 10, 11).toIso8601String(),
  );
  final box = HiveService.instance.workoutBox;
  await box.put('current_plan', {
    'phase': blobPhase,
    'week_plans': <dynamic>[],
  });
  Future<void> row(
    String date,
    int phase, {
    String status = 'completed',
    String type = 'workout',
  }) => box.put('schedule_$date', {
    'date': date,
    'phase': phase,
    'week': 1,
    'day_of_week': 0,
    'type': type,
    'status': status,
    'workout_name': 'x',
    'exercises': <dynamic>[],
  });
  await row('2026-07-20', 1);
  await row('2026-08-17', 2);
  await row('2026-09-14', 3);
  await row('2026-09-28', 3);
  await row('2026-10-07', 3);
  await row('2026-10-08', 3, status: 'planned');
  await row('2026-10-09', 3);
  await row('2026-10-10', 3, status: 'planned');
  await row('2026-10-11', 3, status: 'rest', type: 'rest');
  await UserRepository.instance.saveProgress({
    'current_phase': 3,
    'current_week': 4,
    'total_workouts_done': 34,
    'current_streak_weeks': 3,
    'streak_freezes_available': 1,
  });
  await UserRepository.instance.saveProfile({
    'primary_goal': 'build_muscle',
    'equipment_access': 'full_gym',
    'days_per_week': 4,
    'fitness_experience': 'intermediate',
  });
}
