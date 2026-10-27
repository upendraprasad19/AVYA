@Timeout(Duration(minutes: 5))
library;

// sync-storm-first-sweep W3 (plan docs/plans/2026-10-25-sync-storm-first-sweep.md
// section 5): the first full sweep is POSTPONED, not dropped, on a device that
// was empty at its first launch. A durable per-user marker (`syncBox
// ['fresh_device_<userId>']`) is written before any restore write and consumed at
// the sweep decision. Pure truth tables first, then the real service methods
// under `SyncHarness` through the `@visibleForTesting` wrappers, then five
// source-grep WIRING pins (presence only: `checkAndSync` cannot run under the
// harness because `_supabase.isAuthenticated` returns at its first line). The
// pins are anchored on indentation and forbid an `else`, so the shapes a
// reviewer proposed (a conditional wrapper, a second sweep call) stay red; other
// indirection is NOT covered, and the device check (plan section 9) owes the
// runtime proof.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync/first_sweep_decision.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';
import 'sync_domain_skip_harness.dart';

void main() {
  group('pure decisions', () {
    test('decideSweep: full truth table', () {
      for (final due in [false, true]) {
        for (final owed in [false, true]) {
          for (final fresh in [false, true]) {
            for (final enabled in [false, true]) {
              final expected = !due
                  ? SweepAction.none
                  : (!owed && fresh && enabled)
                      ? SweepAction.postponeAndStamp
                      : SweepAction.run;
              expect(
                decideSweep(
                    due: due,
                    owed: owed,
                    freshWithinWindow: fresh,
                    enabled: enabled),
                expected,
                reason: 'due=$due owed=$owed fresh=$fresh enabled=$enabled',
              );
            }
          }
        }
      }
    });

    test('shouldMarkFreshDevice: full truth table', () {
      final stamp = DateTime.utc(2026, 9, 1);
      for (final history in [false, true]) {
        for (final stamped in [false, true]) {
          for (final exists in [false, true]) {
            for (final enabled in [false, true]) {
              final expected = enabled && !history && !stamped && !exists;
              expect(
                shouldMarkFreshDevice(
                  hasLocalHistory: history,
                  lastFullSync: stamped ? stamp : null,
                  markerExists: exists,
                  enabled: enabled,
                ),
                expected,
                reason: 'history=$history stamped=$stamped exists=$exists '
                    'enabled=$enabled',
              );
            }
          }
        }
      }
    });

    test('isFreshWithinWindow: null, future, edges', () {
      final now = DateTime.utc(2026, 9, 1, 12);
      bool at(Duration ago) =>
          isFreshWithinWindow(marker: now.subtract(ago), now: now);
      expect(isFreshWithinWindow(marker: null, now: now), isFalse);
      expect(at(Duration.zero), isTrue);
      expect(at(const Duration(minutes: 59)), isTrue);
      expect(at(const Duration(minutes: 60)), isFalse,
          reason: 'the window is exclusive');
      expect(at(const Duration(minutes: 61)), isFalse);
      expect(
          isFreshWithinWindow(
              marker: now.add(const Duration(minutes: 1)), now: now),
          isFalse,
          reason: 'a marker from the future is stale');
    });
  });

  group('service methods under SyncHarness', () {
    final h = SyncHarness();
    final events = <String>[];
    final reasons = <String>[];

    setUp(() async {
      await h.setUp();
      events.clear();
      reasons.clear();
      ErrorTelemetry.debugOnLogEventForTests =
          (opType, {String? message}) => events.add(opType);
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required String reason, Map<String, String>? extra}) =>
              reasons.add(reason);
    });
    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      await h.tearDown();
    });

    final svc = SyncService.instance;
    String key([String uid = kTestUserId]) => freshDeviceMarkerKey(uid);
    Object? markerRaw([String uid = kTestUserId]) =>
        HiveService.instance.syncBox.get(key(uid));
    Future<void> setMarker(DateTime t, [String uid = kTestUserId]) =>
        HiveService.instance.syncBox.put(key(uid), t.toUtc().toIso8601String());
    DateTime? lastFull() {
      final raw = HiveService.instance.syncBox.get('last_full_sync');
      return raw == null ? null : DateTime.parse(raw.toString());
    }

    Future<void> seedHistory() => HiveService.instance.workoutBox
        .put('wlog_2026-09-01', {'date': '2026-09-01'});
    Future<void> expectNoPostponeEvent() async {
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty,
          reason: 'first_sweep_postponed is the device-check evidence: it '
              'must fire ONLY when a sweep was actually postponed');
    }
    Future<void> disableSwitch() => HiveService.instance.configBox
        .put('disable_first_sweep_postpone', true);

    group('markFreshDeviceForTest', () {
      test('empty device, no stamp: the marker is written with the current time',
          () async {
        final before = DateTime.now().toUtc();
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw().toString().endsWith('Z'), isTrue,
            reason: 'a UTC instant, whatever zone the device is in');
        final m = DateTime.parse(markerRaw().toString());
        expect(m.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
        expect(m.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 1))),
            isFalse);
      });

      test('first-wins: a second call does not overwrite the marker', () async {
        await svc.markFreshDeviceForTest(kTestUserId);
        final first = markerRaw();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), first);
      });

      test('two NON-awaited concurrent calls write exactly once', () async {
        var writes = 0;
        final sub = HiveService.instance.syncBox
            .watch(key: key())
            .listen((_) => writes++);
        await Future.wait([
          svc.markFreshDeviceForTest(kTestUserId),
          svc.markFreshDeviceForTest(kTestUserId),
        ]);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(writes, 1);
      });

      test('history present (a wlog_ row) -> no marker', () async {
        await seedHistory();
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), isNull);
      });

      test('history present (exlog_ rows only, no completed workout) -> no '
          'marker', () async {
        await HiveService.instance.workoutBox
            .put('exlog_2026-09-01_abcd1234', {'exercise_name': 'Row'});
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), isNull);
      });

      test('a sweep was already stamped -> no marker', () async {
        await HiveService.instance.syncBox
            .put('last_full_sync', DateTime.now().toIso8601String());
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), isNull);
      });

      test('another user id than the open session -> no marker', () async {
        await svc.markFreshDeviceForTest('other-uid');
        expect(markerRaw('other-uid'), isNull);
        expect(markerRaw(), isNull);
      });

      test('the live account is B while the open Hive session is still the '
          'previous user\'s -> no marker for B', () async {
        HiveUserSession.debugCurrentUidResolverForTests = () => 'B';
        await svc.markFreshDeviceForTest('B');
        expect(markerRaw('B'), isNull,
            reason: 'the boxes read here belong to the previous owner');
      });

      test('the live uid differs from the Hive owner (the session resolver '
          'disagrees with the open session) -> no marker', () async {
        HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), isNull);
      });

      test('kill switch engaged -> no marker', () async {
        await disableSwitch();
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(markerRaw(), isNull);
      });

      test('a closed syncBox does not throw and reports', () async {
        await HiveService.instance.syncBox.close();
        await svc.markFreshDeviceForTest(kTestUserId);
        expect(reasons, ['sync_fresh_device_mark']);
      });
    });

    group('postponeFirstSweepForTest', () {
      test('young marker, due, not owed: postponed, stamped with the MARKER '
          'time, consumed, one event', () async {
        final marker = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
        await setMarker(marker);
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isTrue);
        expect(lastFull()!.isAtSameMomentAs(marker), isTrue,
            reason: 'the stamp is the marker time, not now');
        expect(markerRaw(), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(events, ['first_sweep_postponed']);
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse,
            reason: 'consume-once');
        await Future<void>.delayed(Duration.zero);
        expect(events, ['first_sweep_postponed'],
            reason: 'the second (declined) call emits nothing');
        expect(HiveService.instance.syncBox.get('last_full_sync').toString()
            .endsWith('Z'), isTrue,
            reason: 'the stamp is the marker\'s own UTC text');
      });

      test('a marker older than the window: sweep runs, marker consumed',
          () async {
        await setMarker(DateTime.now().toUtc().subtract(const Duration(hours: 2)));
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(markerRaw(), isNull);
        expect(lastFull(), isNull);
        await expectNoPostponeEvent();
      });

      test('a marker from the future: sweep runs, marker consumed', () async {
        await setMarker(DateTime.now().toUtc().add(const Duration(minutes: 10)));
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(markerRaw(), isNull);
        expect(lastFull(), isNull);
        await expectNoPostponeEvent();
      });

      test('a malformed marker value is consumed without a report: sweep runs',
          () async {
        await HiveService.instance.syncBox.put(key(), 'not-a-date');
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(markerRaw(), isNull);
        expect(lastFull(), isNull);
        expect(reasons, isEmpty);
        await expectNoPostponeEvent();
      });

      test('an owed sweep always runs', () async {
        await HiveService.instance.syncBox.put('sync_sweep_owed', true);
        await setMarker(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(markerRaw(), isNull);
        expect(lastFull(), isNull);
        await expectNoPostponeEvent();
      });

      test('the owner changed between the marker and the decision: no stamp',
          () async {
        await setMarker(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
        HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(lastFull(), isNull);
        await expectNoPostponeEvent();
      });

      test('no marker: false and nothing written', () async {
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(lastFull(), isNull);
        expect(markerRaw(), isNull);
        await expectNoPostponeEvent();
      });

      test('kill switch engaged with a fresh marker: false, marker RETAINED, '
          'no stamp', () async {
        final marker = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
        await setMarker(marker);
        await disableSwitch();
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(markerRaw(), isNotNull);
        expect(lastFull(), isNull);
        await expectNoPostponeEvent();
      });

      test('user A\'s fresh marker does not postpone user B\'s decision',
          () async {
        await setMarker(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
        // The live account is now B: only then can the decision proceed past
        // `ownerChangedSince`, so a user-less marker key would postpone B.
        HiveUserSession.debugCurrentUidResolverForTests = () => 'B';
        expect(await svc.postponeFirstSweepForTest('B'), isFalse);
        expect(lastFull(), isNull);
        expect(markerRaw(), isNotNull, reason: 'A\'s marker is untouched');
        await expectNoPostponeEvent();
      });

      test('a closed syncBox returns false without throwing', () async {
        await setMarker(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
        await HiveService.instance.syncBox.close();
        expect(await svc.postponeFirstSweepForTest(kTestUserId), isFalse);
        expect(reasons, ['sync_first_sweep_postpone']);
      });
    });
  });

  group('wiring (source-grep, presence only)', () {
    String strip(String src) => src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final src = strip(File('lib/core/services/sync_service.dart').readAsStringSync());

    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, greaterThanOrEqualTo(0), reason: signature);
      final open = src.indexOf('{', start);
      var depth = 0;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) return src.substring(open, i + 1);
        }
      }
      fail('unbalanced braces after $signature');
    }

    test('checkAndSync: marker after the session opens, before the restore, '
        'as an unconditional statement', () {
      final b = body('Future<void> checkAndSync()');
      final marks = RegExp(r'^ {6}await _markFreshDeviceIfEmpty\(userId\);$',
              multiLine: true)
          .allMatches(b)
          .toList();
      expect(marks, hasLength(1),
          reason: 'one statement at the try-body indent: not wrapped in an if');
      expect('_markFreshDeviceIfEmpty('.allMatches(b).length, 1);
      final session = b.indexOf('_ensureSessionOpen()');
      final restore = b.indexOf('_restoreIfNeeded(userId)');
      expect(session, greaterThanOrEqualTo(0));
      expect(marks.single.start, greaterThan(session));
      expect(restore, greaterThan(marks.single.start));
    });

    test('restore core: marker after openForUser and before the first restore op, '
        'as an unconditional statement', () {
      final b = body('Future<RestoreResult> _restoreFromCloudForUserCore()');
      final marks = RegExp(r'^ {4}await _markFreshDeviceIfEmpty\(userId\);$',
              multiLine: true)
          .allMatches(b)
          .toList();
      expect(marks, hasLength(1),
          reason: 'one statement at the method-body indent: not wrapped');
      expect('_markFreshDeviceIfEmpty('.allMatches(b).length, 1);
      final open = b.indexOf('HiveUserSession.openForUser(userId)');
      final mark = marks.single.start;
      final started = b.indexOf("logEvent('restore_started'");
      final token = b.indexOf('ensureFreshToken()');
      expect(open, greaterThanOrEqualTo(0));
      expect(mark, greaterThan(open));
      expect(started, greaterThan(mark));
      expect(token, greaterThan(mark));
    });

    test('the launch sweep decision keeps its guard and wraps the sweep', () {
      final b = body('Future<void> checkAndSync()');
      expect(b, contains('shouldRunFullSweep('));
      expect(b, contains('owed: _sweepOwed'));
      final wrapper = RegExp(
          r'if \(!await _postponeFirstSweep\(userId\)\) \{\s*await weeklyFullSync\(\);\s*\}');
      expect(wrapper.allMatches(b), hasLength(1));
      expect('weeklyFullSync('.allMatches(b).length, 1,
          reason: 'the sweep is called from exactly one place');
      expect(
          RegExp(r'\}\s*else').hasMatch(b.substring(wrapper.firstMatch(b)!.start,
              wrapper.firstMatch(b)!.end + 12)),
          isFalse,
          reason: 'no else branch re-runs the sweep');
    });

    test('_restoreIfNeeded uses the extracted history check', () {
      final b = body('Future<void> _restoreIfNeeded(String userId)');
      expect(b, contains('_hasLocalWorkoutHistory()'));
      expect(b, isNot(contains("startsWith('exlog_')")),
          reason: 'no second copy of the key loop');
    });

    test('_onUserChanged holds no launch state', () {
      final b = body('void _onUserChanged()');
      expect(b, isNot(contains('_markFreshDeviceIfEmpty')));
      expect(b, isNot(contains('fresh_device')));
    });
  });
}
