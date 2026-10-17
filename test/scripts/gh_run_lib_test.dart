import 'dart:io' show ProcessException;

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/gh_run_lib.dart';

/// Builds a lister that returns [rows] for any args.
GhRunLister _canned(List<Map<String, dynamic>> rows) => (_) => rows;

/// A lister that could not answer at all (gh missing / unauthenticated).
GhRunLister get _unavailable => (_) => null;

Map<String, dynamic> _run({
  required String sha,
  String? conclusion,
  String? createdAt,
  String? url,
  int? id,
}) =>
    {
      'headSha': sha,
      'conclusion': conclusion,
      'createdAt': createdAt,
      'url': url,
      'databaseId': id,
      'status': 'completed',
    };

void main() {
  group('classifyConclusion', () {
    test('maps every conclusion this tool acts on', () {
      expect(classifyConclusion('success'), ConclusionClass.success);
      expect(classifyConclusion('failure'), ConclusionClass.failure);
      expect(classifyConclusion('cancelled'), ConclusionClass.failure);
      expect(classifyConclusion('timed_out'), ConclusionClass.failure);
      expect(classifyConclusion('startup_failure'), ConclusionClass.failure);
    });

    test('null / empty / in-progress are pending, never failure', () {
      // Inventing a red result from "not finished yet" would cry wolf on every
      // session started within a couple of minutes of a push.
      expect(classifyConclusion(null), ConclusionClass.pending);
      expect(classifyConclusion(''), ConclusionClass.pending);
      expect(classifyConclusion('in_progress'), ConclusionClass.pending);
      expect(classifyConclusion('queued'), ConclusionClass.pending);
    });

    test('an unrecognised conclusion is pending, not failure', () {
      expect(classifyConclusion('some_future_gh_value'), ConclusionClass.pending);
    });

    test('is case- and whitespace-insensitive', () {
      expect(classifyConclusion('  SUCCESS '), ConclusionClass.success);
      expect(classifyConclusion('Failure'), ConclusionClass.failure);
    });
  });

  group('queryLatestRunForSha', () {
    test('finds the run matching the SHA', () {
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned([
          _run(sha: 'zzz999', conclusion: 'failure'),
          _run(
              sha: 'aaa111',
              conclusion: 'success',
              url: 'https://example.invalid/1',
              id: 1),
        ]),
      );

      expect(r.found, isTrue);
      expect(r.conclusion, ConclusionClass.success);
      expect(r.url, 'https://example.invalid/1');
      expect(r.runId, 1);
    });

    test('TWO runs for one SHA (a re-run) resolve to the NEWER', () {
      // gh run list documents no ordering guarantee, so this must come from an
      // explicit createdAt sort rather than trusting the response order.
      // Deliberately supplied oldest-first so a naive `.first` would fail.
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned([
          _run(
              sha: 'aaa111',
              conclusion: 'failure',
              createdAt: '2026-08-12T09:00:00Z',
              id: 10),
          _run(
              sha: 'aaa111',
              conclusion: 'success',
              createdAt: '2026-08-12T11:00:00Z',
              id: 11),
        ]),
      );

      expect(r.runId, 11, reason: 'the re-run, not the original');
      expect(r.conclusion, ConclusionClass.success);
    });

    test('a row with no createdAt never outranks one that has it', () {
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned([
          _run(sha: 'aaa111', conclusion: 'failure', id: 20), // no createdAt
          _run(
              sha: 'aaa111',
              conclusion: 'success',
              createdAt: '2026-08-12T09:00:00Z',
              id: 21),
        ]),
      );

      expect(r.runId, 21);
    });

    test('no matching SHA is notFound', () {
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned([_run(sha: 'zzz999', conclusion: 'success')]),
      );

      expect(r.found, isFalse);
    });

    test('an empty run list is notFound', () {
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned([]),
      );

      expect(r.found, isFalse);
    });

    test('a THROWING lister (gh absent / unauthenticated) does not propagate', () {
      // This runs inside a SessionStart hook. An exception escaping here would
      // break session start, which is the one thing this tool must never do.
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: (_) => throw ProcessException('gh', const []),
      );

      expect(r.found, isFalse);
      expect(r.conclusion, ConclusionClass.pending);
    });

    test('"could not ask" is DISTINGUISHABLE from "no such run"', () {
      // The B-pass found these collapsed into one state, so a broken local `gh`
      // produced a confident "CI never ran, check whether Actions is enabled".
      // Same conflation class as safe_push.sh's empty-ls-remote meaning both
      // "ref absent" and "probe unreachable".
      final genuinelyAbsent = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _canned(const []),
      );
      final couldNotAsk = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: _unavailable,
      );

      expect(genuinelyAbsent.found, isFalse);
      expect(genuinelyAbsent.lookupFailed, isFalse,
          reason: 'gh answered; there is simply no run for this SHA');

      expect(couldNotAsk.found, isFalse);
      expect(couldNotAsk.lookupFailed, isTrue,
          reason: 'gh could not be asked — this is NOT evidence about any run');

      expect(genuinelyAbsent.lookupFailed, isNot(couldNotAsk.lookupFailed),
          reason: 'if these are equal the caller cannot tell them apart, which '
              'is the entire defect');
    });

    test('a throwing lister also reports lookupFailed, not a bare notFound', () {
      final r = queryLatestRunForSha(
        workflow: 'Test & Analyze',
        branch: 'main',
        sha: 'aaa111',
        lister: (_) => throw ProcessException('gh', const []),
      );

      expect(r.lookupFailed, isTrue);
    });
  });

  group('fetchFailingJobNames', () {
    test('returns only the non-successful job names', () {
      final names = fetchFailingJobNames(
        runId: 1,
        lister: _canned([
          {
            'jobs': [
              {'name': 'analyze', 'conclusion': 'success'},
              {'name': 'unit-test', 'conclusion': 'failure'},
              {'name': 'audit-gates', 'conclusion': 'timed_out'},
            ]
          }
        ]),
      );

      expect(names, ['unit-test', 'audit-gates']);
    });

    test('a throwing lister yields an empty list, not an exception', () {
      final names = fetchFailingJobNames(
        runId: 1,
        lister: (_) => throw ProcessException('gh', const []),
      );

      expect(names, isEmpty);
    });

    test('an unavailable lister yields an empty list, not an exception', () {
      expect(fetchFailingJobNames(runId: 1, lister: _unavailable), isEmpty);
    });

    test('malformed job payloads yield an empty list', () {
      expect(fetchFailingJobNames(runId: 1, lister: _canned([])), isEmpty);
      expect(
        fetchFailingJobNames(runId: 1, lister: _canned([
          {'jobs': 'not a list'}
        ])),
        isEmpty,
      );
    });
  });

  group('parseGhJson', () {
    test('parses a top-level array (gh run list)', () {
      final rows = parseGhJson('[{"headSha":"a"},{"headSha":"b"}]');
      expect(rows, hasLength(2));
      expect(rows[0]['headSha'], 'a');
    });

    test('normalises a single object (gh run view) to a one-row list', () {
      final rows = parseGhJson('{"jobs":[]}');
      expect(rows, hasLength(1));
      expect(rows.first.containsKey('jobs'), isTrue);
    });

    test('empty, whitespace, and invalid JSON all yield an empty list', () {
      expect(parseGhJson(''), isEmpty);
      expect(parseGhJson('   \n '), isEmpty);
      expect(parseGhJson('gh: command not found'), isEmpty);
      expect(parseGhJson('{"unterminated":'), isEmpty);
    });
  });
}
