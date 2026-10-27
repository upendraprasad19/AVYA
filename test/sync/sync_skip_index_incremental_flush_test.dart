@Timeout(Duration(minutes: 5))
library;

// sync-storm-first-sweep W2 (plan docs/plans/2026-10-25-sync-storm-first-sweep.md):
// `SyncSkipIndex` persists "row sent" every `flushEvery` confirmed pushes while
// the pass runs, not only at `commit`. A retry, a reload, a killed app or an
// owner abort then resumes from the flushed state instead of redoing the pass.
// Related: f3d2a7 / a8c4e5 (overlapping-pass commit), e5b2a9 (retry controller).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

const _domain = SyncSkipDomain.exlog;

/// A box that fails its first [failPuts] `put`s and otherwise delegates to a
/// real box (precedent: `_EmptyBoxStub` in guarded_box.dart). Only the members
/// `SyncSkipIndex` touches are implemented.
class _FlakyBox implements Box<dynamic> {
  _FlakyBox(this.inner, {required this.failPuts});
  final Box<dynamic> inner;
  int failPuts;
  int putAttempts = 0;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);

  @override
  bool containsKey(dynamic key) => inner.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    putAttempts++;
    if (failPuts > 0) {
      failPuts--;
      throw StateError('flaky put');
    }
    await inner.put(key, value);
  }

  @override
  Future<void> delete(dynamic key) => inner.delete(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FlakyBox.${invocation.memberName}');
}

void main() {
  final h = SyncHarness();
  final defaultResolver = SyncSkipIndex.flushEnabledResolver;
  late Box<dynamic> box;
  var puts = 0;
  StreamSubscription<BoxEvent>? sub;

  setUp(() async {
    await h.setUp();
    // A fingerprint-less row reports through ErrorTelemetry; keep it off the
    // network. Tests that assert on reports replace this closure.
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required String reason, Map<String, String>? extra}) {};
    box = await Hive.openBox<dynamic>('skip_flush_box');
    puts = 0;
    sub = box.watch(key: _domain.indexKey).listen((_) => puts++);
  });
  tearDown(() async {
    SyncSkipIndex.flushEnabledResolver = defaultResolver;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    await sub?.cancel();
    await h.tearDown();
  });

  SyncSkipIndex newIndex({
    Box<dynamic>? onBox,
    int flushEvery = 3,
    bool disabled = false,
    bool Function()? ownerChangedNow,
    Set<String> forcePushKeys = const {},
  }) =>
      SyncSkipIndex(
        box: onBox ?? box,
        domain: _domain,
        disabled: disabled,
        ownerChangedNow: ownerChangedNow ?? () => false,
        reportFailure: (_, __, ___) {},
        flushEvery: flushEvery,
        forcePushKeys: forcePushKeys,
      );

  Future<bool> confirm(SyncSkipIndex i, String key, [String? fp]) =>
      i.pushIfChanged(key, () => fp ?? 'fp-$key', () async => true);
  // The fingerprint differs from the confirmed one ("the row changed"), so the
  // skip test does not short-circuit and the push really runs and throws.
  Future<bool> failPush(SyncSkipIndex i, String key) => i.pushIfChanged(
      key, () => 'fp-$key-new', () async => throw StateError('push failed'));
  Map<String, String> stored() =>
      SyncSkipIndex.readIndex(box, _domain.indexKey);
  Future<int> settledPuts() async {
    await Future<void>.delayed(Duration.zero);
    return puts;
  }
  Future<void> resetPuts() async {
    await Future<void>.delayed(Duration.zero);
    puts = 0;
  }

  group('flush cadence', () {
    test('production default: 24 -> 0 puts, 25 -> 1 (25 entries), 26 -> 1, 50 -> 2',
        () async {
      final i = newIndex(flushEvery: kSkipIndexFlushEvery);
      for (var n = 0; n < 24; n++) {
        await confirm(i, 'k$n');
      }
      expect(await settledPuts(), 0);
      await confirm(i, 'k24');
      expect(await settledPuts(), 1);
      expect(stored(), hasLength(25), reason: 'the 25th is included');
      await confirm(i, 'k25');
      expect(await settledPuts(), 1);
      for (var n = 26; n < 50; n++) {
        await confirm(i, 'k$n');
      }
      expect(await settledPuts(), 2);
      expect(stored(), hasLength(50));
    });

    test('the constructor DEFAULT is kSkipIndexFlushEvery: a pass built the way '
        'every production site builds it flushes at the 25th confirmation',
        () async {
      expect(kSkipIndexFlushEvery, 25);
      final i = SyncSkipIndex(
        box: box,
        domain: _domain,
        disabled: false,
        ownerChangedNow: () => false,
        reportFailure: (_, __, ___) {},
      );
      for (var n = 0; n < 24; n++) {
        await confirm(i, 'd$n');
      }
      expect(await settledPuts(), 0);
      await confirm(i, 'd24');
      expect(await settledPuts(), 1);
      expect(stored(), hasLength(25));
    });

    test('100 skipped rows do not advance the counter: 24 confirmations after '
        'them still do not flush', () async {
      await box.put(_domain.indexKey, {
        for (var n = 0; n < 100; n++) 's$n': 'fp-s$n',
      });
      await resetPuts();
      final i = newIndex(flushEvery: kSkipIndexFlushEvery);
      for (var n = 0; n < 100; n++) {
        expect(await confirm(i, 's$n'), isTrue);
      }
      expect(i.skipped, 100);
      for (var n = 0; n < 24; n++) {
        await confirm(i, 'new$n');
      }
      expect(await settledPuts(), 0);
      await confirm(i, 'new24');
      expect(await settledPuts(), 1, reason: 'the 25th CONFIRMED row flushes');
    });

    test('failed, unconfirmed and fingerprint-less rows do not advance the '
        'counter', () async {
      final i = newIndex();
      for (final k in ['n1', 'n2', 'n3']) {
        await i.pushIfChanged(k, () => throw StateError('no fp'), () async => true);
      }
      await failPush(i, 'f1');
      await i.pushIfChanged('u1', () => 'fp', () async => false);
      await confirm(i, 'a');
      await confirm(i, 'b');
      expect(await settledPuts(), 0, reason: 'only 2 CONFIRMED rows so far');
      await confirm(i, 'c');
      expect(await settledPuts(), 1, reason: 'the third CONFIRMED row flushes');
      expect(stored().keys.toSet(), {'a', 'b', 'c'});
    });
  });

  group('resume', () {
    test('a killed pass (30 confirmed, no commit): a new instance skips the '
        'first 25 and pushes the last 5', () async {
      final killed = newIndex(flushEvery: kSkipIndexFlushEvery);
      for (var n = 0; n < 30; n++) {
        await confirm(killed, 'k$n');
      }
      final retry = newIndex(flushEvery: kSkipIndexFlushEvery);
      for (var n = 0; n < 30; n++) {
        await confirm(retry, 'k$n');
      }
      expect(retry.skipped, 25);
      expect(retry.pushed, 5);
    });

    test('a pass constructed after another pass flushed skips what was flushed',
        () async {
      final a = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(a, k);
      }
      final b = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(b, k);
      }
      expect(b.skipped, 3);
    });

    test('two overlapping instances that both flush keep the union', () async {
      final a = newIndex();
      final b = newIndex(); // snapshot taken BEFORE a flushes
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(a, k);
      }
      for (final k in ['b1', 'b2', 'b3']) {
        await confirm(b, k);
      }
      expect(stored().keys.toSet(), {'a1', 'a2', 'a3', 'b1', 'b2', 'b3'});
    });

    test('a forcePushKeys row is pushed again and flushed', () async {
      await box.put(_domain.indexKey, {'k1': 'fp-k1'});
      final i = newIndex(forcePushKeys: {'k1'});
      expect(await confirm(i, 'k1'), isTrue);
      expect(i.pushed, 1, reason: 'pushed although the fingerprint matched');
      await confirm(i, 'k2');
      await confirm(i, 'k3');
      expect(stored().keys.toSet(), {'k1', 'k2', 'k3'});
    });
  });

  group('removals and pending bookkeeping', () {
    test('flush -> forget k -> the drop is event 1 of the next window, so two '
        'more confirmations flush it', () async {
      final i = newIndex();
      for (final k in ['k1', 'k2', 'k3']) {
        await confirm(i, k);
      }
      await failPush(i, 'k1'); // k1 WAS stored: event 1 of the window
      expect(stored().containsKey('k1'), isTrue,
          reason: 'one event is below flushEvery: not written yet');
      await confirm(i, 'k4'); // event 2
      await confirm(i, 'k5'); // event 3: flush
      expect(stored().keys.toSet(), {'k2', 'k3', 'k4', 'k5'});
      await confirm(i, 'k6'); // event 1 of the next window
      expect(stored().containsKey('k6'), isFalse);
    });

    test('confirm k then fail k inside one window: k is not written', () async {
      final i = newIndex();
      await confirm(i, 'k1'); // event 1 of the window
      await failPush(i, 'k1'); // k1 is stored now: the drop is event 2
      await confirm(i, 'k2'); // event 3: flush
      expect(stored().keys.toSet(), {'k2'});
    });

    test('fail k then confirm k inside one window: k is written, not removed',
        () async {
      final i = newIndex();
      await failPush(i, 'k1');
      await confirm(i, 'k1');
      await confirm(i, 'k2');
      await confirm(i, 'k3');
      expect(stored().keys.toSet(), {'k1', 'k2', 'k3'});
    });

    test('dropping stored fingerprints counts toward the flush: a pass killed '
        'after three failed pushes has already removed them', () async {
      await box.put(_domain.indexKey,
          {'a': 'old-a', 'b': 'old-b', 'c': 'old-c', 'keep': 'old-keep'});
      await resetPuts();
      final i = newIndex();
      await failPush(i, 'a');
      await failPush(i, 'b');
      expect(await settledPuts(), 0);
      await failPush(i, 'c');
      expect(await settledPuts(), 1);
      expect(stored(), {'keep': 'old-keep'});
    });

    test('an UNCONFIRMED push of a stored row counts the same way', () async {
      await box.put(_domain.indexKey, {'u1': 'o', 'u2': 'o', 'u3': 'o'});
      await resetPuts();
      final i = newIndex();
      for (final k in ['u1', 'u2', 'u3']) {
        await i.pushIfChanged(k, () => 'changed', () async => false);
      }
      expect(await settledPuts(), 1);
      expect(stored(), isEmpty);
    });

    test('a failed push of a row that was never stored changes nothing '
        'durable, so it does not count', () async {
      final i = newIndex();
      for (var n = 0; n < 5; n++) {
        await failPush(i, 'never$n');
      }
      expect(await settledPuts(), 0);
    });

    test('confirmations and drops share ONE window', () async {
      await box.put(_domain.indexKey, {'a': 'old-a'});
      await resetPuts();
      final i = newIndex();
      await confirm(i, 'x'); // event 1
      await failPush(i, 'a'); // event 2 (a was stored)
      expect(await settledPuts(), 0);
      await confirm(i, 'y'); // event 3: flush
      expect(await settledPuts(), 1);
      expect(stored().keys.toSet(), {'x', 'y'});
    });

    test('edit then revert after a killed pass: the dropped fingerprint is '
        'gone, so the reverted content is pushed again', () async {
      await box.put(_domain.indexKey, {'K': 'fp1', 'Z': 'fpZ'});
      final killed = newIndex(flushEvery: 2);
      await killed.pushIfChanged(
          'K', () => 'fp2', () async => throw StateError('sets upsert failed'));
      await killed.pushIfChanged(
          'Z', () => 'fpZ2', () async => throw StateError('failed'));
      // The process dies here: no commit. The user then reverts K to its
      // original content (fingerprint fp1).
      final retry = newIndex(flushEvery: 2);
      var calls = 0;
      await retry.pushIfChanged('K', () => 'fp1', () async {
        calls++;
        return true;
      });
      expect(calls, 1, reason: 'a stale fp1 would have skipped the push');
    });

    test('a flush whose only effect is a new fingerprint on keys already in '
        'the box is written', () async {
      await box.put(
          _domain.indexKey, {'a': 'old-a', 'b': 'old-b', 'c': 'old-c'});
      await resetPuts();
      final i = newIndex();
      await confirm(i, 'a', 'new-a');
      await confirm(i, 'b', 'new-b');
      await confirm(i, 'c', 'new-c');
      expect(await settledPuts(), 1);
      expect(stored(), {'a': 'new-a', 'b': 'new-b', 'c': 'new-c'});
    });

    test('a stale forget is not re-applied after a successful flush', () async {
      await box.put(_domain.indexKey, {'k': 'old-k', 'j': 'old-j'});
      final a = newIndex(flushEvery: 1);
      await failPush(a, 'k'); // flush: k removed, pending cleared
      final b = newIndex(flushEvery: 1);
      await confirm(b, 'k', 'new-k'); // another pass confirms k again
      await failPush(a, 'j'); // a's next flush must NOT remove b's k
      expect(stored(), {'k': 'new-k'});
    });

    test('commit after flushes still prunes by liveKeys', () async {
      final i = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(i, k);
      }
      await i.commit(liveKeys: {'a1', 'a2'});
      expect(stored().keys.toSet(), {'a1', 'a2'});
    });

    test('an index wiped between two flushes is not resurrected by the second',
        () async {
      final i = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(i, k);
      }
      await SyncSkipIndex.clearAll((_) => box);
      expect(stored(), isEmpty);
      for (final k in ['b1', 'b2', 'b3']) {
        await confirm(i, k);
      }
      expect(stored().keys.toSet(), {'b1', 'b2', 'b3'},
          reason: 'pending was cleared by the first successful flush');
    });

    test('pending is cleared when the flush found nothing to change', () async {
      final k = newIndex(flushEvery: 1); // snapshot taken while the box is empty
      // Another pass persisted this exact fingerprint after k's snapshot.
      await box.put(_domain.indexKey, {'k': 'fp-k'});
      await resetPuts();
      await confirm(k, 'k'); // pushes (stale snapshot); flush finds next == read
      expect(await settledPuts(), 0, reason: 'nothing changed, so no put');
      await box.delete(_domain.indexKey);
      await confirm(k, 'k2');
      expect(stored().keys.toSet(), {'k2'},
          reason: 'the stale pending entry for k was cleared');
    });

    test('recordConfirmedAll between two flushes loses nothing', () async {
      final i = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(i, k);
      }
      await SyncSkipIndex.recordConfirmedAll(box, _domain, {'x': 'fp-x'},
          ownerChangedNow: () => false);
      for (final k in ['b1', 'b2', 'b3']) {
        await confirm(i, k);
      }
      expect(stored().keys.toSet(),
          {'a1', 'a2', 'a3', 'x', 'b1', 'b2', 'b3'});
    });

    test('a map captured before a flush is not mutated by the next flush',
        () async {
      final i = newIndex();
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(i, k);
      }
      final captured = box.get(_domain.indexKey) as Map;
      final copy = Map<dynamic, dynamic>.of(captured);
      for (final k in ['b1', 'b2', 'b3']) {
        await confirm(i, k);
      }
      expect(captured, equals(copy));
      expect(stored(), hasLength(6));
    });
  });

  group('guards', () {
    test('a disabled index never flushes and commit still deletes it', () async {
      await box.put(_domain.indexKey, {'old': 'fp'});
      await resetPuts();
      final i = newIndex(disabled: true, flushEvery: 2);
      for (var n = 0; n < 6; n++) {
        await confirm(i, 'k$n');
      }
      expect(await settledPuts(), 0);
      await i.commit(liveKeys: {'old'});
      expect(box.containsKey(_domain.indexKey), isFalse);
    });

    test('the owner changing on the flush\'s own check writes nothing',
        () async {
      var calls = 0;
      // Defence in depth: in production the closure is the stateless
      // `ownerChangedSince(userId)` and no await separates the post-push check
      // from the flush's, so the second check cannot differ from the first. The
      // call-counting closure makes the guard observable (it pins the number of
      // checks per confirmed row, deliberately).
      // flushEvery 3: each confirmed row makes 2 checks (before and after the
      // push), rows 1-3 use calls 1-6, the flush\'s own check is call 7.
      final i = newIndex(ownerChangedNow: () => ++calls == 7);
      for (final k in ['k1', 'k2', 'k3']) {
        await confirm(i, k);
      }
      expect(calls, 7);
      expect(await settledPuts(), 0);
      expect(stored(), isEmpty);
    });

    test('kill switch via the resolver: no flush, commit persists as before',
        () async {
      SyncSkipIndex.flushEnabledResolver = () => false;
      final i = newIndex();
      for (var n = 0; n < 10; n++) {
        await confirm(i, 'k$n');
      }
      expect(await settledPuts(), 0);
      await i.commit(liveKeys: {for (var n = 0; n < 10; n++) 'k$n'});
      expect(stored(), hasLength(10));
      expect(await settledPuts(), 1);
    });

    test('the switch is read once, at construction: flipping it later changes '
        'nothing for a pass already built', () async {
      SyncSkipIndex.flushEnabledResolver = () => true;
      final on = newIndex();
      SyncSkipIndex.flushEnabledResolver = () => false;
      for (final k in ['a', 'b', 'c']) {
        await confirm(on, k);
      }
      expect(await settledPuts(), 1, reason: 'built ON: still flushes');

      await resetPuts();
      final off = newIndex(); // resolver is false right now
      SyncSkipIndex.flushEnabledResolver = () => true;
      for (final k in ['d', 'e', 'f']) {
        await confirm(off, k);
      }
      expect(await settledPuts(), 0, reason: 'built OFF: never flushes');
    });

    test('the kill-switch LITERAL in configBox disables the flush', () async {
      await HiveService.instance.configBox
          .put('disable_skip_index_incremental_flush', true);
      final i = newIndex(); // default resolver -> SyncFlags getter
      for (var n = 0; n < 9; n++) {
        await confirm(i, 'k$n');
      }
      expect(await settledPuts(), 0);
    });
  });

  group('a failing put', () {
    test('first put fails: no throw, pending kept, the next flush carries both '
        'batches', () async {
      final flaky = _FlakyBox(box, failPuts: 1);
      final i = newIndex(onBox: flaky);
      for (final k in ['a1', 'a2', 'a3']) {
        await confirm(i, k); // flush 1 throws inside, swallowed
      }
      expect(stored(), isEmpty);
      for (final k in ['b1', 'b2', 'b3']) {
        await confirm(i, k); // flush 2 succeeds
      }
      expect(stored().keys.toSet(), {'a1', 'a2', 'a3', 'b1', 'b2', 'b3'});
    });

    test('repeated failures: one attempt per flushEvery and ONE report',
        () async {
      final reasons = <String>[];
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required String reason, Map<String, String>? extra}) =>
              reasons.add(reason);
      final flaky = _FlakyBox(box, failPuts: 100);
      final i = newIndex(onBox: flaky);
      for (var n = 0; n < 9; n++) {
        await confirm(i, 'k$n');
      }
      expect(flaky.putAttempts, 3, reason: 'counter reset after a failure');
      expect(reasons, ['sync_skip_flush_exlog']);
    });
  });

  group('end to end', () {
    test('an aborted exercise-log pass keeps the first 25 confirmations',
        () async {
      final wb = HiveService.instance.workoutBox;
      const day = '2026-09-01';
      for (var n = 0; n < 60; n++) {
        final name = 'Exercise ${n.toString().padLeft(2, '0')}';
        final key = 'exlog_${day}_${n.toString().padLeft(8, '0')}';
        await wb.put(key, {
          'id': key,
          'type': 'exercise_log',
          'exercise_name': name,
          'date': day,
          'logging_type': 'weight_reps',
          'is_pr': false,
          'has_warmup_sets': false,
          'created_at': '${day}T10:00:00+00:00',
          'workout_log_id': SyncService.workoutLogIdForDate(day),
          'sets': [
            {'weight_kg': 60.0, 'reps': 8, 'logged_at_ms': 1},
          ],
          'set_number': 1,
          'weight_kg': 60.0,
          'reps_completed': 8,
          'volume_kg': 480.0,
          'updated_at_ms': 1,
        });
      }
      var summaryWrites = 0;
      h.server.writeResponders['workout_log_exercises'] = (_) {
        summaryWrites++;
        if (summaryWrites == 30) {
          HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
        }
        return null;
      };
      await SyncService.instance
          .pushExerciseLogsForSyncDomain()
          .timeout(const Duration(minutes: 2));
      expect(summaryWrites, lessThan(60), reason: 'the pass aborted');
      final persisted =
          SyncSkipIndex.readIndex(wb, SyncSkipDomain.exlog.indexKey);
      expect(persisted.length, greaterThanOrEqualTo(25),
          reason: 'commit returned early on the abort; only the flush '
              'persisted the first confirmations');
    });
  });
}

