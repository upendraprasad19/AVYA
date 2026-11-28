// OI-348 B10 (diagnose a0d5f7): the single-call restore starts its readiness
// read before the Edge Function call and consumes it in step B.
//
// Behavioural: RestoreReadinessPrefetch (pure) with fake reads and callbacks.
// Wiring: the call site in sync_service.dart starts the prefetch BEFORE the
// `restore-user-snapshot` call and consumes it in the `readiness_daily` step,
// through the one shared read `_fetchReadinessRows`.
@Timeout(Duration(minutes: 1))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync/restore_readiness_prefetch.dart';

List<Map<String, dynamic>> _rows() => [
      {'date': '2026-11-20', 'level': 'green'},
      {'date': '2026-11-21', 'level': 'amber'},
    ];

Object? Function(String) _config([Map<String, Object?> m = const {}]) =>
    (k) => m[k];

class _Calls {
  final List<String> log = [];
  List<Map<String, dynamic>>? rowsGiven;
  Object? reported;

  Future<void> withRows(List<Map<String, dynamic>> rows) async {
    log.add('withRows');
    rowsGiven = rows;
  }

  Future<void> ownRead() async => log.add('ownRead');

  Future<void> report(Object e, StackTrace st) async {
    log.add('report');
    reported = e;
  }

  Future<void> consume(Future<ReadinessPrefetchOutcome>? p) =>
      RestoreReadinessPrefetch.consume(p,
          restoreWithRows: withRows,
          restoreWithOwnRead: ownRead,
          reportFailure: report);
}

void main() {
  group('RestoreReadinessPrefetch', () {
    test('ok: the rows reach the restore and it does not read again', () async {
      var reads = 0;
      final p = RestoreReadinessPrefetch.start(
        readConfig: _config(),
        read: () async {
          reads++;
          return _rows();
        },
      );
      expect(p, isNotNull);
      final c = _Calls();
      await c.consume(p);
      expect(c.log, ['withRows']);
      expect(c.rowsGiven, _rows());
      expect(reads, 1);
    });

    test('ok with NO rows: an empty answer is passed as empty, no second read',
        () async {
      final c = _Calls();
      await c.consume(RestoreReadinessPrefetch.start(
          readConfig: _config(), read: () async => <Map<String, dynamic>>[]));
      expect(c.log, ['withRows']);
      expect(c.rowsGiven, isEmpty);
    });

    test('failed: reported FIRST, then the restore does its own read '
        '(never handed an empty list)', () async {
      final c = _Calls();
      await c.consume(RestoreReadinessPrefetch.start(
          readConfig: _config(),
          read: () async => throw StateError('network down')));
      expect(c.log, ['report', 'ownRead']);
      expect(c.rowsGiven, isNull, reason: 'a failure must not become "no rows"');
      expect(c.reported, isA<StateError>());
    });

    test('a read that throws SYNCHRONOUSLY is a failed outcome, not a throw',
        () async {
      late Future<ReadinessPrefetchOutcome>? p;
      expect(
          () => p = RestoreReadinessPrefetch.start(
              readConfig: _config(), read: () => throw ArgumentError('sync')),
          returnsNormally);
      final c = _Calls();
      await c.consume(p);
      expect(c.log, ['report', 'ownRead']);
    });

    test('a throwing report still runs the own read', () async {
      final log = <String>[];
      await RestoreReadinessPrefetch.consume(
        RestoreReadinessPrefetch.start(
            readConfig: _config(), read: () async => throw StateError('x')),
        restoreWithRows: (_) async => log.add('withRows'),
        restoreWithOwnRead: () async => log.add('ownRead'),
        reportFailure: (_, _) async => throw StateError('report failed'),
      );
      expect(log, ['ownRead']);
    });

    test('switch ON: no prefetch is started, step B reads on its own',
        () async {
      var reads = 0;
      final p = RestoreReadinessPrefetch.start(
        readConfig: _config({RestoreReadinessPrefetch.killSwitchKey: true}),
        read: () async {
          reads++;
          return _rows();
        },
      );
      expect(p, isNull);
      expect(reads, 0);
      final c = _Calls();
      await c.consume(p);
      expect(c.log, ['ownRead']);
    });

    test('switch: only a stored `true` turns the overlap off; a throwing '
        'config read keeps it on', () {
      expect(RestoreReadinessPrefetch.killSwitchKey, 'disable_restore_overlap');
      expect(RestoreReadinessPrefetch.disabled(_config()), isFalse);
      expect(
          RestoreReadinessPrefetch.disabled(
              _config({'disable_restore_overlap': false})),
          isFalse);
      expect(
          RestoreReadinessPrefetch.disabled(
              _config({'disable_restore_overlap': 'true'})),
          isFalse);
      expect(
          RestoreReadinessPrefetch.disabled(
              _config({'disable_restore_overlap': true})),
          isTrue);
      expect(
          RestoreReadinessPrefetch.disabled((_) => throw StateError('closed')),
          isFalse);
    });

    test('the read starts at start(), before anything awaits it', () async {
      final started = Completer<void>();
      final release = Completer<List<Map<String, dynamic>>>();
      final p = RestoreReadinessPrefetch.start(
        readConfig: _config(),
        read: () {
          started.complete();
          return release.future;
        },
      );
      expect(started.isCompleted, isTrue,
          reason: 'the prefetch must overlap the Edge Function call');
      release.complete(_rows());
      final c = _Calls();
      await c.consume(p);
      expect(c.log, ['withRows']);
    });

    test('a failed prefetch that is NEVER consumed (legacy fallback, cancel) '
        'raises no unhandled error', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        // Held, never awaited: what the restore does on every exit before step B.
        final dropped = [
          RestoreReadinessPrefetch.start(
              readConfig: _config(),
              read: () async => throw StateError('dropped')),
          RestoreReadinessPrefetch.start(
              readConfig: _config(), read: () => throw StateError('sync drop')),
        ];
        expect(dropped, everyElement(isNotNull));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (e, _) => uncaught.add(e));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(uncaught, isEmpty);
    });
  });

  group('wiring in sync_service.dart (_attemptSingleCallRestore)', () {
    final src = File('lib/core/services/sync_service.dart').readAsStringSync();
    final health =
        File('lib/core/services/sync/sync_health.dart').readAsStringSync();
    final start = src.indexOf('Future<RestoreResult?> _attemptSingleCallRestore(');
    final end = src.indexOf('static Map? validatedSnapshotTables(');
    final body = (start >= 0 && end > start) ? src.substring(start, end) : '';

    test('the method is found', () {
      expect(body, isNotEmpty);
    });

    test('the prefetch starts BEFORE the restore-user-snapshot call, reading '
        'through the shared readiness read and the configBox', () {
      final s = body.indexOf('RestoreReadinessPrefetch.start(');
      final call = body.indexOf("callFunction('restore-user-snapshot')");
      expect(s, greaterThan(0));
      expect(call, greaterThan(s));
      final startCall = body.substring(s, call);
      expect(startCall, contains('read: () => _fetchReadinessRows(userId, since)'));
      expect(startCall, contains('readConfig: (key) => _hive.configBox.get(key)'));
    });

    test('step B consumes it under the readiness_daily label, own read with '
        'NO argument, failure reported as restore_readiness', () {
      final label = body.indexOf("'readiness_daily',");
      expect(label, greaterThan(0));
      final step = body.substring(label, body.indexOf("'streaks'", label));
      expect(step, contains('RestoreReadinessPrefetch.consume('));
      expect(step, contains('readinessPrefetch,'));
      expect(step,
          contains('_restoreReadiness(userId, since, preFetched: rows)'));
      expect(step,
          contains('restoreWithOwnRead: () => _restoreReadiness(userId, since),'));
      expect(step,
          contains("_reportSyncFailure(opType: 'restore_readiness', error: e)"));
      // between sleep_logs and streaks, as before.
      expect(body.indexOf("'sleep_logs'"), lessThan(label));
    });

    test('_restoreReadiness and the prefetch share ONE read', () {
      expect(health,
          contains('? await _fetchReadinessRows(userId, since)'));
      expect("'readiness_daily', userId,".allMatches(health).length, 1,
          reason: 'one readiness_daily restore read in sync_health.dart');
    });
  });
}
