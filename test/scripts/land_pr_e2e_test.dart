@Timeout(Duration(minutes: 12))
library;

// test/scripts/land_pr_e2e_test.dart
//
// scripts/land_pr.dart against REAL git in throwaway repositories, with the stub protocol of
// test/helpers/land_pr_fixture.dart for gh, the three wrappers and the record gate (landing D,
// docs/plans/merge-train.md section 5). Rule 21: every row asserts the exit code AND the `result:` protocol (exactly one
// `result:` line, and it is the last), then what the stubs were asked, in order.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/land_pr_fixture.dart';
import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';

List<String> happyCalls = <String>[
  'gh repo',
  'gh pr-pre',
  'gh pr-files',
  'sync',
  'gh check-runs',
  'gh pr-head',
  'gate',
  'merge',
  'gh pr-state',
];

String out(ProcessResult r) => '${r.stdout}';

void main() {
  group('the happy path and its order', () {
    test('up to date, nothing to push, CI green, merged: every stub is asked, in order', () {
      final fx = LandFixture.create();
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(fx.calls, happyCalls);
      expect(fx.log.where((l) => l.contains(' sync ')).single, endsWith('sync --commit'));
      expect(fx.log.where((l) => l.contains(' merge ')).single, endsWith('merge 191'));
      expect(fx.count('push'), 0, reason: 'HEAD is the remote tip: no push');
    });

    test('an unpushed commit is listed, pushed, and CI is read for the PUSHED head', () {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'lib/b.dart': 'b\n'}, msg: 'add b');
      final local = fx.cli.head;
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(out(r), contains('1 commit(s) will be pushed'));
      expect(out(r), contains('add b'));
      expect(fx.calls, containsAllInOrder(['sync', 'push', 'gh check-runs', 'gate', 'merge']));
      expect(fx.log.where((l) => l.contains(' push ')).single, endsWith('push origin feature'));
      expect(fx.cli.repo.must(['ls-remote', 'origin', 'refs/heads/feature']), startsWith(local));
    });

    test('a sync that merges (committed) is followed by a push of the merge, then green, then merged', () {
      final fx = LandFixture.create();
      fx.cli.mainCommit({'lib/m.dart': 'm\n'});
      fx.sync(1, word: 'committed', mode: 'merge');
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(fx.calls, containsAllInOrder(['sync', 'push', 'gh check-runs', 'gate', 'merge']));
      expect(fx.cli.repo.must(['ls-remote', 'origin', 'refs/heads/feature']), startsWith(fx.cli.head));
    });

    test('the child output is passed through with a prefix: exactly ONE line starts with result:', () {
      final fx = LandFixture.create();
      fx.sync(1, text: 'sync_with_main: hello\nresult: up-to-date');
      fx.merge(1, out: 'safe_pr_merge: merged\nresult: merged');
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(out(r), contains('sync> result: up-to-date'));
      expect(out(r), contains('merge> result: merged'));
    });
  });

  group('the sync step decides', () {
    final cases = <(String, int, String, int)>[
      ('pending', 1, 'needs-human', 1),
      ('commit-failed', 3, 'needs-human', 1),
      ('ready', 0, 'needs-human', 1),
      ('refused', 2, 'refused', 2),
      ('error', 4, 'error', 4),
      ('bogus-word', 0, 'error', 4),
    ];
    for (final c in cases) {
      test('sync result: ${c.$1} (exit ${c.$2}) -> result: ${c.$3}, exit ${c.$4}, nothing pushed, no CI wait', () {
        final fx = LandFixture.create();
        fx.sync(1, word: c.$1, exit: c.$2);
        final r = fx.land();
        expectResult(r, c.$4, c.$3);
        expect(fx.calls.last, 'sync');
      });
    }

    test('a sync that prints no result line is an error', () {
      final fx = LandFixture.create();
      fx.sync(1, text: 'sync_with_main: something');
      expectResult(fx.land(), 4, 'error');
      expect(fx.calls.last, 'sync');
    });

    test('a sync with a result line that is NOT last is an error (anything after it makes the protocol unreadable)', () {
      final fx = LandFixture.create();
      fx.sync(1, text: 'result: up-to-date\ntrailing noise');
      expectResult(fx.land(), 4, 'error');
    });

    test('a failed push is an error and stops before CI', () {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'lib/b.dart': 'b\n'});
      fx.push(1, exit: 1);
      expectResult(fx.land(), 4, 'error');
      expect(fx.calls.last, 'push');
    });
  });

  group('--ci-only (review CI, CLAUDE.md §4.12.8)', () {
    test('CI green: result ci-green, exit 0, and the run ends at the CI wait (no PR-head check, record gate, merge)', () {
      final fx = LandFixture.create();
      final r = fx.land(extra: ['--ci-only']);
      expectResult(r, 0, 'ci-green');
      expect(fx.calls, ['gh repo', 'gh pr-pre', 'gh pr-files', 'sync', 'gh check-runs']);
      expect(out(r), contains('stopping before the merge'));
    });
    test('a red required job is still ci-failed, exit 3 (the flag changes nothing before green)', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Analyze': 'completed/failure'}));
      final r = fx.land(extra: ['--ci-only']);
      expectResult(r, 3, 'ci-failed');
      expect(fx.calls, isNot(contains('merge')));
    });
    test('an unpushed commit is pushed and CI is read for the PUSHED head, then ci-green', () {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'lib/b.dart': 'b\n'}, msg: 'add b');
      final local = fx.cli.head;
      final r = fx.land(extra: ['--ci-only']);
      expectResult(r, 0, 'ci-green');
      expect(fx.calls, ['gh repo', 'gh pr-pre', 'gh pr-files', 'sync', 'push', 'gh check-runs']);
      expect(fx.log.firstWhere((l) => l.contains(' gh check-runs ')), contains('/commits/$local/check-runs'));
      expect(fx.cli.repo.must(['ls-remote', 'origin', 'refs/heads/feature']), startsWith(local));
    });
    test('--ci-only given twice is refused before anything runs', () {
      final fx = LandFixture.create();
      final r = runLand(fx, ['191', '--ci-only', '--ci-only']);
      expectResult(r, 2, 'refused');
      expect(out(r), contains('--ci-only given twice'));
      expect(fx.log, isEmpty);
    });
  });

  group('waiting for CI', () {
    test('a red required job is ci-failed, exit 3, and the job is named', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Analyze': 'completed/failure'}));
      final r = fx.land();
      expectResult(r, 3, 'ci-failed');
      expect(out(r), contains('Analyze'));
      expect(fx.calls, isNot(contains('merge')));
    });

    test('a red matrix shard is ci-failed', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Unit Tests shard 2/4': 'completed/failure'}));
      expectResult(fx.land(), 3, 'ci-failed');
    });

    test('startup_failure is red at once (not a 60 minute wait)', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Audit Gates': 'completed/startup_failure'}));
      expectResult(fx.land(), 3, 'ci-failed');
    });

    test('a failed attempt followed by a rerun IN PROGRESS is not red: it keeps waiting, then merges', () {
      final fx = LandFixture.create();
      fx.q(
          'check-runs',
          1,
          checkRunsList([
            ...allGreen().entries.where((e) => e.key != 'Analyze').map((e) => (e.key, e.value)),
            ('Analyze', 'completed/failure'),
            ('Analyze', 'in_progress/-'),
          ]));
      fx.q(
          'check-runs',
          2,
          checkRunsList([
            ...allGreen().entries.where((e) => e.key != 'Analyze').map((e) => (e.key, e.value)),
            ('Analyze', 'completed/failure'),
            ('Analyze', 'completed/success'),
          ]));
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(fx.calls.where((c) => c == 'gh check-runs').length, 2);
    });

    test('a pending job until the deadline is ci-timeout (exit 3) and names the job', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Unit Tests': 'in_progress/-'}));
      final r = fx.land(ciTimeoutMs: 400, pollMs: 30);
      expectResult(r, 3, 'ci-timeout');
      expect(out(r), contains('Unit Tests'));
      expect(fx.calls, isNot(contains('merge')));
    });

    test('no runs yet is pending, then the runs arrive: merged', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, '{"total_count":0,"check_runs":[]}');
      fx.q('check-runs', 2, checkRunsBody(allGreen()));
      expectResult(fx.land(), 0, 'merged');
    });

    test('a gh failure while waiting keeps waiting (never green), then merged', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, '', exit: 1, stderr: 'HTTP 502');
      fx.q('check-runs', 2, checkRunsBody(allGreen()));
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(fx.calls.where((c) => c == 'gh check-runs').length, 2);
    });

    test('an unparseable check-runs reply is pending (never green)', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, '{"total_count":5,"check_runs":[]}');
      fx.q('check-runs', 2, checkRunsBody(allGreen()));
      expectResult(fx.land(), 0, 'merged');
    });

    test('ten gh failures in a row end in error (exit 4), exactly ten reads', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, '', exit: 1);
      final r = fx.land(pollMs: 5, ciTimeoutMs: 60000);
      expectResult(r, 4, 'error');
      expect(out(r), contains('gh failed 10 times in a row'));
      expect(fx.calls.where((c) => c == 'gh check-runs').length, 10);
    });

    test('a failure in the middle resets the counter: nine failures, a good pending read, nine more, then green', () {
      final fx = LandFixture.create();
      for (var i = 1; i <= 9; i++) {
        fx.q('check-runs', i, '', exit: 1);
      }
      fx.q('check-runs', 10, checkRunsBody({...allGreen(), 'Unit Tests': 'in_progress/-'}));
      for (var i = 11; i <= 19; i++) {
        fx.q('check-runs', i, '', exit: 1);
      }
      fx.q('check-runs', 20, checkRunsBody(allGreen()));
      expectResult(fx.land(pollMs: 5, ciTimeoutMs: 60000), 0, 'merged');
    });

    test('a required job that stays cancelled-only for three polls is red', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Analyze': 'completed/cancelled'}));
      final r = fx.land(pollMs: 5);
      expectResult(r, 3, 'ci-failed');
      expect(out(r), contains('only cancelled runs'));
      expect(fx.calls.where((c) => c == 'gh check-runs').length, 3);
    });

    test('cancelled once, then a good run: not red', () {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Analyze': 'completed/cancelled'}));
      fx.q('check-runs', 2, checkRunsBody(allGreen()));
      expectResult(fx.land(pollMs: 5), 0, 'merged');
    });

    test('CI is read for the pushed HEAD, through --paginate', () {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'lib/b.dart': 'b\n'});
      expectResult(fx.land(), 0, 'merged');
      final line = fx.log.firstWhere((l) => l.contains(' gh check-runs '));
      expect(line, contains('/commits/${fx.cli.head}/check-runs'));
      expect(line, contains('--paginate'));
      expect(fx.log.firstWhere((l) => l.contains(' gh pr-files ')), contains('--paginate'));
    });

    test('a hung gh is killed at its deadline and counted as a failed read', () {
      final fx = LandFixture.create();
      fx.pre('check-runs', 1, 'sleep 30');
      final started = DateTime.now();
      final r = runLand(fx, ['191', ...seamArgs(fx), '--gh-timeout-ms', '400']);
      expectResult(r, 0, 'merged');
      expect(DateTime.now().difference(started).inSeconds, lessThan(20), reason: 'the hung gh must not hold the run');
    });
  });

  group('child output and our own streams', () {
    test('a non-UTF-8 byte in a child line does not stop the pump: the child result line is still read', () {
      final fx = LandFixture.create();
      fx.pre('sync', 1, r"printf '\377 stray\n'");
      expectResult(fx.land(), 0, 'merged');
    });

    test('a multi-line gh error is printed on ONE land_pr line (no later line can start with result:)', () {
      final fx = LandFixture.create();
      fx.q('pr-pre', 1, '', exit: 1, stderr: 'first line\nresult: merged\nthird line');
      final r = fx.land();
      expectResult(r, 2, 'refused');
      final lines = out(r).split('\n');
      expect(lines.where((l) => l.startsWith('result:')).length, 1, reason: out(r));
      expect(out(r), contains('first line | result: merged | third line'));
    });

    test('a closed stdout does not end the run: the landing still goes through to the merge', () async {
      final fx = LandFixture.create();
      final p = await startSpawn('sh', ['-c', r'exec "$@" >&-', 'sh', dartBin(), fx.landCli, '191', ...seamArgs(fx)],
          workingDirectory: fx.dir, extraEnv: fx.cli.repo.env, allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
      final e = StringBuffer();
      final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
      final code = await p.exitCode.timeout(const Duration(seconds: 90));
      await d2;
      reportSpawn(code, '', e.toString(), 'land_pr CLI with a closed stdout');
      expect(code, 0, reason: e.toString());
      expect(fx.calls, contains('merge'));
    });
  });

  group('main and the PR head move', () {
    test('main moves during CI: a second round (sync, push, CI) then merged', () {
      final fx = LandFixture.create();
      fx.movesMain('check-runs', 1);
      fx.sync(2, word: 'committed', mode: 'merge');
      final r = fx.land();
      expectResult(r, 0, 'merged');
      expect(fx.calls.where((c) => c == 'sync').length, 2);
      expect(fx.calls.where((c) => c == 'push').length, 1);
      expect(fx.cli.repo.git(['merge-base', '--is-ancestor', 'refs/remotes/origin/main', 'HEAD']).exitCode, 0);
    });

    test('main moves twice: merged in round 3', () {
      final fx = LandFixture.create();
      fx.movesMain('check-runs', 1);
      fx.movesMain('check-runs', 2, file: 'moved2.txt');
      fx.sync(2, word: 'committed', mode: 'merge');
      fx.sync(3, word: 'committed', mode: 'merge');
      expectResult(fx.land(), 0, 'merged');
      expect(fx.calls.where((c) => c == 'sync').length, 3);
    });

    test('main moves after round 3: exit 1 with the exact message and no gate or merge call', () {
      final fx = LandFixture.create();
      for (var i = 1; i <= 3; i++) {
        fx.movesMain('check-runs', i, file: 'moved$i.txt');
      }
      fx.sync(2, word: 'committed', mode: 'merge');
      fx.sync(3, word: 'committed', mode: 'merge');
      final r = fx.land();
      expectResult(r, 1, 'needs-human');
      expect(out(r), contains('main moved three times while this branch waited for CI; run the command again'));
      expect(fx.calls.where((c) => c == 'sync').length, 3);
      expect(fx.calls, isNot(contains('gate')));
      expect(fx.calls, isNot(contains('merge')));
    });

    test('the PR head is not the head that was synced and tested: exit 1, both shas named, no gate or merge', () {
      final fx = LandFixture.create();
      fx.q('pr-head', 1, '{"headRefOid":"${'d' * 40}"}');
      final r = fx.land();
      expectResult(r, 1, 'needs-human');
      expect(out(r), contains('d' * 40));
      expect(fx.calls, isNot(contains('gate')));
      expect(fx.calls, isNot(contains('merge')));
    });

    test('an unreadable PR head is an error, never "equal"', () {
      final fx = LandFixture.create();
      fx.q('pr-head', 1, '', exit: 1);
      expectResult(fx.land(), 4, 'error');
      expect(fx.calls.where((c) => c == 'gh pr-head').length, 2, reason: 'one retry');
      expect(fx.calls, isNot(contains('merge')));
    });

    test('someone pushed to the PR branch while round 1 waited: round 2 sees a remote tip that is not an ancestor: exit 1, never a force-push', () {
      final fx = LandFixture.create();
      final other = '${fx.cli.repo.root.path}/pusher';
      runSpawn('git', ['clone', '-q', fx.cli.origin, other],
          why: 'land_pr_e2e: pusher clone', extraEnv: fx.cli.repo.env, allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
      for (final c in [
        ['config', 'user.email', 'p@e.com'],
        ['config', 'user.name', 'P'],
      ]) {
        fx.cli.repo.must(['-C', other, ...c]);
      }
      fx.pre('check-runs', 1, '''
cd "$other" && git checkout -q main && echo m >> m.txt && git add -A && git commit -q -m "main moved" && git push -q origin main \\
  && git checkout -q feature && echo x > p.txt && git add -A && git commit -q -m "someone else" && git push -q origin feature
''');
      fx.sync(2, word: 'committed', mode: 'merge');
      final r = fx.land();
      expectResult(r, 1, 'needs-human');
      expect(out(r), contains('someone pushed to origin/feature'));
      expect(fx.calls.where((c) => c == 'push').length, 0);
      expect(fx.calls, isNot(contains('merge')));
    });
  });

  group('the record replay and the merge', () {
    test('the record gate prints no PASS line (a SKIP): record-failed, exit 5, no merge call', () {
      final fx = LandFixture.create();
      fx.gate(1, out: '[plan-review-record] SKIP: no usable range base');
      expectResult(fx.land(), 5, 'record-failed');
      expect(fx.calls, isNot(contains('merge')));
    });

    test('the record gate prints a FAIL: record-failed', () {
      final fx = LandFixture.create();
      fx.gate(1, exit: 1, out: '[plan-review-record] FAIL: bpass_review does not exist');
      final r = fx.land();
      expectResult(r, 5, 'record-failed');
      expect(out(r), contains('gate> [plan-review-record] FAIL'));
    });

    test('the two VACUOUS pass lines are not accepted', () {
      for (final line in [
        '[plan-review-record] PASS: not landing on main',
        '[plan-review-record] PASS: nothing landed in a..b',
        '[plan-review-record] PASS: every landing in a..b is accounted for — 0 merge(s)',
      ]) {
        final fx = LandFixture.create();
        fx.gate(1, out: line);
        expectResult(fx.land(), 5, 'record-failed');
        expect(fx.calls, isNot(contains('merge')), reason: line);
      }
    });

    test('a PASS line with exit 1 is not accepted', () {
      final fx = LandFixture.create();
      fx.gate(1, exit: 1);
      expectResult(fx.land(), 5, 'record-failed');
    });

    final mergeCases = <(String, int, String, String, int)>[
      // name, merge exit, PR state after, word, code
      ('exit 1 and the PR is OPEN', 1, 'OPEN', 'merge-refused', 6),
      ('exit 2 and the PR is OPEN', 2, 'OPEN', 'merge-unverified', 7),
      ('exit 0 but the PR reads OPEN', 0, 'OPEN', 'merge-unverified', 7),
      ('exit 1 but the PR reads MERGED', 1, 'MERGED', 'merged', 0),
      ('exit 2 but the PR reads MERGED', 2, 'MERGED', 'merged', 0),
    ];
    for (final c in mergeCases) {
      test('the merge wrapper: ${c.$1} -> result: ${c.$4}, exit ${c.$5}', () {
        final fx = LandFixture.create();
        fx.merge(1, exit: c.$2, out: 'safe_pr_merge: said something');
        fx.q('pr-state', 1, '{"state":"${c.$3}"}');
        final r = fx.land();
        expectResult(r, c.$5, c.$4);
        expect(out(r), contains('merge> safe_pr_merge: said something'));
      });
    }

    test('an unreadable PR state after the merge is merge-unverified, even for a wrapper exit 1 (never merge-refused)', () {
      final fx = LandFixture.create();
      fx.merge(1, exit: 1);
      fx.q('pr-state', 1, '', exit: 1);
      expectResult(fx.land(), 7, 'merge-unverified');
      expect(fx.calls.where((c) => c == 'gh pr-state').length, 2, reason: 'one retry');
    });

    test('--allow-workflow-change is absent from the merge argv by default and present when given', () {
      final fx = LandFixture.create();
      expectResult(fx.land(), 0, 'merged');
      expect(fx.log.singleWhere((l) => l.contains(' merge ')), isNot(contains('--allow-workflow-change')));

      final fx2 = LandFixture.create();
      fx2.q('pr-files', 1, '[{"filename":".github/workflows/test.yml"}]');
      expectResult(fx2.land(extra: ['--allow-workflow-change']), 0, 'merged');
      expect(fx2.log.singleWhere((l) => l.contains(' merge ')), endsWith('merge 191 --allow-workflow-change'));
    });
  });

  group('preconditions: refused, nothing changed, nothing asked of the stubs that changes a thing', () {
    void refused(String name, void Function(LandFixture fx) arrange, {String? text, List<String>? onlyCalls}) {
      test(name, () {
        final fx = LandFixture.create();
        arrange(fx);
        final before = fx.cli.snapshot();
        final r = fx.land();
        expectResult(r, 2, 'refused');
        if (text != null) expect(out(r), contains(text));
        expect(fx.cli.snapshot(), before, reason: 'a refusal changes nothing');
        expect(fx.calls, isNot(contains('sync')));
        expect(fx.calls, isNot(contains('push')));
        expect(fx.calls, isNot(contains('merge')));
        if (onlyCalls != null) expect(fx.calls, onlyCalls);
      });
    }

    refused('a detached HEAD', (fx) => fx.cli.repo.must(['checkout', '-q', '--detach']), text: 'detached');
    refused('the protected branch main', (fx) => fx.cli.repo.checkout('main'), text: 'protected');
    refused('a modified tracked file', (fx) => fx.cli.repo.write('lib/a.dart', 'changed\n'), text: 'modified or staged');
    refused('a merge in progress (MERGE_HEAD)', (fx) => File('${fx.cli.gitDir}/MERGE_HEAD').writeAsStringSync('${fx.cli.head}\n'),
        text: 'in progress');
    refused('a sequencer directory', (fx) => Directory('${fx.cli.gitDir}/sequencer').createSync(), text: 'sequencer');
    refused('a bisect in progress', (fx) => File('${fx.cli.gitDir}/BISECT_LOG').writeAsStringSync('x\n'), text: 'BISECT_LOG');
    refused('a cherry-pick in progress', (fx) => File('${fx.cli.gitDir}/CHERRY_PICK_HEAD').writeAsStringSync('${fx.cli.head}\n'),
        text: 'CHERRY_PICK_HEAD');
    refused('a closed PR', (fx) => fx.prPre(1, state: 'CLOSED'), text: 'CLOSED');
    refused('a draft PR', (fx) => fx.prPre(1, draft: true), text: 'draft');
    refused('a PR whose base is not main', (fx) => fx.prPre(1, base: 'develop'), text: 'develop');
    refused('a fork PR', (fx) => fx.prPre(1, fork: true), text: 'fork');
    refused('a PR from another branch', (fx) => fx.prPre(1, head: 'other-branch'), text: 'other-branch');
    refused('a MERGED PR from another branch (the already-merged short circuit does not skip the head check)',
        (fx) => fx.prPre(1, state: 'MERGED', head: 'other-branch'),
        text: 'other-branch');
    refused('gh cannot read the repository', (fx) => fx.q('repo', 1, '', exit: 1, stderr: 'no auth'), text: 'repository name');
    refused('gh cannot read the PR', (fx) => fx.q('pr-pre', 1, '', exit: 1, stderr: 'not found'), text: 'not found');
    refused('a PR that edits .github/ without the flag (refused BEFORE any sync, push or CI wait)',
        (fx) => fx.q('pr-files', 1, '[{"filename":".github/workflows/test.yml"}]'),
        onlyCalls: ['gh repo', 'gh pr-pre', 'gh pr-files']);
    refused('the PR file list cannot be read', (fx) => fx.q('pr-files', 1, '', exit: 1), text: 'file list');
    refused('the branch is absent on origin while the PR is open', (fx) => fx.cli.repo.must(['push', '-q', 'origin', '--delete', 'feature']),
        text: 'does not exist on origin');
    refused('the remote branch tip is not an ancestor of HEAD (someone else pushed)', (fx) {
      final other = '${fx.cli.repo.root.path}/other_clone';
      runSpawn('git', ['clone', '-q', fx.cli.origin, other],
          why: 'land_pr_e2e: second clone', extraEnv: fx.cli.repo.env, allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
      for (final c in [
        ['config', 'user.email', 'o@e.com'],
        ['config', 'user.name', 'O'],
        ['checkout', '-q', 'feature'],
      ]) {
        fx.cli.repo.must(['-C', other, ...c]);
      }
      File('$other/o.txt').writeAsStringSync('o');
      fx.cli.repo.must(['-C', other, 'add', '-A']);
      fx.cli.repo.must(['-C', other, 'commit', '-q', '-m', 'someone else']);
      fx.cli.repo.must(['-C', other, 'push', '-q', 'origin', 'feature']);
    }, text: 'never force-pushes');

    test('the remote cannot be read (ls-remote fails): refused, nothing changed', () {
      final fx = LandFixture.create();
      fx.cli.repo.must(['remote', 'set-url', 'origin', '${fx.cli.repo.root.path}/no_such_origin.git']);
      final before = fx.cli.snapshot();
      final r = fx.land();
      expectResult(r, 2, 'refused');
      expect(out(r), contains('could not read the remote branch'));
      expect(fx.cli.snapshot(), before);
    });

    test('a hung ls-remote is killed at --fetch-timeout-ms: refused (timed out)', () {
      final fx = LandFixture.create();
      final path = fx.cli.stubPath({'git': 'case "\$*" in *ls-remote*) sleep 8;; esac'});
      final r = runLand(fx, ['191', ...seamArgs(fx), '--fetch-timeout-ms', '400'], path: path);
      expectResult(r, 2, 'refused');
      expect(out(r), contains('timed out'));
    });

    test('an UNTRACKED file is not a refusal (only tracked changes are)', () {
      final fx = LandFixture.create();
      fx.cli.repo.write('scratch.txt', 'untracked\n');
      expectResult(fx.land(), 0, 'merged');
    });

    test('an already MERGED PR from this branch is reported merged and nothing else runs', () {
      final fx = LandFixture.create();
      fx.prPre(1, state: 'MERGED');
      expectResult(fx.land(), 0, 'merged');
      expect(fx.calls, ['gh repo', 'gh pr-pre']);
    });

    test('a local commit that adds a .github/ file is refused in the loop BEFORE the push when the flag is absent', () {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'.github/workflows/x.yml': 'name: x\n'}, msg: 'add a workflow');
      final r = fx.land();
      expectResult(r, 2, 'refused');
      expect(fx.calls, isNot(contains('push')));
      expect(fx.calls, isNot(contains('merge')));
      expect(out(r), contains('.github'));
    });

    test('a path with a space in the repository location works', () {
      final fx = LandFixture.create();
      final dest = '${fx.cli.repo.root.path}/with space';
      Directory(dest).createSync();
      final moved = '$dest/repo';
      Directory(fx.dir).renameSync(moved);
      // the stubs read the fixture repo by absolute path; recreate the link for them
      Link(fx.dir).createSync(moved);
      final r = fx.land(cwd: moved);
      expectResult(r, 0, 'merged');
    });

    test('a bad argument is refused with the usage text', () {
      final fx = LandFixture.create();
      expectResult(runLand(fx, ['abc']), 2, 'refused');
      expectResult(runLand(fx, ['191', '192']), 2, 'refused');
      expectResult(runLand(fx, ['191', '--bogus']), 2, 'refused');
      expectResult(runLand(fx, []), 2, 'refused');
      expectResult(runLand(fx, ['191', '--poll-ms', '0']), 2, 'refused');
    });
  });

  group('the sync is the REAL sync_with_main', () {
    test('a clean divergence is concluded by the real sync (committed), then pushed (stub), CI, gate, merge', () {
      final fx = LandFixture.create();
      final real = '${fx.cli.repo.root.path}/real_scripts';
      Directory(real).createSync();
      final copied = copyScriptClosureFor(fx.cli.srcRoot, real);
      expect(copied, isNotEmpty);
      for (final n in ['sync_with_main.sh', '_dart_bin.sh']) {
        File('${fx.cli.srcRoot}/scripts/$n').copySync('$real/$n');
      }
      for (final n in ['safe_push.sh', 'safe_pr_merge.sh']) {
        File('${fx.scriptsDir}/$n').copySync('$real/$n');
        runSpawn('chmod', ['+x', '$real/$n'], why: 'land_pr_e2e: chmod');
      }
      fx.cli.featureCommit({'lib/f.dart': 'f\n'}, msg: 'own work');
      fx.cli.mainCommit({'lib/m.dart': 'm\n'});
      final r = runLand(fx, ['191', ...seamArgs(fx), '--scripts-dir', real], path: Platform.environment['PATH']);
      expectResult(r, 0, 'merged');
      expect(out(r), contains('sync> result: committed'));
      expect(fx.calls, containsAllInOrder(['push', 'gh check-runs', 'gate', 'merge']));
      expect(fx.cli.repo.must(['ls-remote', 'origin', 'refs/heads/feature']), startsWith(fx.cli.head));
      expect(fx.cli.repo.git(['merge-base', '--is-ancestor', 'refs/remotes/origin/main', 'HEAD']).exitCode, 0);
    });
  });

  group('signals', () {
    Future<(int, String)> startAndTerm(LandFixture fx, String slowFlag, {String? path}) async {
      File('${fx.stub}/$slowFlag').writeAsStringSync('1');
      final p = await startSpawn(dartBin(), [fx.landCli, '191', ...seamArgs(fx)],
          workingDirectory: fx.dir, extraEnv: {...fx.cli.repo.env, 'PATH': ?path}, allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
      final o = StringBuffer();
      final e = StringBuffer();
      final d1 = p.stdout.transform(utf8.decoder).forEach(o.write);
      final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
      final ready = File('${fx.stub}/ready');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!ready.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ready.existsSync(), isTrue, reason: 'the slow stub never started');
      p.kill(ProcessSignal.sigterm);
      final code = await p.exitCode.timeout(const Duration(seconds: 60));
      await Future.wait([d1, d2]);
      reportSpawn(code, o.toString(), e.toString(), 'land_pr after a TERM');
      return (code, o.toString());
    }

    test('TERM during the sync: the running child finishes, no further phase starts, result: error, exit 4', () async {
      final fx = LandFixture.create();
      final (code, text) = await startAndTerm(fx, 'slow_sync');
      expect(code, 4, reason: text);
      expect(lastLine(text), 'result: error');
      expect(RegExp(r'^result: ', multiLine: true).allMatches(text).length, 1);
      expect(text, contains('interrupted'));
      expect(fx.calls.last, 'sync', reason: 'no phase after the sync may start');
    });

    test('TERM during the CI wait (CI never finishes): the loop stops at its next poll, result: error, exit 4, not a CI timeout', () async {
      final fx = LandFixture.create();
      fx.q('check-runs', 1, checkRunsBody({...allGreen(), 'Unit Tests': 'in_progress/-'}));
      final (code, text) = await startAndTerm(fx, 'slow_ci');
      expect(code, 4, reason: text);
      expect(lastLine(text), 'result: error');
      expect(text, contains('interrupted'));
      expect(text, isNot(contains('CI did not finish')));
    });

    test('TERM during a gh read before the replay: no replay and no merge starts, result: error, exit 4', () async {
      final fx = LandFixture.create();
      fx.pre('pr-head', 1, ": > '${fx.stub}/ready'; sleep 2");
      final (code, text) = await startAndTerm(fx, 'unused_flag');
      expect(code, 4, reason: text);
      expect(lastLine(text), 'result: error');
      expect(fx.calls, isNot(contains('merge')));
      expect(fx.calls, isNot(contains('gate')));
    });

    test('TERM during the git reads before the push (the loop ls-remote): no push starts, result: error, exit 4', () async {
      final fx = LandFixture.create();
      fx.cli.featureCommit({'local.txt': 'x\n'}, msg: 'a local commit that would be pushed');
      final path = fx.cli.stubPath({
        'git': 'case "\$*" in *ls-remote*) if [ -f "${fx.stub}/lsr" ]; then : > "${fx.stub}/ready"; sleep 3; else : > "${fx.stub}/lsr"; fi;; esac'
      });
      final (code, text) = await startAndTerm(fx, 'unused_flag', path: path);
      expect(code, 4, reason: text);
      expect(lastLine(text), 'result: error');
      expect(fx.calls, isNot(contains('push')));
    });

    test('TERM during the merge: the PR reads MERGED afterwards, so the result is merged (exit 0)', () async {
      final fx = LandFixture.create();
      final (code, text) = await startAndTerm(fx, 'slow_merge');
      expect(code, 0, reason: text);
      expect(lastLine(text), 'result: merged');
    });

    test('TERM during the merge when the PR is NOT merged afterwards: result: error', () async {
      final fx = LandFixture.create();
      fx.q('pr-state', 1, '{"state":"OPEN"}');
      final (code, text) = await startAndTerm(fx, 'slow_merge');
      expect(code, 4, reason: text);
      expect(lastLine(text), 'result: error');
    });
  });
}

/// The closure of scripts/sync_with_main.dart copied into [dest]/scripts, flattened next to the .sh files.
List<String> copyScriptClosureFor(String srcRoot, String dest) {
  final copied = <String>[];
  final entry = File('$srcRoot/scripts/sync_with_main.dart');
  expect(entry.existsSync(), isTrue);
  final seen = <String>{};
  void visit(String name) {
    if (!seen.add(name)) return;
    final f = File('$srcRoot/scripts/$name');
    f.copySync('$dest/$name');
    copied.add(name);
    for (final m in RegExp(r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(f.readAsStringSync())) {
      final target = m.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) continue;
      visit(target.split('/').last);
    }
  }

  visit('sync_with_main.dart');
  return copied;
}
