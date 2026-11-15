// c9d2f6 (2026-10-06) — BEHAVIORAL contract for the freeze-family leg of the
// cloud→Hive `progress` restore merge.
//
// WHAT THIS EXISTS TO CATCH. `UserRepository.mergeCloudProgress` was
// cloud-non-null-wins for EVERY key outside the OI-83 monotonic fields,
// which includes `streak_freezes_available`, `streak_freezes_last_refill` and
// `streak_freezes_first_pro_grant_done`. A stale cloud row therefore overwrote a
// fresher local freeze count on every restore — and `_restoreFreezes`, the one
// place that merges them with `StreakProgressService.mergeFreezeProgress`, runs
// AFTER `_restoreUserProgress` in production (both the legacy fan-out and the
// single-call apply in `sync_service.dart`), so it only ever saw the
// already-clobbered local and could not repair it. `restoreLightweightAlways` (every cold start) and the sign-in
// hydrate never run `_restoreFreezes` at all. Live signature on the founder's
// phone, 2026-10-06 06:46:25-26: `streak_freeze_refill_done monday=2026-10-05`
// then, 1.6 s later, `refill_check lastRefill=2026-09-28`.
//
// The fix routes the family through the ONE existing rule as an
// order-independent post-pass, with an ASYMMETRIC first-PRO-grant carry, a
// push (`scheduleFreezeSyncUp`) when local is ahead of the cloud row, an owner
// guard before the write, and two kill switches. See
// docs/plans/streak-freeze-restore-ownership.md §3 (Unit 2).
//
// HOW EACH TEST DISCRIMINATES (rule 21). Group A runs the pure merge and carries
// the PRE-FIX expression inline as a negative control. Group B flips
// `disable_progress_freeze_merge` and asserts the pre-fix outcome on the SAME
// input, key by key — so the fix test and its control cannot both be green by
// accident. Group C drives the real `_restoreUserProgress` / `_restoreFreezes`
// through `SyncHarness` and counts the RPCs the stub server actually receives
// (observable only because `syncFreezes` now reads `_liveUserId`).
//
// MIRROR ROWS (labelled below) already PASS pre-fix by design: they pin what the
// new code must NOT change (a cross-device consume, a refill, a reinstall).
//
// Run: flutter test test/contracts/progress_restore_freeze_merge_behavioral_test.dart
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart' show StubRequest;
import '../sync/sync_domain_skip_harness.dart';

// IST Mondays: W = this week, P = last week, O = the week before.
const _w = '2026-10-05';
const _p = '2026-09-28';
const _o = '2026-09-21';

/// A LOCAL progress map (the singular `streak_freeze_used_dates` key).
Map<String, dynamic> _local({
  int? avail,
  String? lastRefill,
  List<String>? used,
  bool? grant,
  Map<String, dynamic> extra = const {},
}) =>
    <String, dynamic>{
      if (avail != null) 'streak_freezes_available': avail,
      if (lastRefill != null) 'streak_freezes_last_refill': lastRefill,
      if (used != null) 'streak_freeze_used_dates': used,
      if (grant != null) 'streak_freezes_first_pro_grant_done': grant,
      ...extra,
    };

/// A CLOUD `user_progress` row (the PLURAL `streak_freezes_used_dates` column).
Map<String, dynamic> _cloud({
  int? avail,
  String? lastRefill,
  List<String>? used,
  bool? grant,
  Map<String, dynamic> extra = const {},
}) =>
    <String, dynamic>{
      if (avail != null) 'streak_freezes_available': avail,
      if (lastRefill != null) 'streak_freezes_last_refill': lastRefill,
      if (used != null) 'streak_freezes_used_dates': used,
      if (grant != null) 'streak_freezes_first_pro_grant_done': grant,
      ...extra,
    };

/// The EXACT pre-fix merge: cloud-non-null-wins for every key. Negative control.
Map<String, dynamic> _preFixMerge(
  Map<String, dynamic> local,
  Map<String, dynamic> cloud,
) =>
    <String, dynamic>{
      ...local,
      for (final e in cloud.entries)
        if (e.value != null) e.key: e.value,
    };

ProgressMergeResult _merge(
        Map<String, dynamic> local, Map<String, dynamic> cloud) =>
    UserRepository.mergeCloudProgress(local: local, cloud: cloud, istToday: kTestIstToday);

// The IST calendar day every merge call in this file passes (Slice C1: the
// merge needs it for the last_workout_date ceiling).
const String kTestIstToday = '2026-10-07';

void main() {
  // ── Group A — the pure merge (no Hive: the kill-switch getters FAIL CLOSED
  //    when the box is not open, so the new behaviour is ACTIVE here). ──────
  group('A. mergeCloudProgress freeze post-pass (pure)', () {
    test('a stale cloud row does NOT overwrite a fresher local count '
        '(FAILS pre-fix)', () {
      final local = _local(avail: 2, lastRefill: _p);
      final cloud = _cloud(avail: 1, lastRefill: _o, used: [], grant: false);

      // Negative control: the pre-fix expression clobbers local with the stale row.
      final pre = _preFixMerge(local, cloud);
      expect(pre['streak_freezes_available'], 1);
      expect(pre['streak_freezes_last_refill'], _o);

      final r = _merge(local, cloud);
      expect(r.merged['streak_freezes_available'], 2);
      expect(r.merged['streak_freezes_last_refill'], _p);
      expect(r.scheduleFreezeSyncUp, isTrue,
          reason: 'local is ahead of the cloud row — it must be pushed');
    });

    test('MIRROR: a cross-device CONSUME (same week, cloud lower) wins — no '
        'refund, nothing to push', () {
      final r = _merge(_local(avail: 2, lastRefill: _p),
          _cloud(avail: 1, lastRefill: _p, used: [], grant: false));
      expect(r.merged['streak_freezes_available'], 1);
      expect(r.scheduleFreezeSyncUp, isFalse);
    });

    test('MIRROR: a cross-device REFILL (cloud newer) wins', () {
      final r = _merge(_local(avail: 1, lastRefill: _p),
          _cloud(avail: 3, lastRefill: _w, used: [], grant: false));
      expect(r.merged['streak_freezes_available'], 3);
      expect(r.merged['streak_freezes_last_refill'], _w);
      expect(r.scheduleFreezeSyncUp, isFalse);
    });

    test('MIRROR: a fresh reinstall (no local) takes the cloud row, singular '
        'key, plural key NOT copied', () {
      final r = _merge(
          <String, dynamic>{},
          _cloud(
              avail: 3, lastRefill: _w, used: ['2026-09-16'], grant: true));
      expect(r.merged['streak_freezes_available'], 3);
      expect(r.merged['streak_freezes_last_refill'], _w);
      expect(r.merged['streak_freeze_used_dates'], ['2026-09-16']);
      expect(r.merged['streak_freezes_first_pro_grant_done'], isTrue);
      expect(r.merged.containsKey('streak_freezes_used_dates'), isFalse,
          reason: 'the cloud column is plural; the local key is singular and '
              'the plural name must never be copied into the local map');
      expect(r.scheduleFreezeSyncUp, isFalse);
    });

    test('used_dates is the UNION, written to the singular key, and a '
        'local-only date schedules a push', () {
      final r = _merge(
          _local(avail: 1, lastRefill: _w, used: ['2026-09-16']),
          _cloud(
              avail: 1, lastRefill: _w, used: ['2026-09-25'], grant: false));
      expect(r.merged['streak_freeze_used_dates'],
          ['2026-09-16', '2026-09-25']);
      expect(r.scheduleFreezeSyncUp, isTrue,
          reason: 'cloud lacks 2026-09-16 — the ledger must converge up');
    });

    group('first-PRO grant carry (ASYMMETRIC: cloud flag true, local not)', () {
      test('{1,W,F}x{3,W,T} -> 3, flag adopted, nothing to push', () {
        final r = _merge(_local(avail: 1, lastRefill: _w, grant: false),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 3);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isTrue);
        expect(r.scheduleFreezeSyncUp, isFalse);
      });

      test('{1,W,F}x{3,P,T} -> {3,P}: the local week stamp was seeded under '
          'the FREE cap, so the cloud OLDER stamp is adopted and the next '
          'refillIfNewWeek tops the week up (the pre-fix outcome)', () {
        final local = _local(avail: 1, lastRefill: _w, grant: false);
        final cloud = _cloud(avail: 3, lastRefill: _p, used: [], grant: true);
        final pre = _preFixMerge(local, cloud);
        final r = _merge(local, cloud);
        expect(r.merged['streak_freezes_available'], 3);
        expect(r.merged['streak_freezes_last_refill'], _p,
            reason: 'keeping W would make refillIfNewWeek a no-op this week and '
                'silently drop the weekly +1');
        expect(r.merged['streak_freezes_last_refill'],
            pre['streak_freezes_last_refill']);
        expect(r.scheduleFreezeSyncUp, isFalse,
            reason: 'merged equals the cloud row: nothing to push');
      });

      test('{1,W,F}x{2,P,T} -> {2,P} (the +1 for week W is still owed to '
          'refillIfNewWeek, not pre-spent)', () {
        final r = _merge(_local(avail: 1, lastRefill: _w, grant: false),
            _cloud(avail: 2, lastRefill: _p, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 2);
        expect(r.merged['streak_freezes_last_refill'], _p);
        expect(r.scheduleFreezeSyncUp, isFalse);
      });

      test('{1,null,F}x{3,W,T} -> 3 via the rule\'s cloud-wins branch', () {
        final r = _merge(_local(avail: 1, grant: false),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 3);
        expect(r.merged['streak_freezes_last_refill'], _w);
      });

      test('the reinstall NO-REFUND case: {1,W}x{0,W} (flag not set) stays 0',
          () {
        final r = _merge(_local(avail: 1, lastRefill: _w),
            _cloud(avail: 0, lastRefill: _w, used: [], grant: false));
        expect(r.merged['streak_freezes_available'], 0);
      });

      test('{1,W,F}x{0,W,T} -> 0 (cloud flag true but cloud count LOWER: no '
          'carry, the consume wins)', () {
        final r = _merge(_local(avail: 1, lastRefill: _w, grant: false),
            _cloud(avail: 0, lastRefill: _w, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 0);
      });

      test('a local consume the cloud ledger has NOT seen comes off the '
          'carried count: {0,W,F,used=[d1]}x{3,W,T} -> 2, never a refund', () {
        final local = _local(
            avail: 0, lastRefill: _w, used: ['2026-10-02'], grant: false);
        final cloud = _cloud(avail: 3, lastRefill: _w, used: [], grant: true);
        expect(_preFixMerge(local, cloud)['streak_freezes_available'], 3,
            reason: 'negative control: the pre-fix cloud-wins refunded it');
        final r = _merge(local, cloud);
        expect(r.merged['streak_freezes_available'], 2);
        expect(r.merged['streak_freeze_used_dates'], ['2026-10-02']);
        expect(r.scheduleFreezeSyncUp, isTrue,
            reason: 'the cloud lacks the consumed date — the ledger must '
                'converge up');
      });

      test('two unseen consumes come off two; more than the cloud count never '
          'drives the count below the local one', () {
        final two = _merge(
            _local(
                avail: 0,
                lastRefill: _w,
                used: ['2026-10-01', '2026-10-02'],
                grant: false),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(two.merged['streak_freezes_available'], 1);
        final many = _merge(
            _local(
                avail: 0,
                lastRefill: _w,
                used: ['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'],
                grant: false),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(many.merged['streak_freezes_available'], 0);
      });

      test('MIRROR: consumes the cloud ledger ALREADY has are not subtracted '
          'again: {0,W,F,used=[d1]}x{3,W,T,used=[d1]} -> 3', () {
        final r = _merge(
            _local(
                avail: 0,
                lastRefill: _w,
                used: ['2026-10-02'],
                grant: false),
            _cloud(
                avail: 3,
                lastRefill: _w,
                used: ['2026-10-02'],
                grant: true));
        expect(r.merged['streak_freezes_available'], 3,
            reason: 'the cloud count already reflects that consume');
      });

      test('{0,W,F}x{3,W,T} with NO ledger evidence of a consume -> 3 (what '
          'the pre-fix cloud-wins did; there is nothing to subtract)', () {
        final local = _local(avail: 0, lastRefill: _w, grant: false);
        final cloud = _cloud(avail: 3, lastRefill: _w, used: [], grant: true);
        expect(_preFixMerge(local, cloud)['streak_freezes_available'], 3);
        expect(_merge(local, cloud).merged['streak_freezes_available'], 3);
      });

      test('MIRROR: {2,P,T}x{3,W,T} -> 3 (local flag already true: no carry, '
          'cloud newer wins)', () {
        final r = _merge(_local(avail: 2, lastRefill: _p, grant: true),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 3);
      });
    });

    group('a LOCAL grant the cloud has not seen (local flag true, cloud not) — '
        'no symmetric carry, but an EATEN grant is never claimed', () {
      test('{3,W,T}x{1,W,F} -> {1, flag F}: the plain rule eats the grant, so '
          'the flag stays at the cloud false and grantFirstProFreezes '
          're-grants on the next PRO boot (the pre-fix outcome)', () {
        final local = _local(avail: 3, lastRefill: _w, grant: true);
        final cloud = _cloud(avail: 1, lastRefill: _w, used: [], grant: false);
        final pre = _preFixMerge(local, cloud);
        expect(pre['streak_freezes_available'], 1);
        expect(pre['streak_freezes_first_pro_grant_done'], isFalse,
            reason: 'negative control: pre-fix copied the cloud flag');
        final r = _merge(local, cloud);
        expect(r.merged['streak_freezes_available'], 1);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isFalse,
            reason: 'claiming the grant (flag true) next to the lost count '
                'would block grantFirstProFreezes forever (B-pass A F1)');
        expect(r.scheduleFreezeSyncUp, isFalse,
            reason: 'merged equals the stale cloud row — pushing it would '
                'overwrite a cloud that may already hold the landed grant');
      });

      test('an eaten grant with a local-only used date still pushes the '
          'LEDGER (never the flag)', () {
        final r = _merge(
            _local(
                avail: 3,
                lastRefill: _w,
                used: ['2026-10-02'],
                grant: true),
            _cloud(avail: 1, lastRefill: _w, used: [], grant: false));
        expect(r.merged['streak_freezes_available'], 1);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isFalse);
        expect(r.scheduleFreezeSyncUp, isTrue);
      });

      test('MIRROR: a SURVIVING grant is claimed and pushed — {3,W,T}x{3,W,F} '
          '-> 3, flag T (the cloud only lacks the flag)', () {
        final r = _merge(_local(avail: 3, lastRefill: _w, grant: true),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: false));
        expect(r.merged['streak_freezes_available'], 3);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isTrue,
            reason: 'matches _restoreFreezes: never regress a local true');
        expect(r.scheduleFreezeSyncUp, isTrue);
      });

      test('MIRROR: local week newer — {3,W,T}x{1,P,F} keeps the granted 3 '
          'and pushes it', () {
        final r = _merge(_local(avail: 3, lastRefill: _w, grant: true),
            _cloud(avail: 1, lastRefill: _p, used: [], grant: false));
        expect(r.merged['streak_freezes_available'], 3);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isTrue);
        expect(r.scheduleFreezeSyncUp, isTrue);
      });

      test('MIRROR (F4): a phantom local grant {3,W,T}x{1,W,T} -> 1', () {
        final r = _merge(_local(avail: 3, lastRefill: _w, grant: true),
            _cloud(avail: 1, lastRefill: _w, used: [], grant: true));
        expect(r.merged['streak_freezes_available'], 1);
        expect(r.merged['streak_freezes_first_pro_grant_done'], isTrue);
        expect(r.scheduleFreezeSyncUp, isFalse);
      });
    });

    test('boot-seeded {1,W,F} against a cloud {3,P,*}: the cloud flag decides '
        '(true -> the cloud {3,P}, nothing to push; false -> local 1 kept and '
        'pushed)', () {
      final seeded = _local(avail: 1, lastRefill: _w, grant: false);
      final withFlag = _merge(seeded,
          _cloud(avail: 3, lastRefill: _p, used: [], grant: true));
      expect(withFlag.merged['streak_freezes_available'], 3);
      expect(withFlag.merged['streak_freezes_last_refill'], _p);
      expect(withFlag.scheduleFreezeSyncUp, isFalse);
      final noFlag = _merge(seeded,
          _cloud(avail: 3, lastRefill: _p, used: [], grant: false));
      expect(noFlag.merged['streak_freezes_available'], 1);
      expect(noFlag.scheduleFreezeSyncUp, isTrue);
    });

    group('steady state — the ONLY anti-push-storm protection', () {
      test('identical local and cloud => no push', () {
        final r = _merge(
            _local(
                avail: 2,
                lastRefill: _w,
                used: ['2026-09-16', '2026-09-25'],
                grant: false),
            _cloud(
                avail: 2,
                lastRefill: _w,
                used: ['2026-09-16', '2026-09-25'],
                grant: false));
        expect(r.scheduleFreezeSyncUp, isFalse);
      });

      test('unsorted / duplicated used_dates that are EQUAL AS A SET => no '
          'push', () {
        final r = _merge(
            _local(
                avail: 2,
                lastRefill: _w,
                used: ['2026-09-25', '2026-09-16', '2026-09-16']),
            _cloud(
                avail: 2,
                lastRefill: _w,
                used: ['2026-09-16', '2026-09-25'],
                grant: false));
        expect(r.scheduleFreezeSyncUp, isFalse);
      });

      test('the grant flag true on BOTH sides => no push', () {
        final r = _merge(
            _local(avail: 3, lastRefill: _w, grant: true),
            _cloud(avail: 3, lastRefill: _w, used: [], grant: true));
        expect(r.scheduleFreezeSyncUp, isFalse);
      });
    });

    test('MIRROR: a non-numeric cloud count does not throw and leaves LOCAL '
        'verbatim', () {
      final r = _merge(_local(avail: 2, lastRefill: _p),
          <String, dynamic>{'streak_freezes_available': 'garbage'});
      expect(r.merged['streak_freezes_available'], 2);
      expect(r.merged['streak_freezes_last_refill'], _p);
      expect(r.scheduleFreezeSyncUp, isFalse);
    });

    test('F7: the control-plane columns are never copied into the progress '
        'map (the sign-in hydrate passes the RAW row)', () {
      final cloud = _cloud(
        avail: 1,
        lastRefill: _w,
        used: [],
        grant: false,
        extra: {
          'user_id': 'u-1',
          'plan_json': {'schedules': {'2026-10-06': {}}},
          'sync_epoch': 3,
          'current_phase': 2,
        },
      );
      final pre = _preFixMerge(<String, dynamic>{}, cloud);
      expect(pre.containsKey('plan_json'), isTrue, reason: 'negative control');
      final r = _merge(<String, dynamic>{}, cloud);
      expect(r.merged.containsKey('plan_json'), isFalse);
      expect(r.merged.containsKey('sync_epoch'), isFalse);
      expect(r.merged.containsKey('user_id'), isFalse);
      expect(r.merged['current_phase'], 2,
          reason: 'ordinary keys still copy — only the three are skipped');
    });

    test('the engaged event is emitted ONCE per process, only when a push is '
        'scheduled', () {
      resetFreezeMergeEngagedLatchForTest();
      final seen = <String>[];
      ErrorTelemetry.debugOnLogEventForTests =
          (op, {String? message}) => seen.add('$op|$message');
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

      final quiet = _merge(_local(avail: 2, lastRefill: _w),
          _cloud(avail: 2, lastRefill: _w, used: [], grant: false));
      reportProgressDemotionsDeclined(quiet, source: 'test');
      expect(seen.where((e) => e.contains('freeze_merge_engaged')), isEmpty,
          reason: 'nothing to push => no event (else it proves nothing)');

      final ahead = _merge(_local(avail: 2, lastRefill: _p),
          _cloud(avail: 1, lastRefill: _o, used: [], grant: false));
      reportProgressDemotionsDeclined(ahead, source: 'test');
      reportProgressDemotionsDeclined(ahead, source: 'test');
      expect(seen.where((e) => e.contains('freeze_merge_engaged')), hasLength(1));
    });
  });

  // ── Group B — the two kill switches (Hive needed for configBox). ────────
  group('B. kill switches restore the pre-fix copy verbatim', () {
    late Directory dir;
    setUp(() async => dir = await setUpHiveForTests());
    tearDown(() async => tearDownHiveForTests(dir));

    final local = _local(
        avail: 2, lastRefill: _p, used: ['2026-09-16'], grant: false);
    final cloud = _cloud(
      avail: 1,
      lastRefill: _o,
      used: ['2026-09-25'],
      grant: true,
      extra: {
        'user_id': 'u-1',
        'plan_json': {'x': 1},
        'sync_epoch': 4,
      },
    );

    void expectPreFix(ProgressMergeResult r) {
      final pre = _preFixMerge(local, cloud);
      // Key by key — a `merged == pre` over a fixture that carries none of the
      // keys would pass vacuously (feedback_green_check_input_set_width).
      for (final k in const [
        'streak_freezes_available',
        'streak_freezes_last_refill',
        'streak_freezes_first_pro_grant_done',
        'streak_freezes_used_dates',
        'user_id',
        'plan_json',
        'sync_epoch',
      ]) {
        expect(r.merged[k], pre[k], reason: 'switch set => `$k` is the pre-fix '
            'cloud-non-null-wins value');
      }
      expect(r.merged['streak_freezes_available'], 1);
      expect(r.merged.containsKey('plan_json'), isTrue);
      expect(r.scheduleFreezeSyncUp, isFalse);
    }

    test('disable_progress_freeze_merge => pre-fix, key by key', () async {
      await HiveService.instance.configBox
          .put(UserRepository.kDisableProgressFreezeMergeKey, true);
      expectPreFix(_merge(local, cloud));
    });

    test('ONLY the wider OI-83 switch set => the same pre-fix result',
        () async {
      await HiveService.instance.configBox.put(
          UserRepository.kDisableProgressRestoreMonotonicMergeKey, true);
      expectPreFix(_merge(local, cloud));
    });

    test('NEITHER switch set => the fix is active (the control for the two '
        'tests above)', () {
      final r = _merge(local, cloud);
      expect(r.merged['streak_freezes_available'], 2);
      expect(r.merged.containsKey('plan_json'), isFalse);
    });
  });

  // ── Group C — the REAL restore writers, observed through the stub server. ─
  group('C. real _restoreUserProgress / _restoreFreezes (SyncHarness)', () {
    final h = SyncHarness();
    setUp(() async {
      await h.setUp();
      // The harness's stub server is shared across every test() in this file
      // (only clear() resets `requests`); these tests assert RPC COUNTS, so a
      // straggler from the previous test must not leak in.
      h.server.clear();
    });
    tearDown(() async {
      resetFreezeMergeEngagedLatchForTest();
      await h.tearDown();
    });

    Future<void> seed(Map<String, dynamic> progress) =>
        HiveService.instance.userBox.put('progress', progress);

    Map progressMap() => HiveService.instance.userBox.get('progress') as Map;

    List<StubRequest> rpcs() => h.server.requests
        .where((r) => r.path == '/rest/v1/rpc/update_streak_progress')
        .toList();

    /// `syncFreezes` is fired `unawaited` — wait (bounded) for the RPC to land.
    Future<void> settle({required bool expectRpc}) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (expectRpc && rpcs().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      // Let any straggler (the retry GET, the flag upsert) land too.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    Map<String, dynamic> cloudRow({
      required int avail,
      required String lastRefill,
      List<String> used = const [],
      bool grant = false,
      int version = 7,
    }) =>
        {
          'user_id': kTestUserId,
          'streak_freezes_available': avail,
          'streak_freezes_last_refill': lastRefill,
          'streak_freezes_used_dates': used,
          'streak_freezes_first_pro_grant_done': grant,
          'streak_progress_version': version,
        };

    test('lightweight shape: a stale cloud row leaves local {2,P} and PUSHES it '
        '(one RPC carrying the merged values)', () async {
      await seed(_local(avail: 2, lastRefill: _p, used: []));
      await SyncService.instance.restoreUserProgressForTest(kTestUserId,
          preFetched: [cloudRow(avail: 1, lastRefill: _o)]);

      expect(progressMap()['streak_freezes_available'], 2);
      expect(progressMap()['streak_freezes_last_refill'], _p);
      expect(progressMap()['streak_progress_version'], 7,
          reason: 'the server-owned lock counter is still cloud-always-wins');

      await settle(expectRpc: true);
      expect(rpcs(), isNotEmpty,
          reason: 'local is ahead of the cloud row — syncFreezes must run');
      final body = rpcs().first.body! as Map;
      expect(body['p_freezes_available'], 2);
      expect(body['p_freezes_last_refill'], _p);
      expect(body['p_expected_version'], 7);
    });

    test('PRODUCTION ORDER (progress then freezes): the final local state is '
        '{2,P}; with the kill switch it is the pre-fix {1,O}', () async {
      Future<void> run() async {
        await SyncService.instance.restoreUserProgressForTest(kTestUserId,
            preFetched: [cloudRow(avail: 1, lastRefill: _o)]);
        await SyncService.instance.restoreFreezesForTest(kTestUserId,
            preFetched: cloudRow(avail: 1, lastRefill: _o));
      }

      await seed(_local(avail: 2, lastRefill: _p, used: []));
      await run();
      expect(progressMap()['streak_freezes_available'], 2);
      expect(progressMap()['streak_freezes_last_refill'], _p);
      await settle(expectRpc: true);

      // The control: the SAME input with the switch set is the pre-fix result.
      await HiveService.instance.configBox
          .put(UserRepository.kDisableProgressFreezeMergeKey, true);
      await seed(_local(avail: 2, lastRefill: _p, used: []));
      await run();
      expect(progressMap()['streak_freezes_available'], 1,
          reason: 'pre-fix: the clobber leaves `_restoreFreezes` nothing to repair');
      expect(progressMap()['streak_freezes_last_refill'], _o);
      await settle(expectRpc: false);
    });

    test('MIRROR: a cross-device consume (cloud lower, same week) is adopted '
        'and NOTHING is pushed', () async {
      await seed(_local(avail: 2, lastRefill: _p, used: []));
      await SyncService.instance.restoreUserProgressForTest(kTestUserId,
          preFetched: [cloudRow(avail: 1, lastRefill: _p)]);
      expect(progressMap()['streak_freezes_available'], 1);
      await settle(expectRpc: false);
      expect(rpcs(), isEmpty);
    });

    test('STEADY STATE: two consecutive restores of identical state send ZERO '
        'RPCs', () async {
      await seed({
        ..._local(
            avail: 2,
            lastRefill: _w,
            used: ['2026-09-16', '2026-09-25'],
            grant: false),
        'streak_progress_version': 3,
      });
      final row = cloudRow(
          avail: 2,
          lastRefill: _w,
          used: ['2026-09-16', '2026-09-25'],
          version: 3);
      await SyncService.instance
          .restoreUserProgressForTest(kTestUserId, preFetched: [row]);
      await SyncService.instance
          .restoreUserProgressForTest(kTestUserId, preFetched: [row]);
      await settle(expectRpc: false);
      expect(rpcs(), isEmpty,
          reason: 'a restore that always differs would push on every cold start');
    });

    // B-pass reviewer A F6: the sign-in hydrate is the one writer of this merge
    // that no restore test reaches, and its push is the only thing that stops a
    // stale cloud row from winning on the NEXT restore. Drive the real method.
    Future<void> hydrate(Map<String, dynamic> cloudProgress) async {
      h.server.getResponders['user_profile'] = (_) => [
            {
              'user_id': kTestUserId,
              'primary_goal': 'build_muscle',
              'height_cm': 175,
            }
          ];
      h.server.getResponders['user_progress'] = (_) => [cloudProgress];
      addTearDown(h.server.getResponders.clear);
      final user = User(
        id: kTestUserId,
        appMetadata: const <String, dynamic>{},
        userMetadata: const <String, dynamic>{},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        email: 'hydrate@test.invalid',
      );
      await AuthSessionBootstrapper.instance.hydrateFromCloud(user);
    }

    test('SIGN-IN HYDRATE: a stale cloud row leaves local {2,P} and PUSHES it '
        '(behavioral)', () async {
      await seed(_local(avail: 2, lastRefill: _p, used: []));
      await hydrate(cloudRow(avail: 1, lastRefill: _o));

      expect(progressMap()['streak_freezes_available'], 2,
          reason: 'the hydrate used to copy the stale cloud count over local');
      expect(progressMap()['streak_freezes_last_refill'], _p);
      await settle(expectRpc: true);
      expect(rpcs(), isNotEmpty,
          reason: 'local is ahead of the cloud row — the hydrate must push');
      expect((rpcs().first.body! as Map)['p_freezes_available'], 2);
    });

    // Slice C1: BOTH production callers must hand the merge the IST day from
    // the (test-overridable) clock. The clock is set to a day far from the real
    // one, so a caller that passed raw DateTime.now() or no day would accept the
    // out-of-range cloud date below and fail these.
    //   clock 2026-03-01 (IST) => ceiling 2026-03-02.
    Future<void> withClock(Future<void> Function() body) async {
      setTestClockTo(DateTime(2026, 3, 1, 12));
      addTearDown(resetTestClock);
      await body();
    }

    test('C1 lightweight restore: the merge gets the IST day from the clock '
        '(a date past tomorrow is refused; a stale date does not win)',
        () async {
      await withClock(() async {
        await seed({
          ..._local(avail: 2, lastRefill: _p, used: []),
          'last_workout_date': '2026-03-01',
        });
        await SyncService.instance.restoreUserProgressForTest(kTestUserId,
            preFetched: [
              {
                ...cloudRow(avail: 2, lastRefill: _p),
                'last_workout_date': '2026-02-20',
              }
            ]);
        expect(progressMap()['last_workout_date'], '2026-03-01',
            reason: 'a stale cloud date must not move local backwards');

        await seed({
          ..._local(avail: 2, lastRefill: _p, used: []),
        }..remove('last_workout_date'));
        await SyncService.instance.restoreUserProgressForTest(kTestUserId,
            preFetched: [
              {
                ...cloudRow(avail: 2, lastRefill: _p),
                'last_workout_date': '2026-03-05', // clock + 4 days
              }
            ]);
        expect(progressMap()['last_workout_date'], isNull,
            reason: 'a date past IST-today + 1 is malformed, never stored');
      });
    });

    test('C1 sign-in hydrate: the merge gets the IST day from the clock',
        () async {
      await withClock(() async {
        await seed({
          ..._local(avail: 2, lastRefill: _p, used: []),
          'last_workout_date': '2026-03-01',
        });
        await hydrate({
          ...cloudRow(avail: 2, lastRefill: _p),
          'last_workout_date': '2026-02-20',
        });
        expect(progressMap()['last_workout_date'], '2026-03-01');

        await seed({
          ..._local(avail: 2, lastRefill: _p, used: []),
        }..remove('last_workout_date'));
        await hydrate({
          ...cloudRow(avail: 2, lastRefill: _p),
          'last_workout_date': '2026-03-05',
        });
        expect(progressMap()['last_workout_date'], isNull);
      });
    });

    test('MIRROR: a SIGN-IN HYDRATE whose cloud row already equals local '
        'pushes NOTHING', () async {
      await seed(_local(avail: 2, lastRefill: _w, used: []));
      await hydrate(cloudRow(avail: 2, lastRefill: _w));

      expect(progressMap()['streak_freezes_available'], 2);
      await settle(expectRpc: false);
      expect(rpcs(), isEmpty,
          reason: 'no divergence, so no push (a hydrate that always pushed '
              'would write on every sign-in)');
    });

    test('OWNER GUARD: a restore captured for another account writes NOTHING '
        'and pushes NOTHING (the e5c2d1 sink-side guard)', () async {
      await seed(_local(avail: 2, lastRefill: _p, used: []));
      final before = Map<String, dynamic>.from(progressMap());
      HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
      await SyncService.instance.restoreUserProgressForTest(kTestUserId,
          preFetched: [cloudRow(avail: 1, lastRefill: _o)]);
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      expect(Map<String, dynamic>.from(progressMap()), before);
      await settle(expectRpc: false);
      expect(rpcs(), isEmpty);
    });
  });

  // ── Group D — presence pins for the callers that are network-bound. ──────
  group('D. wiring (PRESENCE only — the behaviour is Group C)', () {
    String read(String path) => File(path).readAsStringSync();

    test('the sign-in hydrate pushes when the freeze merge asks for it', () {
      final src = read('lib/core/services/auth_session_bootstrapper.dart');
      final i = src.indexOf('progressMerge.scheduleFreezeSyncUp');
      expect(i, greaterThan(-1));
      expect(src.substring(i, i + 160), contains('syncFreezes()'));
      expect(src.indexOf("userBox.put('progress', progressMerge.merged)"),
          lessThan(i),
          reason: 'the push must follow the write — syncFreezes reads Hive');
    });

    test('syncFreezes derives the account from _liveUserId', () {
      final src = read('lib/core/services/sync/sync_restore_completeness.dart');
      final start = src.indexOf('Future<void> syncFreezes()');
      final body = src.substring(start, start + 900);
      expect(body, contains('final userId = _liveUserId;'));
    });

    test('_restoreUserProgress guards its write with ownerChangedSince and '
        'pushes after it', () {
      final src = read('lib/core/services/sync/sync_profile.dart');
      final start = src.indexOf('Future<void> _restoreUserProgress(');
      final end = src.indexOf('Future<void> _restoreUserPreferences(');
      final body = src.substring(start, end);
      final guard = body.indexOf('ownerChangedSince(userId)');
      final put = body.indexOf("_hive.userBox.put('progress'");
      final push = body.indexOf('result.scheduleFreezeSyncUp');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(put));
      expect(put, lessThan(push));
    });
  });
}
