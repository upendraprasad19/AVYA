@Timeout(Duration(minutes: 12))
library;

// test/scripts/sync_with_main_e2e_test.dart
//
// scripts/sync_with_main.dart against REAL git in throwaway repositories (landing C2, docs/plans/sync-resolver.md
// section 5, rows E1-E7, E9, E10, E12). Resume/safety is sync_with_main_state_e2e_test.dart, the wrapper and the
// config variants sync_with_main_wrapper_e2e_test.dart.
//
// Rule 21: every scenario asserts the exit code AND the `result:` protocol (one `result:` line, and it is the
// last), then the repository state (what is unmerged, what is staged, what is byte for byte untouched).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';
import '../helpers/sync_resolver_fixtures.dart';

const String kOpenIssues = 'docs/audit/open_issues.md';
const String kBugClasses = '.claude/skills/debugging/bug-classes.md';
const String kLedger = 'docs/audit/gate_test_ledger.yaml';
const String kGateIndex = 'docs/audit/GATE_INDEX.md';
const String kMsg = "Merge remote-tracking branch 'origin/main' into feature";

/// Counts the conflict blocks in [text].
int blocks(String text) => RegExp('^$kOpen', multiLine: true).allMatches(text).length;

/// A `scripts/safe_commit.sh` stand-in: records the message it was given and commits.
void writeCommitStub(SyncCli c, {bool noVerify = false}) {
  c.repo.write(
    'scripts/safe_commit.sh',
    '#!/bin/sh\nprintf "%s" "\$1" > "\$(git rev-parse --git-dir)/stub_commit_msg"\n'
        'exec git commit -q ${noVerify ? '--no-verify ' : ''}-m "\$1"\n',
  );
}

String stubMessage(SyncCli c) => File('${c.gitDir}/stub_commit_msg').readAsStringSync();

/// A scenario with both branches appending to the OI board (resolvable).
SyncCli oiScenario() {
  final c = SyncCli.create();
  c.featureCommit({kOpenIssues: board([oi(1), oi(2), oi(3)])});
  c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
  return c;
}

/// A scenario whose merge is clean (disjoint files).
SyncCli cleanScenario() {
  final c = SyncCli.create();
  c.featureCommit({'README.md': 'feature readme\n'});
  c.mainCommit({'lib/a.dart': 'line1\nmain edit\nline3\n'});
  return c;
}

List<String> parentsOf(SyncCli c, String rev) => c.repo.must(['rev-list', '--parents', '-n', '1', rev]).split(' ');

void main() {
  group('E1 / E2 / E3 / E4: what is resolved, what is left', () {
    test('E1 both branches append an OI: resolved, staged, not committed, main first', () {
      final c = oiScenario();
      final head = c.head;
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.unmerged(), isEmpty);
      expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), oi(3)]));
      expect(c.hasMarkers(kOpenIssues), isFalse);
      expect(c.staged(), contains(kOpenIssues));
      expect(c.mergePending, isTrue);
      expect(c.head, head, reason: 'the tool does not commit without --commit');
      expect(stdoutOf(r), contains(RegExp(r'resolved\s+docs/audit/open_issues\.md')));
      expect(stdoutOf(r), contains('sh scripts/safe_commit.sh "$kMsg"'));
    });

    test('E2 both added bug class 2.2 with different text: markers around THAT record only, neighbours resolved', () {
      final c = SyncCli.create();
      final b = '# Bug classes\n\n${bugClass('2.1')}';
      c.featureCommit({kBugClasses: '$b${bugClass('2.2', body: 'ours text')}${bugClass('2.3')}'});
      c.mainCommit({kBugClasses: '$b${bugClass('2.2', body: 'theirs text')}${bugClass('2.4')}'});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      final out = c.read(kBugClasses);
      expect(blocks(out), 1);
      expect(out, contains('$kBaseMark base\n'), reason: 'the text merge is diff3');
      expect(c.unmerged(), [kBugClasses]);
      expect(c.stagesOf(kBugClasses), [1, 2, 3]);
      expect(c.mergePending, isTrue);
      final outside = out.substring(0, out.indexOf(kOpen)) + out.substring(out.indexOf('$kClose origin/main\n') + '$kClose origin/main\n'.length);
      expect(outside, '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.4')}${bugClass('2.3')}');
      expect(stdoutOf(r), contains(RegExp(r'partial\s+\.claude/skills/debugging/bug-classes\.md\s+markers kept for: 2\.2')));
      expect(stdoutOf(r), contains('sh scripts/safe_commit.sh "$kMsg"'));
    });

    test('E3 one resolvable and one other conflicting file: the first is staged, the second is byte-identical to git\'s', () {
      final c = SyncCli.create();
      c.featureCommit({kOpenIssues: board([oi(1), oi(2), oi(3)]), 'lib/a.dart': 'line1\nours\nline3\n'});
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)]), 'lib/a.dart': 'line1\ntheirs\nline3\n'});
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes('lib/a.dart');
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), ['lib/a.dart']);
      expect(c.readBytes('lib/a.dart'), gits);
      expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), oi(3)]));
      expect(stdoutOf(r), contains(RegExp(r'left\s+lib/a\.dart\s+not on the resolvable list')));
    });

    test('E4 the frozen archive and a tracked pre-A2 local index (modify/delete) are left exactly as git wrote them', () {
      final files = defaultFiles()..['docs/audit/OPEN_INDEX.md'] = 'index\n';
      final c = SyncCli.create(files: files);
      c.featureCommit({
        '.claude/skills/code-review/tuning-history.md': '# archive\n\nentry a\nours entry\n',
        'docs/audit/OPEN_INDEX.md': 'index edited on the branch\n',
      });
      c.mainCommit({
        '.claude/skills/code-review/tuning-history.md': '# archive\n\nentry a\ntheirs entry\n',
        'docs/audit/OPEN_INDEX.md': null,
      });
      expect(c.handMerge().exitCode, 1);
      final archive = c.readBytes('.claude/skills/code-review/tuning-history.md');
      final index = c.readBytes('docs/audit/OPEN_INDEX.md');
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes('.claude/skills/code-review/tuning-history.md'), archive);
      expect(c.readBytes('docs/audit/OPEN_INDEX.md'), index);
      expect(c.unmerged(), ['.claude/skills/code-review/tuning-history.md', 'docs/audit/OPEN_INDEX.md']);
      expect(stdoutOf(r), contains(RegExp(r'left\s+\.claude/skills/code-review/tuning-history\.md')));
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/OPEN_INDEX\.md')));
    });
  });

  group('E1b records merged by line, and merges the checks reject', () {
    test('two edits to ONE record that git merges by line: staged, reported as merged-by-line with the record named', () {
      final c = SyncCli.create();
      final b = board([oi(1, body: '- **Status**: OPEN\n- **Tag**: a\n- **Note**: n\n- **Last**: z'), oi(2)]);
      c.repo.write(kOpenIssues, b);
      c.repo.commitAll('wider base');
      c.repo.checkout('main');
      c.repo.must(['merge', '-q', '--ff-only', 'feature']);
      c.repo.must(['push', '-q', 'origin', 'main']);
      c.repo.checkout('feature');
      c.featureCommit({kOpenIssues: board([oi(1, body: '- **Status**: OPEN\n- **Tag**: ours\n- **Note**: n\n- **Last**: z'), oi(2), oi(3)])});
      c.mainCommit({kOpenIssues: board([oi(1, body: '- **Status**: OPEN\n- **Tag**: a\n- **Note**: n\n- **Last**: theirs'), oi(2), oi(4)])});
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.read(kOpenIssues), board([oi(1, body: '- **Status**: OPEN\n- **Tag**: ours\n- **Note**: n\n- **Last**: theirs'), oi(2), oi(4), oi(3)]));
      expect(stdoutOf(r), contains(RegExp(r'merged-by-line\s+docs/audit/open_issues\.md\s+staged; read these records: OI-1')));
      expect(stdoutOf(r), contains('merged by line - two edits to ONE record'));
    });

    test('a merge whose checks fail is left exactly as git wrote it and not staged', () {
      final c = SyncCli.create();
      // the same record added at DIFFERENT places (git keeps both copies outside its one conflict hunk) plus a conflict at the end
      c.featureCommit({kOpenIssues: board([oi(9), oi(1), oi(2), oi(5, title: 'ours')])});
      c.mainCommit({kOpenIssues: board([oi(1), oi(9), oi(2), oi(5, title: 'theirs')])});
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kOpenIssues);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kOpenIssues), gits);
      expect(c.unmerged(), [kOpenIssues]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+check V-[abc]')));
    });

    test('the state directory cannot be created: every allow-listed path is left with that reason', () {
      final c = oiScenario();
      File('${c.gitDir}/sync_with_main').writeAsStringSync('a file where the state directory should be');
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+the state directory')));
      expect(c.hasMarkers(kOpenIssues), isTrue);
    });

    test('a stage that cannot be read is left with that reason', () {
      final c = oiScenario();
      expect(c.handMerge().exitCode, 1);
      final path = c.stubPath({'git': 'if [ "\$1" = cat-file ]; then echo "fatal: no such object" >&2; exit 1; fi'});
      final r = c.run([], path: path);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+could not read stage 1')));
    });
  });

  group('E5 the generated gate index', () {
    const builder = "import 'dart:io';\nvoid main() {\n  File('builder_ran').writeAsStringSync('x');\n  File('docs/audit/GATE_INDEX.md').writeAsStringSync('regenerated\\n');\n}\n";
    const failing = "import 'dart:io';\nvoid main() {\n  File('docs/audit/GATE_INDEX.md').writeAsStringSync('half written\\n');\n  exit(1);\n}\n";

    SyncCli gateScenario({bool alsoCode = false}) {
      final c = SyncCli.create();
      c.featureCommit({kGateIndex: 'index feature\n', if (alsoCode) 'lib/a.dart': 'line1\nours\nline3\n'});
      c.mainCommit({kGateIndex: 'index main\n', if (alsoCode) 'lib/a.dart': 'line1\ntheirs\nline3\n'});
      return c;
    }

    test('GATE_INDEX.md alone unmerged: the builder runs with the CLI\'s own Dart (no dart on PATH) and the file is staged', () {
      final c = gateScenario();
      c.repo.write('scripts/build_gate_index.dart', builder);
      final r = c.run([], path: c.minimalPath(['git', 'sh']));
      expectResult(r, 0, 'ready');
      expect(c.unmerged(), isEmpty);
      expect(c.read(kGateIndex), 'regenerated\n');
      expect(File('${c.dir}/builder_ran').existsSync(), isTrue);
      expect(stdoutOf(r), contains(RegExp(r'resolved\s+docs/audit/GATE_INDEX\.md\s+regenerated')));
      expect(stdoutOf(r), isNot(contains(RegExp(r'left\s+docs/audit/GATE_INDEX'))), reason: 'the earlier left line is replaced by the resolved one');
    });

    test('a failing builder restores git\'s conflicted file', () {
      final c = gateScenario();
      c.repo.write('scripts/build_gate_index.dart', failing);
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kGateIndex);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kGateIndex), gits);
      expect(c.hasMarkers(kGateIndex), isTrue);
      expect(c.unmerged(), [kGateIndex]);
      expect(stdoutOf(r), contains('the builder failed'));
    });

    test('a builder that exits 0 but leaves a marker line behind is treated as failed', () {
      final c = gateScenario();
      c.repo.write('scripts/build_gate_index.dart', "import 'dart:io';\nvoid main() {\n  File('docs/audit/GATE_INDEX.md').writeAsStringSync('${'<' * 7} still conflicted\\n');\n}\n");
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kGateIndex);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kGateIndex), gits);
      expect(stdoutOf(r), contains('the builder failed'));
    });

    test('GATE_INDEX.md plus another unmerged path: the builder does not run', () {
      final c = gateScenario(alsoCode: true);
      c.repo.write('scripts/build_gate_index.dart', builder);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(File('${c.dir}/builder_ran').existsSync(), isFalse);
      expect(c.unmerged(), [kGateIndex, 'lib/a.dart']);
      expect(c.hasMarkers(kGateIndex), isTrue);
    });

    test('a missing builder is reported, not invented', () {
      final c = gateScenario();
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kGateIndex]);
      expect(stdoutOf(r), contains('build_gate_index.dart'));
    });
  });

  group('E6 --commit, and the merges it may and may not conclude', () {
    test('a fresh start clears a stale state directory (identity and written/) but not the backups', () {
      final c = cleanScenario();
      final state = Directory('${c.gitDir}/sync_with_main')..createSync();
      File('${state.path}/identity').writeAsStringSync('stale\n');
      Directory('${state.path}/written/docs').createSync(recursive: true);
      File('${state.path}/written/docs/x.md').writeAsStringSync('stale');
      final backups = Directory('${c.gitDir}/sync_with_main_backup/old-1')..createSync(recursive: true);
      File('${backups.path}/keep.md').writeAsStringSync('keep');
      expectResult(c.run([]), 0, 'ready');
      expect(File('${state.path}/identity').existsSync(), isFalse);
      expect(Directory('${state.path}/written').existsSync(), isFalse);
      expect(File('${backups.path}/keep.md').existsSync(), isTrue);
    });

    test('the fetch does not follow tags and does not read stdin', () {
      final c = cleanScenario();
      c.repo.must(['tag', '-a', 'v1', '-m', 'v1', 'main']);
      c.repo.must(['push', '-q', 'origin', 'v1']);
      c.repo.must(['tag', '-d', 'v1']);
      final path = c.stubPath({'git': 'if [ "\$1" = fetch ]; then read line; fi'});
      expectResult(c.run([], path: path), 0, 'ready');
      expect(c.repo.must(['tag', '-l']), isEmpty, reason: '--no-tags: the tag on the fetched tip was not followed');
    });

    test('a clean merge: exit 0, staged, result ready; the tool does not commit', () {
      final c = cleanScenario();
      final head = c.head;
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.head, head);
      expect(c.mergePending, isTrue);
      expect(c.unmerged(), isEmpty);
      expect(c.staged(), contains('lib/a.dart'));
    });

    test('a clean merge with --commit is concluded by git itself: one merge commit, HEAD^2 is the tip', () {
      final c = cleanScenario();
      final old = c.head;
      final r = c.run(['--commit']);
      expectResult(r, 0, 'committed');
      final p = parentsOf(c, 'HEAD');
      expect(p, hasLength(3));
      expect(p[1], old);
      expect(p[2], c.tip);
      expect(c.repo.must(['log', '-1', '--format=%s']), kMsg);
      expect(c.mergePending, isFalse);
    });

    test('a clean --commit merge whose pre-merge-commit hook fails falls back to safe_commit.sh (control flow only)', () {
      final c = cleanScenario();
      writeCommitStub(c, noVerify: true);
      File('${c.gitDir}/hooks/pre-merge-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho hook says no >&2\nexit 1\n');
      runSpawn('chmod', ['+x', '${c.gitDir}/hooks/pre-merge-commit'], why: 'chmod hook');
      final old = c.head;
      final r = c.run(['--commit']);
      expectResult(r, 0, 'committed');
      expect(File('${c.gitDir}/stub_commit_msg').existsSync(), isTrue, reason: 'git left the merge pending and the stub concluded it');
      expect(stubMessage(c), kMsg);
      final p = parentsOf(c, 'HEAD');
      expect(p[1], old);
      expect(p[2], c.tip);
    });

    test('a conflicted merge with --commit: the ledger is resolved and safe_commit.sh concludes it', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
      writeCommitStub(c);
      final old = c.head;
      final r = c.run(['--commit']);
      expectResult(r, 0, 'committed');
      expect(stubMessage(c), kMsg);
      final p = parentsOf(c, 'HEAD');
      expect(p[1], old);
      expect(p[2], c.tip);
      expect(c.repo.must(['show', 'HEAD:$kLedger']), '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}${ledgerRec('check_o')}'.trimRight());
    });

    test('--commit prunes the backup directories too (22 planted + the new one leave 20)', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
      writeCommitStub(c);
      final root = '${c.gitDir}/sync_with_main_backup';
      for (var i = 1; i <= 22; i++) {
        final d = Directory('$root/old-$i')..createSync(recursive: true);
        File('${d.path}/f.md').writeAsStringSync('$i');
        runSpawn('touch', ['-d', '2020-01-${i.toString().padLeft(2, '0')}', d.path], why: 'age the planted run directory');
      }
      expectResult(c.run(['--commit']), 0, 'committed');
      expect(Directory(root).listSync().whereType<Directory>(), hasLength(20));
    });

    test('the commit\'s own hook failing is exit 3 with the merge still pending and staged', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
      writeCommitStub(c);
      for (final hook in ['pre-commit', 'pre-merge-commit']) {
        File('${c.gitDir}/hooks/$hook')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\necho the gate says no >&2\nexit 1\n');
        runSpawn('chmod', ['+x', '${c.gitDir}/hooks/$hook'], why: 'chmod hook');
      }
      final head = c.head;
      final r = c.run(['--commit']);
      expectResult(r, 3, 'commit-failed');
      expect(c.head, head);
      expect(c.mergePending, isTrue);
      expect(c.unmerged(), isEmpty);
      expect(c.staged(), contains(kLedger));
    });

    test('--commit with no scripts/safe_commit.sh in the tree is exit 3 with the merge pending and staged', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
      final r = c.run(['--commit']);
      expectResult(r, 3, 'commit-failed');
      expect(stdoutOf(r), contains('scripts/safe_commit.sh is missing'));
      expect(c.mergePending, isTrue);
      expect(c.staged(), contains(kLedger));
    });

    test('a merge commit whose second parent is NOT the tip is not reported as committed', () {
      final c = cleanScenario();
      final git = whichTool('git');
      c.repo.must(['checkout', '-q', '-b', 'elsewhere', 'main']);
      c.repo.write('elsewhere.txt', 'x\n');
      c.repo.commitAll('elsewhere');
      c.repo.checkout('feature');
      final path = c.stubPath({'git': 'if [ "\$1" = merge ]; then "$git" merge --no-ff --no-edit -m other elsewhere; exit 0; fi'});
      final r = c.run(['--commit'], path: path);
      expectResult(r, 4, 'error');
      expect(stdoutOf(r), contains('git stopped in an unexpected state'));
    });

    test('a merge commit whose FIRST parent is not the old HEAD is not reported as committed, even when its second parent is the tip', () {
      final c = cleanScenario();
      final git = whichTool('git');
      c.repo.must(['checkout', '-q', '-b', 'elsewhere', 'main']);
      c.repo.write('elsewhere.txt', 'x\n');
      final elsewhere = c.repo.commitAll('elsewhere');
      c.repo.checkout('feature');
      final path = c.stubPath({
        'git': 'if [ "\$1" = merge ]; then\n'
            '  new=\$("$git" commit-tree "\$("$git" rev-parse HEAD^{tree})" -p $elsewhere -p ${c.tip} -m forged)\n'
            '  "$git" update-ref HEAD "\$new"\n'
            '  exit 0\n'
            'fi',
      });
      final r = c.run(['--commit'], path: path);
      expectResult(r, 4, 'error');
      expect(stdoutOf(r), contains('git stopped in an unexpected state'));
      expect(stdoutOf(r), isNot(contains('git concluded the merge')));
    });

    test('--commit on a merge the CALLER started is refused and changes nothing', () {
      final c = oiScenario();
      expect(c.handMerge().exitCode, 1);
      final snap = c.snapshot();
      final r = c.run(['--commit']);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('safe_commit.sh'));
      expect(c.snapshot(), snap);
    });

    test('--commit on a merge the tool started in an EARLIER run is refused too', () {
      final c = SyncCli.create();
      c.featureCommit({kBugClasses: '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'ours')}'});
      c.mainCommit({kBugClasses: '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'theirs')}'});
      expectResult(c.run([]), 1, 'pending');
      final snap = c.snapshot();
      final r = c.run(['--commit']);
      expectResult(r, 2, 'refused');
      expect(c.snapshot(), snap);
    });

    test('the tip moves between the fetch and the merge: the merge uses the SHA recorded after the fetch', () {
      final c = cleanScenario();
      final git = whichTool('git');
      final recorded = c.tip;
      c.repo.must(['checkout', '-q', '-b', 'elsewhere', 'main']);
      c.repo.write('elsewhere.txt', 'x\n');
      final elsewhere = c.repo.commitAll('elsewhere');
      c.repo.checkout('feature');
      final path = c.stubPath({'git': 'if [ "\$1" = merge ]; then "$git" update-ref refs/remotes/origin/main $elsewhere; fi'});
      final r = c.run(['--commit'], path: path);
      expectResult(r, 0, 'committed');
      expect(parentsOf(c, 'HEAD')[2], recorded);
      expect(c.tip, elsewhere, reason: 'the stub did move the ref after the tool resolved it');
    });
  });

  group('E7 refusals change nothing', () {
    void refusal(String name, void Function(SyncCli c) setup, String reason, {List<String> args = const [], String? cwd}) {
      test(name, () {
        final c = cleanScenario();
        setup(c);
        final snap = c.snapshot();
        final r = c.run(args, cwd: cwd?.replaceAll('{root}', c.repo.root.path));
        expectResult(r, 2, 'refused');
        expect(stdoutOf(r), contains(reason));
        expect(c.snapshot(), snap);
      });
    }

    void onBranch(String branch) => refusal('on $branch', (c) => c.repo.must(['checkout', '-q', '-b', branch]), 'protected', args: const []);

    onBranch('develop');
    onBranch('rescue/x');
    onBranch('oi/x');
    onBranch('dependabot/x');
    refusal('on main', (c) => c.repo.checkout('main'), 'protected branch name');
    refusal('detached HEAD', (c) => c.repo.must(['checkout', '-q', '--detach']), 'HEAD is detached; check out a branch first');
    refusal('not inside a work tree', (c) {}, 'not inside a git work tree', cwd: '{root}');
    refusal('staged-only changes', (c) {
      c.repo.write('README.md', 'staged\n');
      c.repo.stage(['README.md']);
    }, 'modified or staged');
    refusal('a modified tracked file', (c) => c.repo.write('README.md', 'modified\n'), 'modified or staged');
    refusal('an octopus MERGE_HEAD', (c) {
      expect(c.handMerge().exitCode, 0);
      final mh = File('${c.gitDir}/MERGE_HEAD');
      mh.writeAsStringSync('${mh.readAsStringSync()}${c.head}\n');
    }, 'octopus');
    refusal('a pending merge that is not of origin/main', (c) {
      c.repo.must(['checkout', '-q', '-b', 'other', 'main~1']);
      c.repo.write('other.txt', 'x\n');
      c.repo.commitAll('other');
      c.repo.checkout('feature');
      expect(c.repo.git(['merge', '--no-commit', '--no-ff', 'other']).exitCode, 0);
    }, 'is not of origin/main');
    refusal('unmerged entries with no merge', (c) {
      c.featureCommit({'lib/a.dart': 'line1\nours\nline3\n'});
      c.mainCommit({'lib/a.dart': 'line1\ntheirs\nline3\n'});
      expect(c.handMerge().exitCode, 1);
      File('${c.gitDir}/MERGE_HEAD').deleteSync();
    }, 'no merge in progress');
    refusal('a fetch that fails', (c) => c.repo.must(['remote', 'set-url', 'origin', '${c.repo.root.path}/does-not-exist']), 'git fetch failed');
    refusal('no origin/main (with --no-fetch)', (c) => c.repo.must(['update-ref', '-d', 'refs/remotes/origin/main']), 'missing or not a commit', args: const ['--no-fetch']);
    refusal('a rebase in progress', (c) => Directory('${c.gitDir}/rebase-merge').createSync(), 'in progress');
    refusal('a multi-commit cherry-pick sequence in progress', (c) => Directory('${c.gitDir}/sequencer').createSync(), 'in progress');
    refusal('an am in progress', (c) => Directory('${c.gitDir}/rebase-apply').createSync(), 'in progress');
    refusal('a cherry-pick in progress', (c) => File('${c.gitDir}/CHERRY_PICK_HEAD').writeAsStringSync('${c.head}\n'), 'in progress');
    refusal('a revert in progress', (c) => File('${c.gitDir}/REVERT_HEAD').writeAsStringSync('${c.head}\n'), 'in progress');
    refusal('a bisect in progress', (c) => File('${c.gitDir}/BISECT_LOG').writeAsStringSync('git bisect start\n'), 'in progress');
    refusal('an unknown argument', (c) {}, 'unknown argument "--force"', args: const ['--force']);
    test('an unborn HEAD is refused and nothing changes (the shared snapshot cannot read HEAD, so a status snapshot is compared)', () {
      final c = cleanScenario();
      c.repo.must(['update-ref', '-d', 'refs/heads/feature']);
      String snap() => '${c.repo.git(['status', '--porcelain=v1']).stdout}|${c.mergePending}';
      final before = snap();
      final r = c.run([]);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('HEAD is not a commit'));
      expect(snap(), before);
    });
    for (final bad in const ['abc', '0', '-5', '']) {
      refusal('a bad fetch timeout "$bad"', (c) {}, 'bad value in --fetch-timeout-ms=$bad', args: ['--fetch-timeout-ms=$bad']);
    }

    test('a shallow repository', () {
      final c = cleanScenario();
      final shallow = '${c.repo.root.path}/shallow';
      final clone = c.repo.git(['clone', '-q', '--depth', '1', '-b', 'main', 'file://${c.origin}', shallow]);
      expect(clone.exitCode, 0, reason: '${clone.stderr}');
      c.repo.git(['checkout', '-q', '-b', 'feature2'], cwd: shallow);
      final r = c.run([], cwd: shallow);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('shallow'));
    });

    test('a fetch that hangs is killed (the b2f7e4 pattern) and its child sees GIT_TERMINAL_PROMPT=0, HOME and PATH', () {
      final c = cleanScenario();
      final pidFile = '${c.repo.root.path}/fetch.pid';
      final envFile = '${c.repo.root.path}/fetch.env';
      final path = c.stubPath({
        'git': 'if [ "\$1" = fetch ]; then echo \$\$ > $pidFile; echo "prompt=\$GIT_TERMINAL_PROMPT home=\$HOME path=\$PATH" > $envFile; exec sleep 300; fi',
      });
      final snap = c.snapshot();
      final r = c.run(['--fetch-timeout-ms=1500'], path: path);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('timed out'));
      final pid = File(pidFile).readAsStringSync().trim();
      final alive = runSpawn('sh', ['-c', 'kill -0 $pid'], why: 'is the hung fetch still alive?');
      expect(alive.exitCode, isNot(0), reason: 'the fetch child must be dead after the CLI exits');
      final env = File(envFile).readAsStringSync();
      expect(env, contains('prompt=0'));
      expect(env, matches(RegExp(r'home=\S+')));
      expect(env, contains('path=${c.repo.root.path}/stubbin'));
      expect(c.snapshot(), snap);
    });

    test('a merge git refuses to start (an untracked file in the way) is exit 2 with git\'s text', () {
      final c = SyncCli.create();
      c.featureCommit({'README.md': 'feature\n'});
      c.mainCommit({'lib/new.dart': 'from main\n'});
      c.repo.write('lib/new.dart', 'untracked on the branch\n');
      final snap = c.snapshot();
      final r = c.run([]);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('overwritten'));
      expect(c.snapshot(), snap);
      expect(c.read('lib/new.dart'), 'untracked on the branch\n');
    });

    test('a git that fails after the index was written is exit 4 and names the undo without running it', () {
      final c = cleanScenario();
      final git = whichTool('git');
      final old = c.head;
      final path = c.stubPath({
        'git': 'if [ "\$1" = merge ]; then "$git" "\$@"; rm -f "\$("$git" rev-parse --git-dir)/MERGE_HEAD"; exit 1; fi',
      });
      final r = c.run([], path: path);
      expectResult(r, 4, 'error');
      expect(stdoutOf(r), contains('git reset --hard $old'));
      expect(c.head, old, reason: 'the undo is named, never run');
    });

    test('a git that returns junk for ls-files -u once the merge started is exit 4, one result line, merge pending', () {
      final c = oiScenario();
      final path = c.stubPath({
        'git': 'if [ "\$1" = ls-files ] && [ -f "${c.gitDir}/MERGE_HEAD" ]; then echo garbage; exit 0; fi',
      });
      final r = c.run([], path: path);
      expectResult(r, 4, 'error');
      expect(c.mergePending, isTrue);
    });

    test('up to date: exit 0 and nothing changed', () {
      final c = cleanScenario();
      c.repo.must(['merge', '-q', '--no-edit', 'refs/remotes/origin/main']);
      final snap = c.snapshot();
      final r = c.run([]);
      expectResult(r, 0, 'up-to-date');
      expect(c.snapshot(), snap);
    });

    test('a branch with no commit of its own is fast-forwarded and the old and new HEAD are printed', () {
      final c = SyncCli.create();
      final old = c.head;
      c.mainCommit({'lib/a.dart': 'line1\nmain edit\nline3\n'});
      final r = c.run([]);
      expectResult(r, 0, 'fast-forwarded');
      expect(c.head, c.tip);
      expect(stdoutOf(r), contains(old));
      expect(stdoutOf(r), contains(old.substring(0, 8)));
      expect(c.mergePending, isFalse);
    });

    test('a failing --ff-only is exit 2 with git\'s text', () {
      final c = SyncCli.create();
      c.mainCommit({'lib/new.dart': 'from main\n'});
      c.repo.write('lib/new.dart', 'untracked on the branch\n');
      final snap = c.snapshot();
      final r = c.run([]);
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('--ff-only'));
      expect(c.snapshot(), snap);
    });

    test('a hand-started --no-ff merge on a branch with no commit of its own is resumed, not fast-forwarded', () {
      final c = SyncCli.create();
      final old = c.head;
      c.mainCommit({'lib/a.dart': 'line1\nmain edit\nline3\n'});
      expect(c.handMerge().exitCode, 0);
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.head, old);
      expect(c.mergePending, isTrue);
    });
  });

  group('E9 paths the tool must leave to a human', () {
    test('a symlink on both sides (changed to different targets): mode 120000 is not resolved', () {
      final c = SyncCli.create();
      void relink(String target) {
        final f = File('${c.dir}/$kOpenIssues');
        if (FileSystemEntity.typeSync(f.path, followLinks: false) != FileSystemEntityType.notFound) f.deleteSync();
        Link(f.path).createSync(target);
      }

      c.repo.checkout('main');
      relink('../../README.md');
      c.repo.commitAll('open_issues becomes a link');
      c.repo.must(['push', '-q', 'origin', 'main']);
      c.repo.checkout('feature');
      c.repo.must(['merge', '-q', '--ff-only', 'main']);
      relink('../../lib/a.dart');
      c.repo.commitAll('link to code');
      c.repo.checkout('main');
      relink('../../docs/notes.md');
      c.repo.commitAll('link to notes');
      c.repo.must(['push', '-q', 'origin', 'main']);
      c.repo.checkout('feature');
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kOpenIssues]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+file mode 120000')));
    });

    test('a file mode that differs between the sides', () {
      final c = SyncCli.create();
      c.featureCommit({kOpenIssues: board([oi(1), oi(2), oi(3)])});
      runSpawn('chmod', ['+x', '${c.dir}/$kOpenIssues'], why: 'chmod +x the ledger');
      c.repo.commitAll('mode');
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kOpenIssues);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kOpenIssues), gits);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+file mode')));
    });

    test('delete against modify: no stage 2', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: null});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kLedger]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+no stage 2')));
    });

    test('modify against delete: no stage 3', () {
      final c = SyncCli.create();
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: null});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kLedger]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+no stage 3')));
    });

    test('a path with a space is listed and left (the NUL-separated parse keeps it whole)', () {
      final c = SyncCli.create(files: {'docs/a b.md': 'one\ntwo\nthree\n'});
      c.featureCommit({'docs/a b.md': 'one\nours\nthree\n'});
      c.mainCommit({'docs/a b.md': 'one\ntheirs\nthree\n'});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), ['docs/a b.md']);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/a b\.md\s+not on the resolvable list')));
    });

    test('no git on the PATH is a clean refusal (exit 2), not an internal error', () {
      final c = SyncCli.create();
      c.featureCommit({'README.md': 'feature readme\n'});
      final r = c.run([], path: c.minimalPath(['sh']));
      expectResult(r, 2, 'refused');
      expect(stdoutOf(r), contains('git could not be started'));
    });

    test('add against add: no stage 1', () {
      final c = SyncCli.create(files: {'README.md': 'readme\n'});
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_o')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_t')}'});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kLedger]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+no stage 1')));
    });

    test('a blob that is not UTF-8', () {
      final c = SyncCli.create();
      c.repo.writeBytes(kOpenIssues, [...bytes(board([oi(1), oi(2), oi(3)])), 0xff, 0x0a]);
      c.repo.commitAll('feature bytes');
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+stage 2 is not valid UTF-8')));
    });

    test('a NUL byte in an allow-listed path', () {
      final c = SyncCli.create();
      c.featureCommit({kOpenIssues: '${board([oi(1), oi(2), oi(3)])}${String.fromCharCode(0)}\n'});
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kOpenIssues]);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+ours: a NUL byte')));
    });

    test('git merge-file exiting 255 leaves the path untouched with the reason', () {
      final c = oiScenario();
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kOpenIssues);
      final path = c.stubPath({'git': 'if [ "\$1" = merge-file ]; then exit 255; fi'});
      final r = c.run([], path: path);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kOpenIssues), gits);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/open_issues\.md\s+git merge-file failed \(exit 255\)')));
    });

    test('the side file of a directory/file conflict is listed like every other unmerged path', () {
      final c = SyncCli.create(files: {...defaultFiles(), 'dirfile/inner.txt': 'inner\n'});
      c.featureCommit({'dirfile/inner.txt': 'inner changed\n'});
      c.mainCommit({'dirfile/inner.txt': null, 'dirfile': 'now a file\n'});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+dirfile/inner\.txt')));
      expect(stdoutOf(r), contains(RegExp(r'left\s+dirfile~\S+')));
      expect(c.unmerged().where((p) => p.startsWith('dirfile~')), hasLength(1));
    });
  });

  group('E10 where it runs from', () {
    test('a linked worktree keeps its state under its own git dir', () {
      final c = oiScenario();
      c.repo.must(['branch', 'feature2', 'feature']);
      final wt = c.repo.linkedWorktree('wt', 'feature2');
      final r = c.run([], cwd: wt.dir);
      expectResult(r, 0, 'ready');
      expect(File('${wt.dir}/$kOpenIssues').readAsStringSync(), board([oi(1), oi(2), oi(4), oi(3)]));
      final gitDir = wt.must(['rev-parse', '--path-format=absolute', '--git-dir']);
      expect(gitDir, contains('/worktrees/wt'));
      expect(Directory('$gitDir/sync_with_main').existsSync(), isTrue);
      expect(Directory('${c.gitDir}/sync_with_main').existsSync(), isFalse);
    });

    test('a run from a subdirectory resolves paths against the repository root', () {
      final c = oiScenario();
      final r = c.run([], cwd: '${c.dir}/docs/audit');
      expectResult(r, 0, 'ready');
      expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), oi(3)]));
    });
  });

  group('E12 marker-like lines', () {
    test('a line that only resembles a marker, or a bare divider, does not make the output partial', () {
      final c = SyncCli.create();
      final tricky = '## OI-5 — probe\n\n- **Status**: OPEN\n\n${'<' * 6} six is not a marker\n${'=' * 7}\n\n';
      c.featureCommit({kOpenIssues: board([oi(1), oi(2), tricky])});
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(c.unmerged(), isEmpty);
      expect(c.read(kOpenIssues), board([oi(1), oi(2), oi(4), tricky]));
    });

    test('a clean record that really contains a marker line is NOT staged (the tool and the commit gate agree)', () {
      final c = SyncCli.create();
      final marked = '## OI-5 — probe\n\n- **Status**: OPEN\n\n$kOpen kept as prose\n\n';
      c.featureCommit({kOpenIssues: board([oi(1), oi(2), marked])});
      c.mainCommit({kOpenIssues: board([oi(1), oi(2), oi(4)])});
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.unmerged(), [kOpenIssues]);
      expect(stdoutOf(r), isNot(contains(RegExp(r'resolved\s+docs/audit/open_issues\.md'))));
      expect(stdoutOf(r), contains(RegExp(r'(partial|left)\s+docs/audit/open_issues\.md')));
    });
  });
}
