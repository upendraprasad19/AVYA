// H1b Part B1 — pushSnapshot debounce + cross-account swap safety.
//
// ~50 callers fire `unawaited(SyncService.instance.pushSnapshot())` after a
// write. Pre-H1b each was a separate `daily-snapshot` EF invoke (the snapshot
// half of the signup/usage storm). pushSnapshot now routes through a dedicated
// `_snapshotCoalescer` -> `pushSnapshotNow` (the verbatim pre-H1b body: H3
// callFunction routing + coach_memory mirror).
//
// The MECHANISM (in-flight + dirty do-while coalescing) is behaviorally pinned
// by sync_coalescer_behavioral_test.dart. This file pins the B1 WIRING that the
// foolproof review flagged as load-bearing:
//   - B-fix-1 (GATING): _onUserChanged resets ALL THREE coalescers, incl.
//     _snapshotCoalescer. An owed trailing snapshot carried into the NEW owner
//     would mirror the PREVIOUS user's coach_memory into the new owner's
//     coachBox (auth_hive_owner_agreement cross-account leak). A fresh coalescer
//     on swap = clean slate (behavioral assertion below).
//   - B-fix-2: the 3 durable callers (onboarding first-context, checkAndSync
//     next-login backstop, coach_memory_service freshly-extracted coaching_notes)
//     call pushSnapshotNow() directly (not the coalescer).
//   - B-fix-3: flushPendingSyncs flushes _snapshotCoalescer too.
//   - pushSnapshot routes through _snapshotCoalescer behind disable_snapshot_debounce.
//
// This FAILS if any of those wirings regress (e.g. _onUserChanged stops
// resetting _snapshotCoalescer -> the GATING leak guard is gone).
//
// See docs/diagnoses/2026-06-27-pushsnapshot-debounce-e7c1a9.md.

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_coalescer.dart';

void main() {
  group('swap safety — a fresh coalescer abandons the previous owner\'s owed work',
      () {
    test('reassigning the coalescer (the _onUserChanged pattern) yields a clean slate',
        () {
      fakeAsync((async) {
        // Model the SyncService._snapshotCoalescer field.
        var coalescer = SyncCoalescer();
        var passes = 0;
        Future<void> task() async {
          passes++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        // User A: pass 1 in-flight + a second trigger owes a trailing pass.
        coalescer.trigger(task);
        coalescer.trigger(task);
        expect(coalescer.isInFlight, isTrue);
        expect(coalescer.isDirty, isTrue,
            reason: 'A owes a trailing pass on THIS instance');

        // _onUserChanged (B-fix-1): reassign a FRESH coalescer for user B.
        coalescer = SyncCoalescer();

        // The new instance carries NONE of A's owed work — so a B-trigger does
        // not pigg-back on A's pending pass, and A's owed pass cannot be
        // re-routed onto B's session.
        expect(coalescer.isDirty, isFalse,
            reason: 'fresh coalescer must not inherit A\'s _dirty');
        expect(coalescer.isInFlight, isFalse,
            reason: 'fresh coalescer must not inherit A\'s in-flight');

        // The OLD instance still drains its own owed work (Dart has no
        // cancellation): pass 1 + the owed trailing pass = 2. The guarantee is
        // NOT that the old pass is killed, but that the NEW instance is clean —
        // so a B-trigger coalesces independently and A's owed pass can't be
        // re-routed onto B (it runs on the dereferenced old instance, then ends).
        async.elapse(const Duration(milliseconds: 300));
        expect(passes, 2,
            reason: 'old coalescer drains pass1 + its owed trailing pass; the '
                'fresh instance carries none of it');
      });
    });
  });

  group('B1 wiring contracts (source-pinned against sync_service.dart)', () {
    late String src;
    late String onUserChanged;

    setUpAll(() {
      src = File('lib/core/services/sync_service.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      // Extract the _onUserChanged method body (from its signature to the next
      // `final HiveService _hive` field that immediately follows it).
      final start = src.indexOf('_onUserChanged(');
      expect(start, greaterThan(-1), reason: '_onUserChanged must exist');
      final end = src.indexOf('final HiveService _hive', start);
      onUserChanged = end > start ? src.substring(start, end) : src.substring(start);
    });

    test('B-fix-1 (GATING): _onUserChanged resets all THREE coalescers', () {
      expect(onUserChanged.contains('_workoutCoalescer = SyncCoalescer()'), isTrue,
          reason: 'workout coalescer reset (H1a)');
      expect(onUserChanged.contains('_nutritionCoalescer = SyncCoalescer()'), isTrue,
          reason: 'nutrition coalescer reset (H1a)');
      expect(
        onUserChanged.contains('_snapshotCoalescer = SyncCoalescer()'),
        isTrue,
        reason:
            'B-fix-1 GATING — the snapshot coalescer MUST reset on swap or an '
            'owed pass leaks the previous user\'s coach_memory into the new '
            'owner\'s coachBox',
      );
    });

    test('pushSnapshot routes through _snapshotCoalescer behind the kill-switch',
        () {
      expect(
        src.contains('_snapshotCoalescer.trigger(pushSnapshotNow)'),
        isTrue,
        reason: 'pushSnapshot (+ flush) must coalesce through pushSnapshotNow',
      );
      expect(src.contains('_snapshotDebounceDisabled'), isTrue,
          reason: 'kill-switch disable_snapshot_debounce must gate the coalescer');
      expect(src.contains('Future<void> pushSnapshotNow() async'), isTrue,
          reason: 'the verbatim pre-H1b body lives in pushSnapshotNow');
    });

    test('B-fix-3: flushPendingSyncs flushes the snapshot coalescer too', () {
      final start = src.indexOf('void flushPendingSyncs()');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 600);
      expect(body.contains('_snapshotCoalescer.trigger(pushSnapshotNow)'), isTrue,
          reason: 'app-pause flush must include the snapshot coalescer');
    });

    test('B-fix-4: the coach_memory mirror is guarded by a session re-check', () {
      // pushSnapshotNow must re-verify the session owner immediately before the
      // coach_memory mirror — else an in-flight push parked on its EF await
      // across an A->B swap leaks A's coach_memory into B's coachBox (the
      // concurrency-lens P1; B-fix-1's coalescer reset only drops an OWED pass).
      // `currentUser?.id` is a sync getter with no await before the box
      // resolution, so the check + mirror are atomic.
      expect(
        src.contains('_supabase.currentUser?.id != userId'),
        isTrue,
        reason:
            'pushSnapshotNow must skip the coach_memory mirror on a mid-flight '
            'session swap (cross-account guard, vector 2)',
      );
    });
  });

  group('B-fix-2 eager carve-outs (durable callers bypass the coalescer)', () {
    test('checkAndSync (next-login backstop) calls pushSnapshotNow', () {
      final src = File('lib/core/services/sync_service.dart').readAsStringSync();
      expect(src.contains('await pushSnapshotNow()'), isTrue,
          reason: 'the awaited checkAndSync backstop must be durable (*Now)');
    });

    test('onboarding first-context calls pushSnapshotNow', () {
      final src = File('lib/features/onboarding/providers/onboarding_provider.dart')
          .readAsStringSync();
      expect(src.contains('pushSnapshotNow()'), isTrue,
          reason:
              'onboarding\'s first AI-context snapshot must be eager (*Now), not '
              'deferred to a coalescer pass that could be lost in the signup storm');
    });

    test('coach_memory_service (freshly-extracted coaching_notes) calls pushSnapshotNow',
        () {
      final src = File(
              'lib/features/ai_coach/services/coach_memory_service.dart')
          .readAsStringSync();
      expect(src.contains('pushSnapshotNow()'), isTrue,
          reason:
              'the only PROMPT sync of coachBox[coaching_notes] must be eager '
              '(*Now) — syncCoachMemoryNow is only a delayed full-sweep backstop');
    });
  });
}
