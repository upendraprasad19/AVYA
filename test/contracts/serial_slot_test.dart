// test/contracts/serial_slot_test.dart
//
// Contract — closes-diagnose e5b2a9 (B-pass F2). SerialSlot is what keeps
// weeklyFullSync from overlapping itself. The source-grep that used to guard it
// left every one of these mutations green, so it is tested BEHAVIOURALLY here:
// overlap order, release on every path, the newest-tail rule, reset while waiting.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/serial_slot.dart';

void main() {
  test('the first caller does not wait', () {
    fakeAsync((async) {
      final slot = SerialSlot();
      var turned = false;
      slot.enter().turn.then((_) => turned = true);
      async.flushMicrotasks();
      expect(turned, isTrue);
    });
  });

  test('callers run strictly one after the other, in arrival order', () {
    fakeAsync((async) {
      final slot = SerialSlot();
      final log = <String>[];
      final a = slot.enter();
      final b = slot.enter();
      final c = slot.enter();
      a.turn.then((_) => log.add('a-start'));
      b.turn.then((_) => log.add('b-start'));
      c.turn.then((_) => log.add('c-start'));
      async.flushMicrotasks();
      expect(log, ['a-start'], reason: 'b and c must wait for a');
      a.release();
      async.flushMicrotasks();
      expect(log, ['a-start', 'b-start'], reason: 'c must still wait for b');
      b.release();
      async.flushMicrotasks();
      expect(log, ['a-start', 'b-start', 'c-start']);
    });
  });

  test('MIRROR: releasing a MIDDLE ticket does not let a later one skip the line', () {
    // The newest-tail rule: b releasing must NOT clear the slot's tail (c is the
    // newest), or a fourth caller would start without waiting for c.
    fakeAsync((async) {
      final slot = SerialSlot();
      final a = slot.enter();
      final b = slot.enter();
      final c = slot.enter();
      a.release();
      b.release(); // c holds the tail; b must not clear it
      var dStarted = false;
      slot.enter().turn.then((_) => dStarted = true);
      async.flushMicrotasks();
      expect(dStarted, isFalse, reason: 'd must wait for c');
      c.release();
      async.flushMicrotasks();
      expect(dStarted, isTrue);
    });
  });

  test('a job that THROWS still releases the line (release in finally)', () async {
    final slot = SerialSlot();
    Future<void> job({required bool fail}) async {
      final t = slot.enter();
      await t.turn;
      try {
        if (fail) throw StateError('boom');
      } finally {
        t.release();
      }
    }

    await expectLater(job(fail: true), throwsStateError);
    await job(fail: false).timeout(const Duration(seconds: 2));
  });

  test('a predecessor that never released but was reset does not block a NEW caller', () {
    fakeAsync((async) {
      final slot = SerialSlot();
      slot.enter(); // old owner's ticket, never released
      slot.reset(); // account switch
      var started = false;
      slot.enter().turn.then((_) => started = true);
      async.flushMicrotasks();
      expect(started, isTrue, reason: 'the new owner must not wait on the old one');
    });
  });

  test('a ticket already waiting when reset() lands still runs after its predecessor', () {
    fakeAsync((async) {
      final slot = SerialSlot();
      final a = slot.enter();
      var bStarted = false;
      final b = slot.enter();
      b.turn.then((_) => bStarted = true);
      slot.reset();
      async.flushMicrotasks();
      expect(bStarted, isFalse);
      a.release();
      async.flushMicrotasks();
      expect(bStarted, isTrue);
    });
  });

  test('release() is idempotent', () {
    fakeAsync((async) {
      final slot = SerialSlot();
      final a = slot.enter();
      a.release();
      a.release();
      var started = false;
      slot.enter().turn.then((_) => started = true);
      async.flushMicrotasks();
      expect(started, isTrue);
    });
  });
}
