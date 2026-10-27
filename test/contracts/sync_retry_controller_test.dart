// test/contracts/sync_retry_controller_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit B). An OUTAGE-SHAPED PUSH failure
// schedules a reachability-gated re-sweep on 30s → 2m → 10m (capped at 6 failed
// runs); anything else never does; recovery clears `paused` and resets the
// backoff; an account switch drops everything including an in-flight run.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_retry_controller.dart';

// Real shapes from client_errors, 2026-10-01 outage.
final Object _cf521 = Exception(
    'PostgrestException(message: error code: 521\n, code: 521, details: <none>, hint: null)');
final Object _pgrst002 = Exception(
    'PostgrestException(message: Could not query the database for the schema cache. Retrying., code: PGRST002, details: null, hint: null)');
final Object _dns = Exception(
    "ClientException with SocketException: Failed host lookup: 'dedsavbjuwgarrhphgnl.supabase.co' (OS Error: No address associated with hostname, errno = 7)");
final Object _webLoadFailed = Exception(
    'ClientException: Load failed, uri=https://dedsavbjuwgarrhphgnl.supabase.co/rest/v1/workout_logs?on_conflict=user_id');
final Object _ceiling45 =
    TimeoutException('Future not completed', const Duration(seconds: 45));
// A deterministic failure: the same payload can never succeed.
final Object _dup23505 =
    Exception('PostgrestException(message: duplicate key, code: 23505, details: x, hint: null)');

class _Harness {
  int probes = 0;
  int sweeps = 0;
  bool reachable = true;
  bool disabled = false;
  Completer<bool>? probeGate;
  Completer<void>? sweepGate;
  void Function()? duringSweep;
  late final SyncRetryController c;

  _Harness({int maxAttempts = kSyncRetryMaxAttempts}) {
    c = SyncRetryController(
      probe: () async {
        probes++;
        final g = probeGate;
        if (g != null) return g.future;
        return reachable;
      },
      sweep: () async {
        sweeps++;
        duringSweep?.call();
        final g = sweepGate;
        if (g != null) await g.future;
      },
      jitter: (d) => d, // deterministic
      maxAttempts: maxAttempts,
      isDisabled: () => disabled,
    );
  }

  void fail([String op = 'upsert_weight_log', Object? e]) =>
      c.noteFailure(e ?? _cf521, opType: op);
}

void main() {
  group('outage predicate', () {
    test('httpStatusOfError reads the status from the real shapes, never a UUID or a PG code',
        () {
      expect(httpStatusOfError(_cf521), 521);
      expect(httpStatusOfError(Exception('FunctionException(status: 503, details: x)')), 503);
      expect(httpStatusOfError(_dup23505), isNull, reason: '5-digit PG code is not an HTTP status');
      expect(httpStatusOfError(Exception('id 5f0a13b2-401a-4bcc-8403-dddddddddddd failed')),
          isNull);
    });

    test('outage shapes ARE retryable', () {
      for (final e in [
        _cf521,
        _pgrst002,
        _dns,
        _webLoadFailed,
        _ceiling45,
        const SocketException('Failed host lookup'),
        const SocketException('Broken pipe'), // no other alternative matches this one
        Exception('PostgrestException(message: x, code: 504)'),
        Exception('PostgrestException(message: x, code: 429)'),
        Exception('PostgrestException(message: canceling statement, code: 57014)'),
      ]) {
        expect(isOutageShapedFailure(e), isTrue, reason: '$e');
      }
    });

    test('MIRROR: answered-and-rejected / unknown shapes are NOT retryable', () {
      for (final e in [
        _dup23505,
        Exception('PostgrestException(message: x, code: 400)'),
        Exception('PostgrestException(message: JWT expired, code: 401)'),
        Exception('PostgrestException(message: x, code: 403)'),
        Exception('PostgrestException(message: x, code: 404)'),
        Exception('PostgrestException(message: x, code: 409)'),
        Exception('column foo does not exist 42703'),
        StateError('bad state'),
        Exception('id 5f0a13b2-401a-4bcc-8403-dddddddddddd failed'),
      ]) {
        expect(isOutageShapedFailure(e), isFalse, reason: '$e');
      }
    });

    test('push op types are allowlisted; reads/restores/bookkeeping are not', () {
      for (final op in [
        'upsert_weight_log',
        'upsert_workout_log',
        'sync_workout_plan',
        'restore_sync_weight', // a PUSH op that hit the 45s ceiling in weeklyFullSync
        'weekly_full_sync',
      ]) {
        expect(isPushFailureOpType(op), isTrue, reason: op);
      }
      for (final op in [
        'sync_fitness_summary', // a READ
        'sync_custom_items', // pushed by checkAndSync / writers — the sweep does not re-send it
        'restore_workout_logs',
        'restore_weight_logs',
        'realtime_handler_weight_logs',
        'push_snapshot',
        'check_and_sync',
        'onboarding_sync',
        'scheduled_workout_fk_recovered',
        'scheduled_workout_template_orphaned',
        'restore_from_cloud_for_user',
      ]) {
        expect(isPushFailureOpType(op), isFalse, reason: op);
      }
    });

    test('delay schedule is 30s, 2m, 10m and caps at the last entry', () {
      expect(syncRetryDelay(0), const Duration(seconds: 30));
      expect(syncRetryDelay(1), const Duration(minutes: 2));
      expect(syncRetryDelay(2), const Duration(minutes: 10));
      expect(syncRetryDelay(9), const Duration(minutes: 10));
      expect(syncRetryDelay(-3), const Duration(seconds: 30));
    });

    test('the run ceilings are pinned: 5 min sweep, 10 s manual cooldown, 6 failed runs', () {
      expect(kSyncRetrySweepCeiling, const Duration(minutes: 5));
      expect(kSyncRetryManualCooldown, const Duration(seconds: 10));
      expect(kSyncRetryMaxAttempts, 6);
    });

    test('kill-switch predicate: only literal true disables', () {
      expect(isSyncRetryDisabled(true), isTrue);
      expect(isSyncRetryDisabled(false), isFalse);
      expect(isSyncRetryDisabled(null), isFalse);
      expect(isSyncRetryDisabled('true'), isFalse);
    });
  });

  group('noteFailure filtering', () {
    test('only an outage-shaped PUSH failure is accepted (and counted)', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail('upsert_weight_log', _cf521);
        expect(h.c.retryableFailureSeq, 1);
        h.fail('restore_weight_logs', _cf521); // wrong opType
        h.fail('upsert_weight_log', _dup23505); // wrong shape
        h.c.noteFailure('PostgrestException(code: 521)', // a telemetry-queue REPLAY
            opType: 'upsert_weight_log');
        expect(h.c.retryableFailureSeq, 1);
      });
    });

    test('kill-switch on → inert: nothing counted, nothing paused', () {
      fakeAsync((async) {
        final h = _Harness()..disabled = true;
        h.fail();
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);
        expect(h.c.retryableFailureSeq, 0);
        expect(h.probes, 0);
      });
    });

    test('a non-retryable failure never schedules anything', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail('upsert_weight_log', _dup23505);
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);
        expect(h.probes, 0);
        expect(h.sweeps, 0);
      });
    });
  });

  group('controller', () {
    test('a failure pauses and sweeps after 30s, not before', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        expect(h.c.paused.value, isTrue);
        async.elapse(const Duration(seconds: 29));
        expect(h.sweeps, 0, reason: 'must wait the full 30s');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse, reason: 'clean sweep clears paused');
      });
    });

    test('an unreachable probe does NOT sweep and backs off to 2 minutes', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 0, reason: 'no sweep while the server is unreachable');
        expect(h.c.paused.value, isTrue);

        async.elapse(const Duration(minutes: 1, seconds: 50)); // t=141s < 150s
        async.flushMicrotasks();
        expect(h.probes, 1, reason: 'second attempt waits the 2m step');

        h.reachable = true;
        async.elapse(const Duration(seconds: 15)); // t=156s
        async.flushMicrotasks();
        expect(h.probes, 2);
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
      });
    });

    test('a burst of failures yields ONE sweep (single timer)', () {
      fakeAsync((async) {
        final h = _Harness();
        for (var i = 0; i < 25; i++) {
          h.fail();
        }
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
      });
    });

    test('a failure DURING the sweep keeps paused and re-arms at the next step', () {
      fakeAsync((async) {
        final h = _Harness();
        h.duringSweep = () => h.fail();
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isTrue, reason: 'sweep itself failed again');

        h.duringSweep = null;
        // The 2m step was armed at t≈30s → fires at t≈150s. Now t=31s:
        // +110s → t=141s still waiting; +15s → t=156s fires.
        async.elapse(const Duration(minutes: 1, seconds: 50));
        async.flushMicrotasks();
        expect(h.sweeps, 1, reason: 'next attempt is the 2m step, not 30s');
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(h.sweeps, 2);
        expect(h.c.paused.value, isFalse);
      });
    });

    test('MIRROR: recovery resets the backoff — the next outage waits 30s again', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.c.paused.value, isFalse);

        h.fail();
        async.elapse(const Duration(seconds: 29));
        expect(h.sweeps, 1, reason: 'second outage must not inherit a longer wait');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(h.sweeps, 2);
      });
    });

    test('the cap: after 6 failed runs it stops and clears paused (no endless loop)', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        async.elapse(const Duration(hours: 3));
        async.flushMicrotasks();
        expect(h.probes, 6, reason: '30s,2m,10m,10m,10m,10m then give up');
        expect(h.c.paused.value, isFalse,
            reason: 'the banner must not claim "retrying" forever');
        // A later failure starts a FRESH cycle from the 30s step.
        h.reachable = true;
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
      });
    });

    test('retryNow() sweeps immediately and cancels the pending timer', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(h.sweeps, 1, reason: 'the cancelled timer must not double-fire');
      });
    });

    test('retryNow() against an unreachable server does NOT advance the backoff', () {
      fakeAsync((async) {
        final h = _Harness()..reachable = false;
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1);
        expect(h.sweeps, 0);
        // A manual tap must re-arm the SAME 30s step, not escalate to 2m.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.probes, 2);
      });
    });

    test('retryNow() spam: taps inside the 10s cooldown are ONE probe+sweep', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1);
        h.fail(); // a second failure re-pauses (a 30s timer is armed)
        h.c.retryNow(); // inside the cooldown → ignored
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.probes, 1, reason: 'a tap inside the cooldown must not probe');
        async.elapse(kSyncRetryManualCooldown + const Duration(seconds: 1));
        h.c.retryNow(); // after the cooldown → runs
        async.flushMicrotasks();
        expect(h.probes, 2);
      });
    });

    test('manualRetryAllowed is false for the cooldown after a tap and true again after it (the queue-drain fan-out reads it)', () {
      fakeAsync((async) {
        final h = _Harness();
        expect(h.c.manualRetryAllowed, isTrue, reason: 'nothing tapped yet');
        h.fail();
        h.c.retryNow();
        async.flushMicrotasks();
        expect(h.c.manualRetryAllowed, isFalse, reason: 'inside the cooldown');
        async.elapse(kSyncRetryManualCooldown - const Duration(seconds: 1));
        expect(h.c.manualRetryAllowed, isFalse, reason: 'still inside the cooldown');
        async.elapse(const Duration(seconds: 2));
        expect(h.c.manualRetryAllowed, isTrue, reason: 'cooldown over');
      });
    });

    test('disabled mirrors the kill-switch read (weeklyFullSync takes no ticket while it is on)', () {
      final h = _Harness();
      expect(h.c.disabled, isFalse);
      h.disabled = true;
      expect(h.c.disabled, isTrue);
    });

    test('a sweep that never completes is abandoned at the ceiling; the cycle continues', () {
      fakeAsync((async) {
        final h = _Harness()..sweepGate = Completer<void>();
        h.fail();
        async.elapse(const Duration(seconds: 31)); // the run starts and parks in the sweep
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        async.elapse(kSyncRetrySweepCeiling + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(h.c.paused.value, isTrue,
            reason: 'a hung sweep is a FAILED run — never reported as recovery');
        h.sweepGate = null;
        async.elapse(const Duration(minutes: 3)); // the re-armed 2m step (attempt 1)
        async.flushMicrotasks();
        expect(h.sweeps, 2, reason: '_running must have been released');
        expect(h.c.paused.value, isFalse);
      });
    });

    test('a sweep that THROWS is a failed run: the next attempt is the 2m step, not 30s again', () {
      fakeAsync((async) {
        final h = _Harness();
        h.duringSweep = () => throw StateError('sweep blew up');
        h.fail();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isTrue);
        h.duringSweep = null;
        // A 30 s step would fire at t=60s; the 2 m step at t=150s.
        async.elapse(const Duration(seconds: 40)); // t=71s
        async.flushMicrotasks();
        expect(h.sweeps, 1, reason: 'the catch path must escalate the backoff');
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(h.sweeps, 2);
        expect(h.c.paused.value, isFalse);
      });
    });

    test('reset() cancels a pending sweep and clears paused (account switch)', () {
      fakeAsync((async) {
        final h = _Harness();
        h.fail();
        h.c.reset();
        expect(h.c.paused.value, isFalse);
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(h.probes, 0);
        expect(h.sweeps, 0);
      });
    });

    test('reset() while a run is IN FLIGHT: the old run is a no-op and the new owner still gets retried',
        () {
      fakeAsync((async) {
        final gate = Completer<bool>();
        final h = _Harness()..probeGate = gate;
        h.fail();
        async.elapse(const Duration(seconds: 31)); // run 1 parked on the probe
        expect(h.probes, 1);

        h.c.reset(); // account switch mid-probe
        h.probeGate = null;
        h.fail(); // the NEW owner's first failure — must not be swallowed
        expect(h.c.paused.value, isTrue);

        gate.complete(true); // the OLD run wakes up
        async.flushMicrotasks();
        expect(h.sweeps, 0, reason: 'a stale run must not sweep under the new owner');
        expect(h.c.paused.value, isTrue, reason: 'nor clear the new owner\'s flag');

        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(h.sweeps, 1);
        expect(h.c.paused.value, isFalse);
      });
    });
  });

  group('classifier edges (B-pass F5/F6)', () {
    Object pg(String msg, String code, {String details = 'null'}) => Exception(
        'PostgrestException(message: $msg, code: $code, details: $details, hint: null)');

    test('EVERY outage text alternative is retryable (table-driven, incl. Chrome\'s "Failed to fetch")', () {
      for (final e in <Object>[
        Exception('SocketException: Connection refused'),
        Exception('Failed host lookup: x.supabase.co'),
        Exception('Connection reset by peer'),
        Exception('Connection closed before full header was received'),
        Exception('Connection abort'),
        Exception('Connection terminated'),
        Exception('Network is unreachable'),
        Exception('Software caused connection abort'),
        Exception('ClientException: Failed to fetch, uri=https://x.supabase.co/rest/v1/y'),
        Exception('ClientException: Load failed'),
        Exception('XMLHttpRequest error.'),
        Exception('TimeoutException after 0:00:45.000000'),
        Exception('TlsException: Handshake error'),
        Exception('HandshakeException: Connection terminated during handshake'),
        Exception('net::ERR_INTERNET_DISCONNECTED'),
        Exception('request timed out'),
        pg('Could not query the database', 'PGRST002'),
        pg('x', 'PGRST000'),
        pg('x', '57014'),
        pg('x', '57P01'),
        pg('x', '53300'),
        pg('x', '53200'), // out of memory
        pg('x', '08006'), // connection failure
        pg('x', '40001'), // serialization failure
        pg('x', '40P01'), // deadlock
      ]) {
        expect(isOutageShapedFailure(e), isTrue, reason: '$e');
      }
    });

    test('MIRROR: text the USER typed, echoed into details, is never an outage signal', () {
      for (final e in <Object>[
        pg('violates check constraint', '23514',
            details: 'Failing row contains (abc, my workout timed out yesterday)'),
        pg('violates not-null', '23502', details: 'Failing row contains (connection reset)'),
        pg('bad', '23503', details: 'Key (id)=(status: 503 returned) is not present'),
        pg('bad', '22P02', details: 'Failing row contains (Failed to fetch lunch)'),
      ]) {
        expect(isOutageShapedFailure(e), isFalse, reason: '$e');
      }
    });

    test('the status word needs a word boundary: "decode 500 items" is not a 500', () {
      expect(httpStatusOfError(Exception('could not decode 500 items')), isNull);
      expect(httpStatusOfError(Exception('unicode 404 table')), isNull);
      expect(httpStatusOfError(pg('x', '503')), 503);
    });

    test('a status in details is ignored; the same status in the message/code counts', () {
      expect(httpStatusOfError(pg('x', '23514', details: 'status: 503 returned')), isNull);
      expect(httpStatusOfError(Exception('FunctionException(status: 503, details: x)')), 503);
    });
  });

  group('push op-type classification (B-pass F4)', () {
    test('ops the sweep does NOT re-send, and READS sharing the sync_ prefix, never arm a retry', () {
      for (final op in kNotSweptOpTypes) {
        expect(isPushFailureOpType(op), isFalse, reason: op);
      }
      expect(kNotSweptOpTypes, containsAll(<String>[
        'sync_community_items', // a READ
        'sync_custom_items',
        'sync_freezes',
        'sync_saved_diet_plan',
        'sync_notifications_inbox_entry',
        'upsert_coach_memory_induction',
      ]));
    });

    test('MIRROR: the pushes the sweep DOES re-send still arm it', () {
      for (final op in [
        'upsert_weight_log',
        'upsert_workout_log',
        'upsert_user_profile',
        'sync_weight_now',
        'sync_workout_data',
        'sync_user_progress',
        'restore_sync_weight',
        'weekly_full_sync',
      ]) {
        expect(isPushFailureOpType(op), isTrue, reason: op);
      }
    });

    test('FORCING FUNCTION: every opType literal in lib/ is classified here — a NEW one fails until someone decides',
        () {
      const armed = <String>{
        'sync_measurements_now', 'sync_nutrition_data', 'sync_progress_now',
        'sync_readiness_now', 'sync_saved_meals_now', 'sync_sleep_now',
        'sync_user_profile_marker', 'sync_user_progress', 'sync_weight_now',
        'sync_workout_data', 'sync_workout_plan', 'weekly_full_sync',
        'upsert_coach_interaction', 'upsert_exercise_log', 'upsert_nutrition_log',
        'upsert_nutrition_log_item', 'upsert_schedule_completion',
        'upsert_scheduled_workout', 'upsert_streak', 'upsert_template_exercise',
        'upsert_user_preferences', 'upsert_user_profile', 'upsert_workout_log',
        'upsert_workout_log_sets', 'upsert_workout_template',
      };
      const notArmed = <String>{
        'backfill_custom_entity_ids', 'check_and_sync', 'check_and_sync_snapshot',
        'mirror_coach_memory_from_snapshot', 'onboarding_sync',
        'onboarding_sync_replay', 'onboarding_sync_retry', 'pull_cross_channel_logs',
        'push_snapshot', 'realtime_handler_weight_logs', 'realtime_stream_weight_logs',
        'scheduled_workout_fk_recovered', 'scheduled_workout_template_orphaned',
        'subscription_refresh_on_restore',
      };
      final found = <String>{};
      final re = RegExp(r"opType:\s*'([a-z0-9_]+)'");
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          found.add(m.group(1)!);
        }
      }
      expect(found, isNotEmpty);
      final unclassified = [
        for (final op in found)
          if (!armed.contains(op) &&
              !notArmed.contains(op) &&
              !kNotSweptOpTypes.contains(op) &&
              !(op.startsWith('restore_') && !op.startsWith('restore_sync_')))
            op,
      ];
      expect(unclassified, isEmpty,
          reason: 'new opType literal(s) — decide whether the retry sweep re-sends them: '
              '$unclassified. Armed => add to isPushFailureOpType\'s scope AND to `armed` here; '
              'not re-sent => add to kNotSweptOpTypes (or `notArmed`).');
      for (final op in found) {
        expect(isPushFailureOpType(op), armed.contains(op), reason: op);
      }
    });
  });

  group('shouldRunFullSweep (B-pass F1 — the durable "owed" flag)', () {
    final now = DateTime(2026, 10, 1, 15);
    const day = Duration(days: 1);

    test('a fresh stamp and nothing owed → no launch sweep', () {
      expect(
          shouldRunFullSweep(
              lastFullSync: now.subtract(const Duration(hours: 6)),
              now: now,
              interval: day,
              owed: false),
          isFalse);
    });

    test('a fresh stamp but a sweep OWED → sweep (the web-reload-after-outage case)', () {
      expect(
          shouldRunFullSweep(
              lastFullSync: now.subtract(const Duration(hours: 6)),
              now: now,
              interval: day,
              owed: true),
          isTrue);
    });

    test('MIRROR: no stamp, or an elapsed interval, still sweeps with nothing owed', () {
      expect(
          shouldRunFullSweep(lastFullSync: null, now: now, interval: day, owed: false),
          isTrue);
      expect(
          shouldRunFullSweep(
              lastFullSync: now.subtract(const Duration(days: 2)),
              now: now,
              interval: day,
              owed: false),
          isTrue);
    });
  });

  group('wiring (presence — comment-stripped; behavior is covered above)', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final svc =
        strip(File('lib/core/services/sync_service.dart').readAsStringSync());
    final ctl = strip(
        File('lib/core/services/sync_retry_controller.dart').readAsStringSync());

    test('_reportSyncFailure forwards every failure and persists "sweep owed" ONLY for an ACCEPTED one', () {
      final i = svc.indexOf('Future<void> _reportSyncFailure(');
      expect(i, greaterThan(-1));
      final body = svc.substring(i, i + 1800);
      final note = body.indexOf('SyncRetryController.instance.noteFailure(error, opType: opType)');
      final guard = RegExp(r'retryableFailureSeq\s*!=\s*acceptedBefore').firstMatch(body);
      final owed = body.indexOf('_setSweepOwed(true)');
      expect(note, greaterThan(-1));
      expect(guard, isNotNull, reason: 'owed is set only when the failure was accepted');
      expect(owed, greaterThan(guard!.start));
      expect(guard.start, greaterThan(note));
    });

    test('checkAndSync honours the durable owed flag through shouldRunFullSweep', () {
      expect(svc.contains('shouldRunFullSweep('), isTrue);
      expect(svc.contains('owed: _sweepOwed'), isTrue);
    });

    test('the controller sweeps with weeklyFullSync and probes with probeBackendReachable', () {
      expect(svc.contains('probe: probeBackendReachable'), isTrue);
      expect(svc.contains('sweep: weeklyFullSync'), isTrue);
    });

    test('_onUserChanged resets the controller AND the serialisation slot', () {
      final i = svc.indexOf('void _onUserChanged()');
      final j = svc.indexOf('final HiveService _hive', i);
      final body = svc.substring(i, j);
      expect(body.contains('SyncRetryController.instance.reset()'), isTrue);
      expect(body.contains('_weeklyFullSyncSlot.reset()'), isTrue);
    });

    test('weeklyFullSync SERIALISES via the slot (kill-switch bypasses it), stamps ONLY on a clean sweep, clears owed, releases in finally', () {
      final m = RegExp(r'Future<void>\s+weeklyFullSync\(\)\s*async\s*\{')
          .firstMatch(svc);
      expect(m, isNotNull);
      final next = svc.indexOf(RegExp(r'\n  Future<'), m!.end);
      final body = svc.substring(m.start, next);
      final enter = body.indexOf('_weeklyFullSyncSlot.enter()');
      final wait = body.indexOf('await ticket.turn');
      final baseline = body.indexOf('final retryableFailuresBefore');
      expect(body.contains('SyncRetryController.instance.disabled'), isTrue,
          reason: '§4.6: kill-switch on => the old path, no ticket');
      expect(enter, greaterThan(-1));
      expect(wait, greaterThan(enter), reason: 'waits for its turn');
      expect(baseline, greaterThan(wait),
          reason: 'the failure baseline is read AFTER the wait');
      // The code breaks this comparison across two lines — match whitespace-tolerantly.
      final guard = RegExp(r'retryableFailureSeq\s*==\s*retryableFailuresBefore')
          .firstMatch(body);
      final stamp = body.indexOf('_setTimestamp(_lastFullSyncKey)');
      final clear = body.indexOf('_setSweepOwed(false)');
      expect(guard, isNotNull);
      expect(stamp, greaterThan(guard!.start),
          reason: 'the stamp sits BEHIND the clean-sweep guard');
      expect(clear, greaterThan(stamp), reason: 'owed is cleared only with the stamp');
      final fin = body.indexOf('finally');
      final release = body.indexOf('ticket?.release()');
      expect(fin, greaterThan(-1));
      expect(release, greaterThan(fin), reason: 'the ticket must be released in finally');
    });

    test('kill-switch key literals are pinned (a typo would silently disable the switch)', () {
      expect(ctl.contains("'disable_sync_retry_sweep'"), isTrue);
    });

    test('probeBackendReachable keeps its 8 s ceiling and fails closed on it (a hung probe must not wedge the controller)', () {
      final res = strip(
          File('lib/core/services/sync/sync_resilience.dart').readAsStringSync());
      final i = res.indexOf('Future<bool> probeBackendReachable()');
      expect(i, greaterThan(-1));
      final body = res.substring(i, (i + 400).clamp(0, res.length));
      expect(
          RegExp(r'\.timeout\(\s*const Duration\(seconds: 8\),\s*onTimeout: \(\) => false\s*\)')
              .hasMatch(body),
          isTrue);
    });

    test('the probe fails CLOSED: no signed-in user and any thrown error both mean "unreachable"', () {
      final res = strip(
          File('lib/core/services/sync/sync_resilience.dart').readAsStringSync());
      expect(res.contains('if (uid == null) return false;'), isTrue,
          reason: 'a null user must not be reported reachable');
      final closed = RegExp(r'catch \(_\) \{\s*return false;\s*\}').allMatches(res);
      expect(closed.length, 2,
          reason: 'both probeBackendReachable and _probeBackend return false from their catch');
      expect(res.contains('return true'), isFalse,
          reason: 'the only "reachable" verdict comes from probeBackendWithClient');
    });
  });
}
