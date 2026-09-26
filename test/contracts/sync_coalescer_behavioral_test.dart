import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_coalescer.dart';

/// Behavioral contract for [SyncCoalescer] (Unit H / H1a — offline-first cost
/// optimization). Pins the two semantics the Opus-4.8 ×3 review demanded:
///   1. a burst of triggers during one in-flight pass collapses to ≤ 2 passes
///      (the signup-storm fix — ~18 per-write syncs → 1–2 cloud passes);
///   2. a trigger that arrives *during* a (trailing) pass is NEVER lost — it
///      re-raises `_dirty` and the do-while runs one more pass. A naive "clear
///      after the pass" or "exactly one trailing pass" loses the last write
///      until the next unrelated sync; this test is RED on that implementation.
void main() {
  group('SyncCoalescer', () {
    test('a burst of triggers during one in-flight pass collapses to ≤2 passes',
        () {
      fakeAsync((async) {
        final c = SyncCoalescer();
        var passes = 0;
        Future<void> task() async {
          passes++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        // Pass 1 starts (runs synchronously up to the first await).
        c.trigger(task);
        expect(c.isInFlight, isTrue);
        expect(passes, 1);

        // 10 more triggers arrive WHILE pass 1 is in-flight.
        for (var i = 0; i < 10; i++) {
          c.trigger(task);
        }
        expect(passes, 1, reason: 'no concurrent pass starts while in-flight');
        expect(c.isDirty, isTrue, reason: 'a single trailing pass is owed');

        // Pass 1 completes → exactly ONE trailing pass absorbs all 10.
        async.elapse(const Duration(milliseconds: 100));
        expect(passes, 2);

        // No triggers during pass 2 → no pass 3.
        async.elapse(const Duration(milliseconds: 100));
        expect(passes, 2);
        expect(c.isInFlight, isFalse);
      });
    });

    test('a trigger arriving DURING the trailing pass runs another pass (no loss)',
        () {
      fakeAsync((async) {
        final c = SyncCoalescer();
        var passes = 0;
        var queued2 = false;
        var queued3 = false;
        late SyncCoalescer self;
        Future<void> task() async {
          passes++;
          // Simulate a Hive write landing mid-pass: queue a trigger.
          if (passes == 1 && !queued2) {
            queued2 = true;
            unawaited(self.trigger(task)); // arrives during pass 1 → owes pass 2
          } else if (passes == 2 && !queued3) {
            queued3 = true;
            unawaited(self.trigger(task)); // arrives during pass 2 → MUST owe pass 3
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        self = c;
        c.trigger(task); // pass 1
        async.elapse(const Duration(milliseconds: 100)); // → pass 2
        async.elapse(const Duration(milliseconds: 100)); // → pass 3 (no-loss)
        async.elapse(const Duration(milliseconds: 100)); // pass 3 done, idle

        expect(passes, 3,
            reason: 'the trigger during the trailing pass must not be dropped');
        expect(c.isInFlight, isFalse);
        expect(c.isDirty, isFalse);
      });
    });

    test('triggers spaced apart each run their own pass (no false coalescing)',
        () {
      fakeAsync((async) {
        final c = SyncCoalescer();
        var passes = 0;
        Future<void> task() async {
          passes++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        c.trigger(task);
        async.elapse(const Duration(milliseconds: 50));
        expect(passes, 1);
        expect(c.isInFlight, isFalse);

        c.trigger(task); // fresh, not coalesced with the first
        async.elapse(const Duration(milliseconds: 50));
        expect(passes, 2);
      });
    });

    test('a throwing pass does not wedge the coalescer nor rethrow', () {
      fakeAsync((async) {
        final c = SyncCoalescer();
        var passes = 0;
        var shouldThrow = true;
        Future<void> task() async {
          passes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (shouldThrow) throw StateError('boom');
        }

        // First pass throws — must be swallowed + in-flight cleared.
        c.trigger(task);
        async.elapse(const Duration(milliseconds: 10));
        expect(passes, 1);
        expect(c.isInFlight, isFalse, reason: 'a throw must not wedge in-flight');

        // A later trigger still runs (coalescer not wedged).
        shouldThrow = false;
        c.trigger(task);
        async.elapse(const Duration(milliseconds: 10));
        expect(passes, 2);
      });
    });
  });
}
