// OI-45 finding 4 / Unit 3a (progress-map-consolidation, 2026-07-30) —
// source-grep contract (comment-stripped, mirrors the sibling
// unit3_web_ux_gates_test.dart's convention for this exact file — that
// file deliberately never invokes HealthSyncService's real methods either,
// since they reach the `health` plugin's platform channel, which isn't
// mocked in this suite; _ensureConfigured's unawaited Health().configure()
// call risks an unhandled async rejection if actually exercised here).
//
// syncToHive() is called both on app launch AND when the health-sync
// toggle is turned on in Settings — on a slow device these can genuinely
// overlap. The weight write inside guards with a plain
// `existing == null` read-then-write, no lock — safe WITHIN one call
// (nothing else runs between that read and the put), but not ACROSS two
// independently-dispatched calls, where both can pass their own read
// before either reaches its write. The only real await gap in the method
// sits BEFORE the read (fetchLatestWeight), not between the read and the
// write, so the fix is a whole-method in-flight dedup, not a finer-grained
// lock around the read-check-write.
//
// Run: flutter test test/contracts/health_sync_service_dedup_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  group('OI-45 finding 4 — HealthSyncService.syncToHive dedup guard', () {
    final source = _strip(
        File('lib/core/services/health_sync_service.dart').readAsStringSync());

    test('a dedicated in-flight Future field exists', () {
      expect(
        RegExp(r'Future<void>\?\s*_syncInFlight\s*;').hasMatch(source),
        isTrue,
        reason: 'the dedup guard must be a nullable in-flight Future field, '
            'set while a sync is running and cleared when it completes.',
      );
    });

    test(
        'the public syncToHive() entrypoint checks _syncInFlight before '
        'doing any work and delegates the real work to a separate method',
        () {
      final sig = RegExp(
        r'Future<void>\s+syncToHive\(\)\s*async\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(source);
      expect(sig, isNotNull,
          reason: 'syncToHive signature shape changed — update this regex');
      final body = sig!.group(1)!;

      expect(body.contains('_syncInFlight'), isTrue,
          reason: 'syncToHive must consult the in-flight guard before '
              'starting a new sync — OI-45 finding 4.');
      // The real work must live in a DIFFERENT method (not inline in the
      // public entrypoint) — otherwise there is no way for a second caller
      // to "await the first call's work" instead of independently
      // re-running it, which is the actual mechanism that closes the gap.
      expect(body.contains('_syncToHiveLocked'), isTrue,
          reason: 'syncToHive must delegate the actual sync work to a '
              'private method so a second concurrent caller can await the '
              'FIRST call\'s in-flight future instead of starting its own '
              'independent, overlapping run (which would re-issue '
              'fetchLatestWeight and re-run the unguarded read-check-write).');
    });

    test(
        '_syncToHiveLocked is private (library-scoped) — nothing outside '
        'this file can bypass the dedup guard by calling it directly', () {
      // Enforced by the language itself (leading underscore = library
      // privacy in Dart) — this test just documents and pins that the
      // method exists under that name, so a rename can't silently drop
      // the privacy guarantee without this test needing an update too.
      expect(
        RegExp(r'Future<void>\s+_syncToHiveLocked\(\)\s*async\s*\{').hasMatch(source),
        isTrue,
        reason: 'the real sync work must live in a private (underscore) '
            'method — public would let a caller route around the guard.',
      );
    });

    test('the in-flight future is always cleared, even if the sync throws',
        () {
      final sig = RegExp(
        r'Future<void>\s+syncToHive\(\)\s*async\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(source);
      final body = sig!.group(1)!;
      expect(body.contains('finally'), isTrue,
          reason: 'clearing _syncInFlight must happen in a finally block — '
              'otherwise a thrown exception would wedge every future caller '
              'into awaiting a Future that will never complete.');
    });

    test(
        'round-1 review P2 (fixed): the completer resolves with the SAME '
        'outcome the leader actually had — success only calls complete(), '
        'failure calls completeError() and rethrows', () {
      final sig = RegExp(
        r'Future<void>\s+syncToHive\(\)\s*async\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(source);
      final body = sig!.group(1)!;

      // The bug this pins: complete() called unconditionally in `finally`
      // regardless of whether _syncToHiveLocked() threw — a deduped
      // follower caller (one that got `return inFlight`) would then
      // silently observe SUCCESS even when the leader's sync actually
      // failed. Fix: complete() only follows a successful await;
      // completeError() + rethrow live in a catch block.
      expect(body.contains('completeError'), isTrue,
          reason: 'a thrown exception must propagate to every follower via '
              'completer.completeError(...), not be swallowed by an '
              'unconditional complete() in finally.');
      expect(body.contains('rethrow'), isTrue,
          reason: 'the leader caller must also still see the exception.');

      // The specific pre-fix shape: complete() as the ONLY statement inside
      // a bare `finally { ...; completer.complete(); }` with no catch block
      // in between. Post-fix, complete() must NOT be the last statement of
      // an unconditional finally — it must be gated behind the try's own
      // success path (i.e. NOT sitting in the same finally block as the
      // _syncInFlight-clearing line, which does stay unconditional).
      final finallyBlock =
          RegExp(r'finally\s*\{([\s\S]*?)\n    \}').firstMatch(body);
      expect(finallyBlock, isNotNull,
          reason: 'syncToHive signature shape changed — update this regex');
      expect(finallyBlock!.group(1)!.contains('completer.complete()'), isFalse,
          reason: 'complete() must NOT be unconditional inside finally — '
              'that is exactly the bug this test pins. Only '
              '_syncInFlight = null may be unconditional.');
    });

    test(
        'round-2 review P1 (fixed): completer.future has an immediate '
        'listener attached, so an unlistened leader-only failure cannot '
        'surface as a duplicate unhandled-Zone error', () {
      // The bug this pins: in the common case (no concurrent follower ever
      // calls syncToHive() while one is in flight), nobody ever awaits or
      // attaches a listener to `completer.future` — the leader observes
      // its own outcome via the try/catch below through a SEPARATE Future
      // (this method's own). completer.completeError() on an unlistened
      // Future is treated by Dart as an unhandled error and reported a
      // SECOND time to the current Zone — verified empirically via a
      // runZonedGuarded repro during round-2 review, reproducing a
      // spurious duplicate FATAL Crashlytics report on every ordinary
      // (non-concurrent) sync failure. Fix: attach a no-op listener to
      // completer.future immediately, before any await — Future listeners
      // fan out rather than consume, so a REAL follower awaiting the SAME
      // future via _syncInFlight still independently observes the real
      // outcome; only the phantom "nobody was listening" report is
      // silenced.
      final sig = RegExp(
        r'Future<void>\s+syncToHive\(\)\s*async\s*\{([\s\S]*?)\n  \}\n',
      ).firstMatch(source);
      final body = sig!.group(1)!;

      final completerCreateIdx = body.indexOf('Completer<void>()');
      final firstAwaitIdx = body.indexOf('await ');
      expect(completerCreateIdx, greaterThanOrEqualTo(0),
          reason: 'syncToHive must construct its own Completer — shape '
              'changed, update this regex before trusting the result.');
      expect(firstAwaitIdx, greaterThan(completerCreateIdx),
          reason: 'syncToHive signature shape changed — update this regex');

      final beforeFirstAwait = body.substring(0, firstAwaitIdx);
      expect(
        RegExp(r'completer\.future\.catchError\(').hasMatch(beforeFirstAwait),
        isTrue,
        reason: 'a silencing listener (completer.future.catchError(...)) '
            'must be attached BEFORE the first await in syncToHive — '
            'otherwise a leader-only failure (the common case) reports a '
            'duplicate error to the Zone. Round-2 review P1.',
      );
    });
  });
}
