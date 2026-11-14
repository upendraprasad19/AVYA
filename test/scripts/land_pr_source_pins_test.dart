// test/scripts/land_pr_source_pins_test.dart
//
// Source pins of landing D (docs/plans/merge-train.md section 5): what the sources must and must not contain. Pins prove PRESENCE only;
// the behaviour is in land_pr_e2e_test.dart, land_pr_replay_test.dart and land_pr_wrapper_e2e_test.dart (rule 21).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/land_pr_lib.dart';

String read(String p) => File(p).readAsStringSync();

/// The source text without comment lines, so a pin cannot be satisfied or tripped by prose.
String code(String p) => read(p).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  final cli = code('scripts/land_pr.dart');
  final sh = read('scripts/land_pr.sh');
  final shCode = sh.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');
  final helper = read('scripts/_dart_bin.sh').split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  group('the wrapper', () {
    test('forwards none of the test seams and only the own arguments of the wrapper (the PR number and the one flag)', () {
      for (final seam in ['--gh', '--scripts-dir', '--poll-ms', '--ci-timeout-ms', '--fetch-timeout-ms', '--gh-timeout-ms', '--record-gate']) {
        expect(shCode.contains(seam), isFalse, reason: seam);
      }
      expect(shCode, contains('run_dart_cli "\$DART_BIN" "\$here/land_pr.dart" "\$@"'));
      // The grammar (`<pr>` first, then `--allow-workflow-change` and/or `--ci-only`, each once) is owned by the
      // wrapper and exercised by land_pr_wrapper_e2e_test.dart; these pin the two flags it knows.
      expect(shCode, contains('--allow-workflow-change) [ "\$seen_wf" = 0 ]'));
      expect(shCode, contains('--ci-only) [ "\$seen_ci" = 0 ]'));
    });
    test('prints result: error only for a status above 7, and exits 4 then', () {
      expect(shCode, contains('if [ "\$rc" -gt 7 ]'));
      expect(shCode, contains('echo "result: error"'));
      expect(RegExp(r'echo "result: ').allMatches(shCode).length, 2, reason: 'refused (the usage path) and error (a status above 7)');
    });
    test('the signal handling matches the sibling wrapper (TERM to the CLI, wait for the real status)', () {
      expect(shCode, isNot(contains('trap ')), reason: 'one signal block, in run_dart_cli (OI-483)');
      expect(helper, contains('trap _dart_cli_on_signal TERM INT HUP'));
      expect(helper.indexOf('trap _dart_cli_on_signal'), lessThan(helper.indexOf('"\$@" &')), reason: 'the trap must be set before the CLI starts');
      expect(helper, contains('if [ "\$_dart_cli_got" = 1 ]; then kill -TERM "\$_dart_cli_child"'));
      expect(helper, contains('while kill -0 "\$_dart_cli_child"'));
      // The bash early-reap path cannot be provoked here (timing inside bash's SIGCHLD handling): pinned by shape, in order.
      final reap = helper.indexOf('if [ "\$_dc_rc" -gt 128 ]; then');
      expect(reap, greaterThan(helper.indexOf('while kill -0 "\$_dart_cli_child"')));
      expect(helper.substring(reap), contains('wait "\$_dart_cli_child" 2>/dev/null'));
      expect(helper.substring(reap), contains('if [ "\$_dc_rc2" -ne 127 ]; then _dc_rc=\$_dc_rc2; fi'));
    });
    test('carries no // Gate: header (it is not a check_*.dart gate)', () {
      for (final p in ['scripts/land_pr.dart', 'scripts/land_pr_lib.dart', 'scripts/land_pr.sh']) {
        expect(RegExp(r'^\s*(//|#)\s*Gate:\s*\d', multiLine: true).hasMatch(read(p)), isFalse, reason: p);
      }
    });
  });

  group('the CLI', () {
    test('main is pinned once per round: the ancestry check, the replay and the stream guards use that sha', () {
      expect(cli, contains("['merge-base', '--is-ancestor', mainSha, 'HEAD']"));
      expect(cli, contains('await _recordGate(head, mainSha);'));
      // our own streams cannot end a run that has a child (the merge) running, and the zone handler waits for it
      expect(cli, contains('unawaited(stdout.done.catchError((_) {}));'));
      expect(cli, contains('while (_childrenRunning > 0'));
    });
    test('OI-451: _out and _err are bare writes; a closed stdout fails asynchronously, so no try/catch there is reachable', () {
      for (final fn in ['_out', '_err']) {
        final m = RegExp('void $fn\\(String line\\) \\{([^}]*)\\}').firstMatch(cli);
        expect(m, isNotNull, reason: '$fn must keep its one-statement body');
        expect(m!.group(1), isNot(contains('try')));
        expect(m.group(1), isNot(contains('catch')));
      }
    });
    test("the replay hands the gate the MAIN sha as PUSH_BEFORE (CI's range base; the head would give the same first-parent walk, so only this pin holds it)", () {
      expect(cli, contains("'PUSH_BEFORE': mainSha,"));
      expect(cli, isNot(contains("'PUSH_BEFORE': head")));
    });
    test('runs no raw git commit, push or merge and no gh pr merge (the wrappers do)', () {
      for (final w in ['commit', 'push', 'merge']) {
        expect(RegExp('(_git|sg)\\(\\s*\\[\\s*[\'"]$w[\'"]').hasMatch(cli), isFalse, reason: "git $w argv");
      }
      expect(RegExp(r"_git\(\s*\[\s*'merge-base'").hasMatch(cli), isTrue, reason: 'the ancestor checks use merge-base (allowed)');
      expect(cli.contains("'pr', 'merge'"), isFalse);
      expect(cli.contains('pr merge'), isFalse);
      expect(cli, contains("'\$_scriptsDir/safe_push.sh'"));
      expect(cli, contains("'\$_scriptsDir/safe_pr_merge.sh'"));
      expect(cli, contains("'\$_scriptsDir/sync_with_main.sh', '--commit'"));
    });
    test('prints a line starting with result: in exactly one place', () {
      expect(RegExp(r"writeln\('result:").allMatches(cli).length, 1);
      expect(RegExp(r"_say\('result:").hasMatch(cli), isFalse);
    });
    test('reads no environment variable and never drops the parent environment', () {
      expect(cli.contains('Platform.environment'), isFalse);
      expect(cli.contains('includeParentEnvironment'), isFalse);
    });
    test('closes the stdin of every child and passes GIT_TERMINAL_PROMPT=0 to git', () {
      expect(cli, contains('p.stdin.close()'));
      expect(cli, contains("'GIT_TERMINAL_PROMPT': '0'"));
    });
    test('uses explicit refspecs for the fetches', () {
      expect(cli, contains("'+refs/heads/\$branch:refs/remotes/origin/\$branch'"));
      expect(cli, contains("'+refs/heads/main:refs/remotes/origin/main'"));
    });
    test('the replay commit is built from HEAD\'s tree with the parents main then head and never uses --warn-only', () {
      expect(cli, contains("'commit-tree', '\$head^{tree}', '-p', mainSha, '-p', head"));
      expect(cli.contains('warn-only'), isFalse);
      expect(cli, contains("'GITHUB_EVENT_PATH': ''"));
      expect(cli, contains("'GIT_DIR': '\$dir/.git'"));
    });
    test('the record gate and the CI classifier come from the libraries (the single judge)', () {
      expect(cli, contains('classifyCheckRuns('));
      expect(cli, contains('replayVerdict('));
      expect(cli, contains('mergeOutcome('));
    });
    test('imports protectedBranchReason from retire_worktree_lib (the same predicate as the sync)', () {
      expect(cli, contains("import 'retire_worktree_lib.dart' show protectedBranchReason;"));
    });
  });

  group('the C2 and merge wrapper contracts the library assumes', () {
    test('every word the sync CLI prints is in syncResultWords, and nothing else', () {
      final header = read('scripts/sync_with_main.dart');
      final m = RegExp(r'`result: <([a-z|\-]+)>`').firstMatch(header);
      expect(m, isNotNull, reason: 'the header line naming the result words moved');
      expect(m!.group(1)!.split('|').toSet(), syncResultWords.toSet());
    });
    test('every sync word is mapped to a decision (an unknown word is an error, never "continue")', () {
      const expected = <String, SyncNext>{
        'ready': SyncNext.needsHuman,
        'pending': SyncNext.needsHuman,
        'committed': SyncNext.proceed,
        'fast-forwarded': SyncNext.proceed,
        'up-to-date': SyncNext.proceed,
        'refused': SyncNext.refused,
        'commit-failed': SyncNext.needsHuman,
        'error': SyncNext.error,
      };
      expect(expected.keys.toSet(), syncResultWords.toSet(), reason: 'a new sync word needs a decision here');
      expected.forEach((w, d) => expect(syncNext(w), d, reason: w));
      expect(syncNext('made-up'), SyncNext.error);
    });
    test('safe_pr_merge still says: exit 1 refused, exit 2 usage or unverified (pinned by content)', () {
      final src = read('scripts/safe_pr_merge.dart');
      expect(src, contains('1 refused / could'));
      expect(src, contains('2 usage error, or `gh pr merge` exited 0 but the PR is not MERGED'));
      expect(src, contains('UNVERIFIED'));
      expect(RegExp(r'return 2;').hasMatch(src), isTrue);
    });
    test('evaluateCheckRuns still has no side effect on its callers: classifyCheckRuns reads the same pass', () {
      final lib2 = code('scripts/safe_pr_merge_lib.dart');
      expect(lib2, contains('final j = _judgeCheckRuns(runs);'));
      expect(RegExp(r'_judgeCheckRuns\(').allMatches(lib2).length, 3, reason: 'the definition and its two readers');
    });
  });

  group('the exit table is written the same everywhere', () {
    final words = exitCodeByWord.keys.toList();
    // A bare contains(word) is satisfied by any prose ("error", "merged"): pin the CODE-AND-WORD pairs of the tables instead.
    test('the plan table (section 3.1) has one row per code and word', () {
      final text = read('docs/plans/merge-train.md');
      exitCodeByWord.forEach((w, c) {
        // the table shares row 3 between ci-failed and ci-timeout
        final row = c == 3 ? '| 3 | `ci-failed` / `ci-timeout` |' : '| $c | `$w` |';
        expect(text, contains(row), reason: 'the plan table lacks "$row"');
      });
    });
    test('the wrapper and the CLI headers state the codes 0 to 7 in the same order', () {
      final wrapper = read('scripts/land_pr.sh');
      final cliHeader = read('scripts/land_pr.dart');
      for (final t in ['0 merged', '1 needs-human', '2 refused', '3 ci-failed', '4 error', '5 record-failed', '6 merge-refused', '7 merge-unverified']) {
        expect(wrapper, contains(t), reason: t);
        expect(cliHeader, contains(t), reason: t);
      }
    });
    test('hooks.md documents the command with the same code-and-word pairs, inside its own section', () {
      final hooks = read('docs/architecture/hooks.md');
      final i = hooks.indexOf('### Landing a PR');
      expect(i, greaterThan(-1), reason: 'hooks.md has no "### Landing a PR" section');
      final next = hooks.indexOf('\n## ', i);
      final section = hooks.substring(i, next == -1 ? hooks.length : next);
      for (final w in words) {
        expect(section, contains('`$w`'), reason: 'hooks.md lacks "`$w`" in the section');
      }
      for (final t in ['0 `merged`', '1 `needs-human`', '2 `refused`', '3 `ci-failed`', '4 `error`', '5 `record-failed`', '6 `merge-refused`', '7 `merge-unverified`']) {
        expect(section, contains(t), reason: 'hooks.md lacks "$t"');
      }
    });
  });
}
