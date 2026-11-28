// OI-150 — the durability half: progress and profile writes are persisted as
// MARKERS in SyncQueue so process death cannot lose them, and
// `sync_reliability_v1` is ON.
//
// Review round 2 / B4: the queue mechanism and the flag flip originally shipped
// with ZERO tests of any kind — the highest-risk unit in the batch was the only
// one with nothing that could fail. This file is that coverage.
//
// The executors themselves need a live Supabase session, so the runtime paths
// are pinned STRUCTURALLY here and the pure decisions are pinned behaviourally.
// Where a source-grep is used it is comment-stripped first
// (`feedback_source_grep_strip_comments_first`), and every absent-pattern
// assertion is paired with a positive half so deleting the block cannot pass.
//
// Run: flutter test test/contracts/sync_queue_progress_marker_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_error.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final m = RegExp(r'(?<!:)//').firstMatch(l);
      return m == null ? l : l.substring(0, m.start);
    })
    .join('\n');

void main() {
  final syncServiceSrc =
      _strip(File('lib/core/services/sync_service.dart').readAsStringSync());
  final syncProfileSrc = _strip(
      File('lib/core/services/sync/sync_profile.dart').readAsStringSync());

  group('the two marker executors are registered', () {
    for (final op in const ['sync_user_progress', 'sync_user_profile_marker']) {
      test('$op has a registered executor', () {
        expect(syncServiceSrc, contains("'$op'"));
        expect(syncServiceSrc, contains('registerExecutor'));
      });
    }

    test('upsert_user_profile stays registered for old queued entries', () {
      expect(syncServiceSrc, contains("'upsert_user_profile'"),
          reason: 'an entry persisted under the pre-OI-150 payload shape must '
              'still drain — dropping the registration would dead-letter it');
    });
  });

  group('the queue entry is a MARKER, never a payload', () {
    test('both enqueues send only user_id', () {
      final enqueues = RegExp(
              r"enqueue\(\s*opType:\s*'(sync_user_progress|sync_user_profile_marker)'\s*,\s*payload:\s*<String, dynamic>\{'user_id': userId\}")
          .allMatches(syncProfileSrc)
          .length;
      expect(enqueues, 3,
          reason: 'THREE marker enqueues exist — the progress failure path, '
              'the progress version-conflict path (B3), and the profile '
              'failure path. A stored payload replayed later would carry a '
              'stale p_expected_version (progress) or stale values (profile)');
    });

    test('neither executor reads a field value out of the payload', () {
      for (final fn in const [
        '_executeUserProgressSync',
        '_executeUserProfileMarker',
      ]) {
        final i = syncServiceSrc.indexOf(
            'Future<Result<void, SyncError>> $fn(');
        expect(i, isNot(-1), reason: '$fn must exist');
        final body = syncServiceSrc.substring(i, i + 900);
        expect(body.contains("payload['user_id']"), isTrue);
        expect(body.contains("payload['current_phase']"), isFalse);
        expect(body.contains("payload['daily_calories']"), isFalse);
      }
    });
  });

  group('executor refusals are NON-transient so they dead-letter at once', () {
    test('ValidationError is non-transient and UnknownError is not', () {
      // The behavioural core of B2: the refusals used to route through
      // SyncError.classify(StateError(...)), which yields UnknownError —
      // transient — so an op that can NEVER succeed burned the full retry
      // budget while the doc comment claimed it dead-lettered.
      expect(
          ValidationError(message: 'x', at: DateTime.now()).isTransient, isFalse);
      expect(SyncError.classify(StateError('queued marker had no user_id'))
              .isTransient,
          isTrue,
          reason: 'this is why classify() was the wrong route for a refusal');
    });

    test('both executors refuse via ValidationError, not classify', () {
      for (final fn in const [
        '_executeUserProgressSync',
        '_executeUserProfileMarker',
      ]) {
        final i = syncServiceSrc.indexOf(
            'Future<Result<void, SyncError>> $fn(');
        final body = syncServiceSrc.substring(i, i + 900);
        expect(RegExp(r'ValidationError\(').allMatches(body).length, 2,
            reason: '$fn must refuse a null user_id AND a foreign account '
                'non-transiently');
      }
    });
  });

  group('a drain can observe failure and never re-enqueues', () {
    test('fromQueue rethrows before the enqueue in _syncUserProgress', () {
      final i = syncProfileSrc.indexOf('Future<void> _syncUserProgress(');
      final body = syncProfileSrc.substring(i);
      final rethrowAt = body.indexOf('if (fromQueue) rethrow;');
      final enqueueAt = body.indexOf('SyncQueue.instance.enqueue');
      expect(rethrowAt, isNot(-1),
          reason: 'without it the executor catch is unreachable and every '
              'drain reports Ok for a failed push');
      expect(enqueueAt, greaterThan(rethrowAt));
    });

    test('every enqueue site is guarded by !fromQueue', () {
      final guards =
          RegExp(r'_syncReliabilityEnabled && !fromQueue').allMatches(syncProfileSrc).length;
      expect(guards, greaterThanOrEqualTo(2),
          reason: 'the failure path and the version-conflict path must BOTH '
              'skip enqueueing while draining — otherwise retryCount resets '
              'on every drain and the op never dead-letters');
    });

    test('both executors pass fromQueue: true', () {
      expect(
          RegExp(r'fromQueue:\s*true').allMatches(syncServiceSrc).length, 2);
    });
  });

  group('markers are deduped per user (N9)', () {
    test('every marker enqueue is guarded by hasPendingMarker', () {
      final guards =
          RegExp(r'hasPendingMarker\(').allMatches(syncProfileSrc).length;
      expect(guards, 3,
          reason: 'all THREE enqueue sites must dedupe — markers are '
              'idempotent, so a second one for the same user does a redundant '
              "round-trip and inflates SyncBanner's pending count. "
              'syncProgressNow fires from every progress delta, so an offline '
              'day would otherwise mint one per write');
    });

    test('the payload op is NOT deduped', () {
      // Two upsert_user_profile ops can legitimately carry different field
      // values, so deduping them would drop a real write.
      final i = syncServiceSrc.indexOf("'upsert_user_profile'");
      expect(i, isNot(-1));
      expect(
          syncServiceSrc
              .substring(i, i + 300)
              .contains('hasPendingMarker'),
          isFalse);
    });
  });

  group('the version-conflict drop path persists the debt (B3)', () {
    test('the retry helper enqueues before logging the drop', () {
      final i = syncProfileSrc
          .indexOf('Future<void> _retrySyncUserProgressOnceAfterConflict(');
      expect(i, isNot(-1));
      final body = syncProfileSrc.substring(i);
      final enqueueAt = body.indexOf('SyncQueue.instance.enqueue');
      final logAt = body.indexOf("'sync_user_progress_retry_dropped'");
      expect(enqueueAt, isNot(-1),
          reason: 'live telemetry shows this path firing 8 times across 3 '
              'users; dropping there discards the debt the marker exists for');
      expect(enqueueAt, lessThan(logAt));
    });
  });

  group('a drain never deletes a marker for an undelivered push (B-pass F2)',
      () {
    test('every early return in the conflict-retry helper throws under a drain',
        () {
      // Under fromQueue the executor turns a normal return into Result.ok, and
      // SyncQueue then DELETES the marker (sync_queue.dart _runOne). Three
      // returns in _retrySyncUserProgressOnceAfterConflict used to complete
      // normally, so a repeated version conflict during a drain reported a
      // synced write that was actually dropped — the N10 class recurring in a
      // spot the first pass missed.
      final i = syncProfileSrc
          .indexOf('Future<void> _retrySyncUserProgressOnceAfterConflict(');
      expect(i, isNot(-1));
      final next = syncProfileSrc.indexOf('Future<void> _syncUserPreferences(', i);
      final body = syncProfileSrc.substring(i, next == -1 ? null : next);

      final throws = RegExp(r'if \(fromQueue\) \{').allMatches(body).length;
      expect(throws, 3,
          reason: 'all THREE drop paths (row-absent, no-version, second '
              'conflict) must throw under a drain so the executor returns '
              'Result.err and the marker survives');
      // Each of the three drop paths must ALSO still have its non-drain
      // `return;` — the guard adds a branch, it does not replace the normal
      // path. Three throws and three returns is the shape.
      final returnCount = RegExp('return;').allMatches(body).length;
      expect(returnCount, greaterThanOrEqualTo(3),
          reason: 'the non-drain callers must still return normally; a throw '
              'that replaced the return would break syncProgressNow');
    });
  });

  group('the flag is ON, and a failed profile push still reports (B1)', () {
    test('sync_reliability_v1 defaults to true', () {
      expect(syncServiceSrc,
          contains("get('sync_reliability_v1', defaultValue: true)"));
    });

    test('the profile enqueue branch reports the failure', () {
      // Method-bounded window: _syncUserProfile builds a 34-field payload, so
      // a fixed character budget does not reach its enqueue.
      final i = syncProfileSrc.indexOf('Future<void> _syncUserProfile(');
      expect(i, isNot(-1));
      final next = syncProfileSrc.indexOf(
          'Map<String, dynamic> _buildUserProgressRpcParams(', i);
      final body = syncProfileSrc.substring(i, next == -1 ? null : next);
      final enqueueAt = body.indexOf('SyncQueue.instance.enqueue');
      expect(enqueueAt, isNot(-1),
          reason: 'the profile failure path must enqueue a marker');
      final branch = body.substring(0, enqueueAt);
      expect(branch.contains('_reportSyncFailure'), isTrue,
          reason: 'taking the queue branch stops the throw, so '
              'syncProfileNow\'s catch never runs — without a report here the '
              'flag flip re-creates the silent path that left 24 onboarding '
              'fields NULL on fresh signups');
      expect(branch.contains('recordNonFatal'), isTrue);
    });
  });
}
