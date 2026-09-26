import 'package:flutter_test/flutter_test.dart';

import '../../scripts/ci_reconcile_state_lib.dart';
import '../../scripts/gh_run_lib.dart';

PendingEntry _entry(String branch, String sha, DateTime armedAt) =>
    PendingEntry(branch: branch, sha: sha, armedAt: armedAt);

final _t0 = DateTime.utc(2026, 8, 12, 10, 0, 0);

void main() {
  group('parse / serialize', () {
    test('round-trips a set of entries', () {
      final entries = [
        _entry('main', 'aaa111', _t0),
        _entry('develop', 'bbb222', _t0.add(const Duration(minutes: 5))),
      ];
      final reparsed = parsePendingEntries(serializePendingEntries(entries));

      expect(reparsed, hasLength(2));
      expect(reparsed[0].branch, 'main');
      expect(reparsed[0].sha, 'aaa111');
      expect(reparsed[0].armedAt.toUtc(), _t0);
      expect(reparsed[1].branch, 'develop');
    });

    test('serializing an empty list produces an empty string, not "[]"', () {
      // The file is JSONL and is appended to by a shell script; an empty file
      // must stay genuinely empty so the next append starts a valid first line.
      expect(serializePendingEntries([]), '');
    });

    test('skips malformed lines instead of throwing', () {
      // A half-written line from an interrupted append must not take the whole
      // SessionStart hook down.
      const jsonl = '{"branch":"main","sha":"aaa111","armed_at":"2026-08-12T10:00:00Z"}\n'
          'not json at all\n'
          '{"branch":"main"\n' // truncated mid-object
          '{"branch":"","sha":"x","armed_at":"2026-08-12T10:00:00Z"}\n' // empty branch
          '{"branch":"b","sha":"y","armed_at":"nonsense"}\n' // unparseable date
          '{"sha":"z","armed_at":"2026-08-12T10:00:00Z"}\n' // no branch key
          '\n'
          '{"branch":"develop","sha":"bbb222","armed_at":"2026-08-12T11:00:00Z"}\n';

      final parsed = parsePendingEntries(jsonl);

      expect(parsed, hasLength(2),
          reason: 'only the two well-formed lines should survive');
      expect(parsed.map((e) => e.sha), ['aaa111', 'bbb222']);
    });
  });

  group('dedupeKeepingEarliest', () {
    test('collapses repeat arms of the same (branch, sha) to the earliest', () {
      final entries = [
        _entry('main', 'aaa111', _t0.add(const Duration(hours: 3))),
        _entry('main', 'aaa111', _t0),
        _entry('main', 'aaa111', _t0.add(const Duration(hours: 1))),
      ];

      final deduped = dedupeKeepingEarliest(entries);

      expect(deduped, hasLength(1));
      expect(deduped.single.armedAt.toUtc(), _t0,
          reason: 'the staleness clock must run from the first landing');
    });

    test('two SHAs on ONE branch survive as two entries', () {
      // The load-bearing case: keying on branch alone would collapse these and
      // leave a rebase-and-repush tracking the superseded commit's CI result.
      final entries = [
        _entry('main', 'aaa111', _t0),
        _entry('main', 'bbb222', _t0.add(const Duration(minutes: 1))),
      ];

      final deduped = dedupeKeepingEarliest(entries);

      expect(deduped, hasLength(2));
      expect(deduped.map((e) => e.sha).toSet(), {'aaa111', 'bbb222'});
    });
  });

  group('mergeConcurrentArrivals', () {
    test('an entry armed concurrently during classification survives', () {
      final initial = [_entry('main', 'aaa111', _t0)];
      final survivors = <PendingEntry>[];
      // Another session pushed while we were querying gh.
      final onDisk = [
        _entry('main', 'aaa111', _t0),
        _entry('main', 'ccc333', _t0.add(const Duration(minutes: 2))),
      ];

      final merged = mergeConcurrentArrivals(
        initialRead: initial,
        currentOnDisk: onDisk,
        survivors: survivors,
      );

      expect(merged.map((e) => e.sha), ['ccc333'],
          reason: 'the concurrent arm must not be lost by our rewrite');
    });

    test('NEVER resurrects an entry this run resolved and dropped', () {
      // The disaster case. The dropped entry is still physically on disk —
      // nothing has rewritten the file yet — so a "merge everything currently
      // on disk" implementation re-adds it every single run, with no
      // concurrency needed, permanently disabling classify-and-drop.
      final resolved = _entry('main', 'aaa111', _t0);
      final initial = [resolved];
      final survivors = <PendingEntry>[]; // we resolved + dropped it
      final onDisk = [resolved]; // still there, untouched

      final merged = mergeConcurrentArrivals(
        initialRead: initial,
        currentOnDisk: onDisk,
        survivors: survivors,
      );

      expect(merged, isEmpty,
          reason: 'a resolved entry present in initialRead must stay dropped');
    });

    test('does not duplicate an entry that is both a survivor and on disk', () {
      final kept = _entry('main', 'aaa111', _t0);
      final merged = mergeConcurrentArrivals(
        initialRead: [kept],
        currentOnDisk: [kept],
        survivors: [kept],
      );

      expect(merged, hasLength(1));
    });
  });

  group('classify — resolved outcomes', () {
    test('success resolves and is dropped silently', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: const GhRunQueryResult(
            found: true,
            conclusion: ConclusionClass.success,
            rawConclusion: 'success'),
        now: _t0.add(const Duration(minutes: 10)),
      );

      expect(o.action, ReconcileAction.resolvedSuccess);
      expect(o.warns, isFalse);
      expect(o.keeps, isFalse);
    });

    test('failure warns, carries its detail, and is dropped', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: const GhRunQueryResult(
          found: true,
          conclusion: ConclusionClass.failure,
          rawConclusion: 'failure',
          url: 'https://example.invalid/run/7',
          runId: 7,
        ),
        now: _t0.add(const Duration(minutes: 10)),
      );

      expect(o.action, ReconcileAction.resolvedFailure);
      expect(o.warns, isTrue);
      expect(o.keeps, isFalse,
          reason: 'remediation is a new push, which arms a fresh entry');
      expect(o.conclusion, 'failure');
      expect(o.url, 'https://example.invalid/run/7');
      expect(o.runId, 7);
    });

    test('a found-but-unfinished run keeps waiting, does not warn', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: const GhRunQueryResult(
            found: true, conclusion: ConclusionClass.pending),
        now: _t0.add(const Duration(days: 5)), // well past the bound
      );

      expect(o.action, ReconcileAction.stillPending,
          reason: 'a run that EXISTS is never "never ran", however old');
      expect(o.keeps, isTrue);
      expect(o.warns, isFalse);
    });
  });

  group('classify — staleness boundary', () {
    test('47h59m with no run found is still pending', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(hours: 47, minutes: 59)),
      );

      expect(o.action, ReconcileAction.stillPending);
      expect(o.keeps, isTrue);
      expect(o.warns, isFalse);
    });

    test('48h01m with no run found on main warns', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(hours: 48, minutes: 1)),
      );

      expect(o.action, ReconcileAction.staleNeverRan);
      expect(o.warns, isTrue);
      expect(o.keeps, isFalse);
      expect(o.ageHours, 48);
    });

    test('48h01m on DEVELOP warns too, not just main', () {
      // Hardcoding one CI branch and forgetting the other is a silent slip:
      // develop pushes trigger CI exactly as main pushes do.
      final o = classify(
        entry: _entry('develop', 'bbb222', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(hours: 48, minutes: 1)),
      );

      expect(o.action, ReconcileAction.staleNeverRan);
      expect(o.warns, isTrue);
    });

    test('48h01m on a PR-less working branch is silent, not a warning', () {
      // ADR-0018: most branches get no CI until merged, so "no run" there is
      // the expected outcome. Warning would fire on nearly every claude/* push
      // and train the reader to ignore the tool.
      final o = classify(
        entry: _entry('claude/some-feature', 'ccc333', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(hours: 48, minutes: 1)),
      );

      expect(o.action, ReconcileAction.staleExpected);
      expect(o.warns, isFalse);
      expect(o.keeps, isFalse,
          reason: 'dropping it stops the file growing forever');
    });

    test('a FAILED LOOKUP never warns "never ran", however old the entry', () {
      // The B-pass proved the pre-fix code emitted "A push to main should have
      // triggered CI... check whether Actions is enabled" when the real problem
      // was a local gh that could not be asked. Byte-identical output with gh
      // stripped from PATH. This is the assertion that keeps them apart.
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: GhRunQueryResult.unavailable,
        now: _t0.add(const Duration(days: 30)),
      );

      expect(o.action, ReconcileAction.stillPending,
          reason: '"I could not ask" is not evidence that CI never ran');
      expect(o.warns, isFalse);
      expect(o.keeps, isTrue,
          reason: 'keep it — we still owe an answer once gh works again');
    });

    test('a genuine notFound at the same age DOES warn (the mirror case)', () {
      // Without this, the test above would pass on code that simply never
      // warns at all.
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(days: 30)),
      );

      expect(o.action, ReconcileAction.staleNeverRan);
      expect(o.warns, isTrue);
    });

    test('the stale bound is configurable and respected', () {
      final o = classify(
        entry: _entry('main', 'aaa111', _t0),
        ghResult: GhRunQueryResult.notFound,
        now: _t0.add(const Duration(hours: 2)),
        staleBound: const Duration(hours: 1),
      );

      expect(o.action, ReconcileAction.staleNeverRan);
    });
  });

  group('ciTriggeringBranches', () {
    test('matches test.yml on.push.branches exactly', () {
      // If .github/workflows/test.yml's push branch list changes, this constant
      // must change with it — nothing detects the drift automatically.
      expect(ciTriggeringBranches, {'main', 'develop'});
    });
  });
}
