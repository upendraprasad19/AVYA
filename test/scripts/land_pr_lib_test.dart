// test/scripts/land_pr_lib_test.dart
//
// The pure decisions of scripts/land_pr_lib.dart and the CI classifier added to scripts/safe_pr_merge_lib.dart
// (landing D, docs/plans/merge-train.md sections 3 and 5).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/land_pr_lib.dart';
import '../../scripts/safe_pr_merge_lib.dart';

Map<String, dynamic> run(int id, String name, {String status = 'completed', String? conclusion = 'success', String slug = 'github-actions'}) =>
    {'id': id, 'name': name, 'status': status, 'conclusion': conclusion, 'app': {'slug': slug}};

List<Map<String, dynamic>> green() => [
      for (final (i, n) in [...requiredSuccessJobs, 'Unit Tests shard 1/4'].indexed) run(10 + i, n),
      run(30, skippedOkJobs.first, conclusion: 'skipped'),
    ];

List<Map<String, dynamic>> without(List<Map<String, dynamic>> runs, String name) => runs.where((r) => r['name'] != name).toList();

void main() {
  group('parseResultWord', () {
    test('the last line only', () {
      expect(parseResultWord('a\nresult: merged\n'), 'merged');
      expect(parseResultWord('result: merged'), 'merged');
      expect(parseResultWord('a\r\nresult: needs-human\r\n'), 'needs-human');
      expect(parseResultWord('result: merged   \n\n\n'), 'merged');
    });
    test('an earlier result line is not the answer when something follows it', () {
      expect(parseResultWord('result: merged\ntrailing'), isNull);
      expect(parseResultWord('result: a\nresult: b'), 'b');
    });
    test('absent, empty and malformed', () {
      expect(parseResultWord(''), isNull);
      expect(parseResultWord('\n\n'), isNull);
      expect(parseResultWord('nothing here'), isNull);
      expect(parseResultWord('result:'), isNull);
      expect(parseResultWord('result: a b'), isNull);
      expect(parseResultWord('  result: x'), isNull, reason: 'the prefix must start the line');
    });
  });

  group('syncNext', () {
    test('every word of the sync CLI maps, and the unknown ones are an error', () {
      expect(syncNext('up-to-date'), SyncNext.proceed);
      expect(syncNext('fast-forwarded'), SyncNext.proceed);
      expect(syncNext('committed'), SyncNext.proceed);
      expect(syncNext('pending'), SyncNext.needsHuman);
      expect(syncNext('commit-failed'), SyncNext.needsHuman);
      expect(syncNext('ready'), SyncNext.needsHuman);
      expect(syncNext('refused'), SyncNext.refused);
      expect(syncNext('error'), SyncNext.error);
      expect(syncNext('anything-else'), SyncNext.error);
      expect(syncNext(null), SyncNext.error);
      for (final w in syncResultWords) {
        expect(syncNext(w), isNotNull);
      }
    });
  });

  group('mergeOutcome', () {
    test('MERGED wins over every status', () {
      for (final st in [0, 1, 2, 3, 127]) {
        expect(mergeOutcome(status: st, merged: true), resMerged, reason: 'status $st');
      }
    });
    test('an unreadable state is merge-unverified, never merge-refused', () {
      for (final st in [0, 1, 2]) {
        expect(mergeOutcome(status: st, merged: null), resMergeUnverified, reason: 'status $st');
      }
    });
    test('not merged: exit 1 is merge-refused, everything else merge-unverified', () {
      expect(mergeOutcome(status: 1, merged: false), resMergeRefused);
      expect(mergeOutcome(status: 0, merged: false), resMergeUnverified);
      expect(mergeOutcome(status: 2, merged: false), resMergeUnverified);
      expect(mergeOutcome(status: 99, merged: false), resMergeUnverified);
    });
  });

  group('replayVerdict', () {
    const finalPass = '[plan-review-record] PASS: every landing in abc..def is accounted for — 1 merge(s) landed; NOTE';
    test('exit 0 and the final pass line', () {
      expect(replayVerdict(0, 'noise\n$finalPass\n'), isTrue);
    });
    test('the vacuous pass lines are not accepted', () {
      expect(replayVerdict(0, '[plan-review-record] PASS: not landing on main\n'), isFalse);
      expect(replayVerdict(0, '[plan-review-record] PASS: nothing landed in a..b\n'), isFalse);
      expect(replayVerdict(0, '[plan-review-record] PASS: every landing in a..b is accounted for — 0 merge(s)\n'), isFalse);
      expect(replayVerdict(0, '[plan-review-record] PASS: every landing in a..b is accounted for — 2 merge(s)\n'), isFalse);
    });
    test('FAIL, SKIP, empty and a non-zero exit are not accepted', () {
      expect(replayVerdict(1, finalPass), isFalse);
      expect(replayVerdict(0, '[plan-review-record] FAIL: x\n'), isFalse);
      expect(replayVerdict(0, '[plan-review-record] SKIP: x\n'), isFalse);
      expect(replayVerdict(0, ''), isFalse);
    });
    test('the pass line must start the line', () {
      expect(replayVerdict(0, 'x [plan-review-record] PASS: every landing in a..b — 1 merge(s)'), isFalse);
    });
  });

  group('roundNext', () {
    test('main already an ancestor goes to the replay and merge, at any round', () {
      for (final r in [1, 2, 3]) {
        expect(roundNext(round: r, mainIsAncestor: true), RoundNext.replayAndMerge);
      }
    });
    test('main moved: rounds 1 and 2 go round again, round 3 gives up', () {
      expect(roundNext(round: 1, mainIsAncestor: false), RoundNext.nextRound);
      expect(roundNext(round: 2, mainIsAncestor: false), RoundNext.nextRound);
      expect(roundNext(round: 3, mainIsAncestor: false), RoundNext.giveUp);
      expect(maxRounds, 3);
    });
  });

  group('the exit table', () {
    test('every result constant agrees with exitCodeByWord and stays within the CLI range', () {
      for (final r in [resMerged, resNeedsHuman, resRefused, resCiFailed, resCiTimeout, resError, resRecordFailed, resMergeRefused, resMergeUnverified]) {
        expect(exitCodeByWord[r.word], r.code, reason: r.word);
        expect(r.code, lessThanOrEqualTo(maxCliStatus));
      }
      expect(exitCodeByWord.length, 9);
      expect(maxCliStatus, 7);
    });
  });

  group('CiWatch', () {
    CiJudgement j(CiState s, [Set<String> c = const {}]) => (state: s, cancelledOnly: c);

    test('green and red pass through, pending stays pending', () {
      final w = CiWatch();
      expect(w.update(j(CiState.pending)).state, CiTickState.pending);
      expect(w.update(j(CiState.red)).state, CiTickState.red);
      expect(w.update(j(CiState.green)).state, CiTickState.green);
    });
    test('ten consecutive gh failures end the wait; nine do not', () {
      final w = CiWatch();
      for (var i = 1; i <= 9; i++) {
        expect(w.update(null).state, CiTickState.pending, reason: 'failure $i');
      }
      expect(w.update(null).state, CiTickState.ghFailing);
    });
    test('a good read resets the failure counter', () {
      final w = CiWatch();
      for (var i = 0; i < 9; i++) {
        w.update(null);
      }
      expect(w.update(j(CiState.pending)).state, CiTickState.pending);
      for (var i = 0; i < 9; i++) {
        expect(w.update(null).state, CiTickState.pending);
      }
      expect(w.update(null).state, CiTickState.ghFailing);
    });
    test('a job cancelled-only on three consecutive polls makes the poll red; two do not', () {
      final w = CiWatch();
      expect(w.update(j(CiState.pending, {'Analyze'})).state, CiTickState.pending);
      expect(w.update(j(CiState.pending, {'Analyze'})).state, CiTickState.pending);
      final t = w.update(j(CiState.pending, {'Analyze'}));
      expect(t.state, CiTickState.red);
      expect(t.note, contains('Analyze'));
    });
    test('the cancelled streak is per job and resets when the job is no longer cancelled-only', () {
      final w = CiWatch();
      w.update(j(CiState.pending, {'Analyze'}));
      w.update(j(CiState.pending, {'Analyze'}));
      expect(w.update(j(CiState.pending)).state, CiTickState.pending, reason: 'streak reset');
      expect(w.update(j(CiState.pending, {'Analyze'})).state, CiTickState.pending);
      expect(w.update(j(CiState.pending, {'Analyze'})).state, CiTickState.pending);
      expect(w.update(j(CiState.pending, {'Analyze', 'Audit Gates'})).state, CiTickState.red);
    });
  });

  group('prRefusal', () {
    Map<String, dynamic> pr({String state = 'OPEN', bool draft = false, String head = 'b', String base = 'main', Object fork = false}) =>
        {'state': state, 'isDraft': draft, 'headRefName': head, 'baseRefName': base, 'isCrossRepository': fork};

    test('an open, non-draft, same-repo PR from this branch to main is landable', () {
      expect(prRefusal(pr(), 'b', allowMerged: true), isNull);
    });
    test('each refusal', () {
      expect(prRefusal(pr(head: 'x'), 'b', allowMerged: true), contains('"x"'));
      expect(prRefusal(pr(fork: true), 'b', allowMerged: true), contains('fork'));
      expect(prRefusal(pr(state: 'CLOSED'), 'b', allowMerged: true), contains('CLOSED'));
      expect(prRefusal(pr(draft: true), 'b', allowMerged: true), contains('draft'));
      expect(prRefusal(pr(base: 'dev'), 'b', allowMerged: true), contains('dev'));
    });
    test('a missing or odd field is a refusal, never a pass', () {
      expect(prRefusal({'state': 'OPEN'}, 'b', allowMerged: true), isNotNull);
      expect(prRefusal(pr(fork: 'maybe'), 'b', allowMerged: true), isNotNull);
    });
    test('MERGED is accepted only with allowMerged, and the head and fork checks still apply', () {
      expect(prRefusal(pr(state: 'MERGED'), 'b', allowMerged: true), isNull);
      expect(prRefusal(pr(state: 'MERGED'), 'b', allowMerged: false), contains('MERGED'));
      expect(prRefusal(pr(state: 'MERGED', head: 'x'), 'b', allowMerged: true), isNotNull);
      expect(prRefusal(pr(state: 'MERGED', fork: true), 'b', allowMerged: true), isNotNull);
      expect(prIsMerged(pr(state: 'MERGED')), isTrue);
      expect(prIsMerged(pr()), isFalse);
    });
  });

  group('small helpers', () {
    test('in-progress state files include the sequencer and MERGE_HEAD', () {
      expect(inProgressStateFiles, containsAll(['MERGE_HEAD', 'rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'BISECT_LOG', 'sequencer']));
    });
    test('workflowChangeRefusal follows the merge wrapper', () {
      expect(workflowChangeRefusal(['lib/a.dart'], allowWorkflowChange: false), isNull);
      expect(workflowChangeRefusal(['.github/workflows/test.yml'], allowWorkflowChange: false), isNotNull);
      expect(workflowChangeRefusal(['.github/workflows/test.yml'], allowWorkflowChange: true), isNull);
    });
    test('splitCommand splits like safe_pr_merge.dart', () {
      final c = splitCommand('  /a/b/gh   --x  y ');
      expect(c.exe, '/a/b/gh');
      expect(c.prefix, ['--x', 'y']);
    });
    test('prefixLines prefixes every line, drops CR, keeps the shape', () {
      expect(prefixLines('sync', 'a\r\nb\n'), 'sync> a\nsync> b');
      expect(prefixLines('sync', ''), '');
      expect(prefixLines('x', 'result: merged'), 'x> result: merged');
    });
    test('replayDirName and staleReplayDir touch only their own, only when old', () {
      const day = 24 * 60 * 60 * 1000;
      final name = replayDirName(42, 1000);
      expect(name, 'land_pr_replay-42-1000');
      expect(staleReplayDir(name, 1000 + day + 1), isTrue);
      expect(staleReplayDir(name, 1000 + day), isFalse);
      expect(staleReplayDir(name, 5000), isFalse);
      expect(staleReplayDir('other-42-1000', 1000 + 3 * day), isFalse);
      expect(staleReplayDir('land_pr_replay-x-y', 9999999999999), isFalse);
      expect(staleReplayDir('land_pr_replay-', 9999999999999), isFalse);
    });
    test('replayMergeMessage and ownerOf', () {
      expect(replayMergeMessage('191', 'acme', 'feat'), 'Merge pull request #191 from acme/feat');
      expect(ownerOf('acme/avya'), 'acme');
      expect(ownerOf('noslash'), isNull);
      expect(ownerOf('/x'), isNull);
      expect(ownerOf('x/'), isNull);
    });
    test('unpushedSummary counts and truncates', () {
      expect(unpushedSummary([]), 'no local commits to push');
      expect(unpushedSummary(['a b']), '1 commit(s) will be pushed:\n  a b');
      final many = unpushedSummary([for (var i = 0; i < 25; i++) 'c$i']);
      expect(many, contains('25 commit(s)'));
      expect(many, contains('c19'));
      expect(many, isNot(contains('c20\n')));
      expect(many, contains('and 5 more'));
    });
  });

  group('classifyCheckRuns reads the SAME judgement as evaluateCheckRuns', () {
    final fixtures = <String, List<Map<String, dynamic>>?>{
      'all green': green(),
      'a required job failed': [...without(green(), 'Analyze'), run(50, 'Analyze', conclusion: 'failure')],
      'a shard failed': [...without(green(), 'Unit Tests shard 1/4'), run(50, 'Unit Tests shard 1/4', conclusion: 'failure')],
      'failed then rerun in progress': [run(5, 'Analyze', conclusion: 'failure'), ...without(green(), 'Analyze'), run(60, 'Analyze', status: 'in_progress', conclusion: null)],
      'failed then green': [run(5, 'Analyze', conclusion: 'failure'), ...without(green(), 'Analyze'), run(60, 'Analyze')],
      'cancelled then green': [run(5, 'Analyze', conclusion: 'cancelled'), ...without(green(), 'Analyze'), run(60, 'Analyze')],
      'a required job only cancelled': [...without(green(), 'Analyze'), run(5, 'Analyze', conclusion: 'cancelled')],
      'a job pending': [...without(green(), 'Unit Tests'), run(50, 'Unit Tests', status: 'in_progress', conclusion: null)],
      'red AND pending together': [...without(without(green(), 'Unit Tests'), 'Analyze'), run(50, 'Unit Tests', status: 'in_progress', conclusion: null), run(51, 'Analyze', conclusion: 'failure')],
      'a required job missing': without(green(), 'Audit Gates'),
      'no runs': <Map<String, dynamic>>[],
      'only third-party runs': [run(1, 'Vercel', slug: 'vercel')],
      'a required job skipped': [...without(green(), 'Analyze'), run(50, 'Analyze', conclusion: 'skipped')],
      'a skippedOk job neutral': [...without(green(), skippedOkJobs.first), run(50, skippedOkJobs.first, conclusion: 'neutral')],
      'a skippedOk job timed out': [...without(green(), skippedOkJobs.first), run(50, skippedOkJobs.first, conclusion: 'timed_out')],
      'startup_failure': [...without(green(), 'Audit Gates'), run(50, 'Audit Gates', conclusion: 'startup_failure')],
      'timed_out': [...without(green(), 'Audit Gates'), run(50, 'Audit Gates', conclusion: 'timed_out')],
      'stale': [...without(green(), 'Audit Gates'), run(50, 'Audit Gates', conclusion: 'stale')],
      'an unlisted job cancelled only': [...green(), run(70, 'Extra job', conclusion: 'cancelled')],
      'an unlisted job neutral': [...green(), run(70, 'Extra job', conclusion: 'neutral')],
      'an unlisted job failing': [...green(), run(70, 'Extra job', conclusion: 'failure')],
      'null (the lookup failed)': null,
    };
    for (final e in fixtures.entries) {
      test('${e.key}: green exactly when the judge says ok', () {
        final judged = evaluateCheckRuns(e.value);
        final c = classifyCheckRuns(e.value);
        expect(c.state == CiState.green, judged.ok, reason: judged.reasons.join('; '));
      });
    }

    CiState state(String k) => classifyCheckRuns(fixtures[k]).state;
    test('the red / pending partition', () {
      expect(state('all green'), CiState.green);
      for (final k in ['a required job failed', 'a shard failed', 'a required job skipped', 'a skippedOk job neutral', 'a skippedOk job timed out', 'startup_failure', 'timed_out', 'stale', 'an unlisted job failing']) {
        expect(state(k), CiState.red, reason: k);
      }
      for (final k in ['failed then rerun in progress', 'a required job only cancelled', 'a job pending', 'a required job missing', 'no runs', 'only third-party runs', 'an unlisted job cancelled only', 'null (the lookup failed)']) {
        expect(state(k), CiState.pending, reason: k);
      }
      for (final k in ['failed then green', 'cancelled then green', 'an unlisted job neutral']) {
        expect(state(k), CiState.green, reason: k);
      }
    });
    test('red wins over pending (fail early)', () {
      expect(state('red AND pending together'), CiState.red);
    });
    test('the cancelled-only set names the jobs, required or not', () {
      expect(classifyCheckRuns(fixtures['a required job only cancelled']).cancelledOnly, {'Analyze'});
      expect(classifyCheckRuns(fixtures['an unlisted job cancelled only']).cancelledOnly, {'Extra job'});
      expect(classifyCheckRuns(fixtures['all green']).cancelledOnly, isEmpty);
      expect(classifyCheckRuns(fixtures['cancelled then green']).cancelledOnly, isEmpty);
    });
    test('evaluateCheckRuns keeps its reasons byte for byte (the refactor is behaviour preserving)', () {
      expect(evaluateCheckRuns(null).reasons, ['could not read the check-runs for the PR head (refusing: unknown is not green)']);
      expect(evaluateCheckRuns(<Map<String, dynamic>>[]).reasons.single, startsWith('no GitHub Actions check-runs exist'));
      expect(evaluateCheckRuns(fixtures['a required job failed']).reasons, ['"Analyze" concluded failure (required: success)']);
      expect(evaluateCheckRuns(fixtures['a job pending']).reasons, ['"Unit Tests" is in_progress (not finished) (required: success)']);
      expect(evaluateCheckRuns(fixtures['a required job missing']).reasons, ['"Audit Gates" has no check-run (required)']);
      expect(evaluateCheckRuns(fixtures['a required job only cancelled']).reasons, ['"Analyze" has only cancelled runs']);
      expect(evaluateCheckRuns(fixtures['an unlisted job failing']).reasons, ['"Extra job" concluded failure']);
    });
  });

  test('the library has no File or Process (check_gate_existssync_file_vs_dir guards *_lib.dart)', () {
    final src = File('scripts/land_pr_lib.dart').readAsStringSync();
    expect(src.contains('File('), isFalse);
    expect(src.contains('Process.'), isFalse);
    expect(src.contains("import 'dart:io'"), isFalse);
  });
}
