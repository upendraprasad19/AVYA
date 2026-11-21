@Timeout(Duration(minutes: 12))
library;

// test/scripts/sync_with_main_state_e2e_test.dart
//
// Row E8 of docs/plans/sync-resolver.md section 5: resume and safety. What the tool wrote is remembered in
// `<git dir>/sync_with_main/written/`; what it overwrote is copied to `<git dir>/sync_with_main_backup/`.
// A file a human touched is never overwritten without a backup, and a file with no marker line never.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';
import '../helpers/sync_resolver_fixtures.dart';

const String kBugClasses = '.claude/skills/debugging/bug-classes.md';
const String kLedger = 'docs/audit/gate_test_ledger.yaml';
const String kOpenIssues = 'docs/audit/open_issues.md';

/// Both branches add bug class 2.2 with different text: the tool leaves a PARTIAL file.
SyncCli collisionScenario() {
  final c = SyncCli.create();
  final b = '# Bug classes\n\n${bugClass('2.1')}';
  c.featureCommit({kBugClasses: '$b${bugClass('2.2', body: 'ours text')}'});
  c.mainCommit({kBugClasses: '$b${bugClass('2.2', body: 'theirs text')}'});
  return c;
}

/// Both branches append a different ledger entry: the tool resolves it completely.
SyncCli ledgerScenario() {
  final c = SyncCli.create();
  c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}'});
  c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}'});
  return c;
}

/// A scenario whose merge is clean (disjoint files): nothing to overwrite.
SyncCli cleanScenario() {
  final c = SyncCli.create();
  c.featureCommit({'README.md': 'feature readme\n'});
  c.mainCommit({'lib/a.dart': 'line1\nmain edit\nline3\n'});
  return c;
}

List<String> backupRuns(SyncCli c) {
  final d = Directory('${c.gitDir}/sync_with_main_backup');
  if (!d.existsSync()) return [];
  return [
    for (final e in d.listSync())
      if (e is Directory) e.path.split('/').last,
  ]..sort();
}

String backupText(SyncCli c, String run, String rel) => File('${c.gitDir}/sync_with_main_backup/$run/$rel').readAsStringSync();

String writtenPath(SyncCli c, String rel) => '${c.gitDir}/sync_with_main/written/$rel';

bool get _isRoot => runSpawn('id', ['-u'], why: 'id -u', stdoutEncoding: utf8).stdout.toString().trim() == '0';

void main() {
  group('E8 resume and safety', () {
    test('a second run over the tool\'s own unchanged output writes nothing, adds no backup and keeps the old ones', () {
      final c = collisionScenario();
      expectResult(c.run([]), 1, 'pending');
      final out = c.readBytes(kBugClasses);
      final runs = backupRuns(c);
      expect(runs, hasLength(1));
      expect(File(writtenPath(c, kBugClasses)).readAsBytesSync(), out);
      final m = File('${c.dir}/$kBugClasses').statSync().modified;
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kBugClasses), out);
      expect(File('${c.dir}/$kBugClasses').statSync().modified, m, reason: 'not rewritten');
      expect(backupRuns(c), runs);
      expect(Directory('${c.gitDir}/sync_with_main_backup/${runs.single}').listSync(recursive: true).whereType<File>(), hasLength(1));
      expect(stdoutOf(r), contains('unchanged since the last run'));
      expect(stdoutOf(r), isNot(contains('backups of overwritten files')));
    });

    test('after a human edit of a file the tool wrote, the file is left alone and the state path is printed', () {
      final c = collisionScenario();
      expectResult(c.run([]), 1, 'pending');
      File('${c.dir}/$kBugClasses').writeAsStringSync('${c.read(kBugClasses)}\nhand note\n');
      final edited = c.readBytes(kBugClasses);
      final runs = backupRuns(c);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kBugClasses), edited);
      expect(backupRuns(c), runs);
      expect(stdoutOf(r), contains('edited since the tool wrote it'));
      expect(stdoutOf(r), contains(writtenPath(c, kBugClasses)));
    });

    test('removing the state path named in that message lets the tool redo the path, after a backup of the edit', () {
      final c = collisionScenario();
      expectResult(c.run([]), 1, 'pending');
      final tools = c.readBytes(kBugClasses);
      File('${c.dir}/$kBugClasses').writeAsStringSync('${c.read(kBugClasses)}\nhand note\n');
      final edited = c.read(kBugClasses);
      File(writtenPath(c, kBugClasses)).deleteSync();
      expectResult(c.run([]), 1, 'pending');
      expect(c.readBytes(kBugClasses), tools);
      expect(backupRuns(c), hasLength(2));
      expect(backupText(c, backupRuns(c).last, kBugClasses), edited);
    });

    test('a file hand-edited before the first run but still holding markers is overwritten ONLY after a backup, and a second run does not destroy it', () {
      final c = collisionScenario();
      expect(c.handMerge().exitCode, 1);
      File('${c.dir}/$kBugClasses').writeAsStringSync('${c.read(kBugClasses)}\n# hand comment\n');
      final edited = c.read(kBugClasses);
      expectResult(c.run([]), 1, 'pending');
      final out = c.readBytes(kBugClasses);
      expect(out, isNot(bytes(edited)));
      final runs = backupRuns(c);
      expect(runs, hasLength(1));
      expect(backupText(c, runs.single, kBugClasses), edited);
      expectResult(c.run([]), 1, 'pending');
      expect(c.readBytes(kBugClasses), out);
      expect(backupRuns(c), runs);
      expect(backupText(c, runs.single, kBugClasses), edited);
    });

    test('a file with NO marker line (resolved by hand or by rerere, not staged) is never overwritten', () {
      final c = collisionScenario();
      expect(c.handMerge().exitCode, 1);
      final resolved = '# Bug classes\n\n${bugClass('2.1')}${bugClass('2.2', body: 'the human merged both')}';
      File('${c.dir}/$kBugClasses').writeAsStringSync(resolved);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.read(kBugClasses), resolved);
      expect(c.unmerged(), [kBugClasses]);
      expect(backupRuns(c), isEmpty);
      expect(stdoutOf(r), contains(RegExp(r'left\s+\.claude/skills/debugging/bug-classes\.md\s+resolved but not staged')));
      expect(stdoutOf(r), contains('git add $kBugClasses'));
    });

    test('a failing backup (read-only backup parent) means NO overwrite', () {
      if (_isRoot) {
        markTestSkipped('root bypasses file modes');
        return;
      }
      final c = ledgerScenario();
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kLedger);
      final root = Directory('${c.gitDir}/sync_with_main_backup')..createSync();
      runSpawn('chmod', ['555', root.path], why: 'read-only backup parent');
      addTearDown(() => runSpawn('chmod', ['755', root.path], why: 'restore the backup parent'));
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kLedger), gits);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+could not back up')));
      expect(c.unmerged(), [kLedger]);
    });

    test('the target\'s directory made read-only: left, the file untouched, no temp file anywhere', () {
      if (_isRoot) {
        markTestSkipped('root bypasses file modes');
        return;
      }
      final c = ledgerScenario();
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kLedger);
      final dir = '${c.dir}/docs/audit';
      runSpawn('chmod', ['555', dir], why: 'read-only target directory');
      addTearDown(() => runSpawn('chmod', ['755', dir], why: 'restore the target directory'));
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kLedger), gits);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+could not write')));
      final tmp = Directory('${c.gitDir}/sync_with_main/tmp');
      expect(!tmp.existsSync() || tmp.listSync().isEmpty, isTrue, reason: 'no temp file is left in the state directory');
      expect(Directory(dir).listSync().map((e) => e.path.split('/').last), isNot(contains(anyOf(contains('.tmp'), contains('.pid')))));
      expect(backupRuns(c), hasLength(1), reason: 'the backup of git\'s file was taken before the failed write and is kept');
    });

    test('an unreadable file is left with an internal-error line and the other paths are still resolved', () {
      if (_isRoot) {
        markTestSkipped('root bypasses file modes');
        return;
      }
      final c = SyncCli.create();
      final bb = '# Bug classes\n\n${bugClass('2.1')}';
      c.featureCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_o')}', kBugClasses: '$bb${bugClass('2.2', body: 'ours')}'});
      c.mainCommit({kLedger: '# header\n\n${ledgerRec('check_a')}${ledgerRec('check_t')}', kBugClasses: '$bb${bugClass('2.3', body: 'theirs')}'});
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kLedger);
      runSpawn('chmod', ['000', '${c.dir}/$kLedger'], why: 'unreadable target');
      addTearDown(() => runSpawn('chmod', ['644', '${c.dir}/$kLedger'], why: 'restore the target'));
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+internal error: ')));
      expect(stdoutOf(r), contains(RegExp(r'resolved\s+\.claude/skills/debugging/bug-classes\.md\s+staged')));
      runSpawn('chmod', ['644', '${c.dir}/$kLedger'], why: 'restore the target');
      expect(c.readBytes(kLedger), gits);
      expect(c.unmerged(), [kLedger]);
    });

    test('a line only the commit-time marker gate calls a marker (eight "<") passes the checks but is never staged: partial, still unmerged', () {
      final c = SyncCli.create();
      final fenced = bugClass('2.1', body: '```\n${'<' * 8}\n```');
      final b = '# Bug classes\n\n$fenced';
      c.featureCommit({kBugClasses: '$b${bugClass('2.2', body: 'ours text')}'});
      c.mainCommit({kBugClasses: '$b${bugClass('2.3', body: 'theirs text')}'});
      expect(c.handMerge().exitCode, 1);
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'partial\s+\.claude/skills/debugging/bug-classes\.md\s+markers kept for: a conflict')));
      expect(c.unmerged(), [kBugClasses]);
      expect(c.read(kBugClasses), '$b${bugClass('2.3', body: 'theirs text')}${bugClass('2.2', body: 'ours text')}');
    });

    test('an unwritable state tmp directory (no temp file for git merge-file) means left, the file untouched, nothing written next to the target', () {
      if (_isRoot) {
        markTestSkipped('root bypasses file modes');
        return;
      }
      final c = ledgerScenario();
      expect(c.handMerge().exitCode, 1);
      final gits = c.readBytes(kLedger);
      final tmp = Directory('${c.gitDir}/sync_with_main/tmp')..createSync(recursive: true);
      runSpawn('chmod', ['555', tmp.path], why: 'read-only state tmp directory');
      addTearDown(() => runSpawn('chmod', ['755', tmp.path], why: 'restore the state tmp directory'));
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kLedger), gits);
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+could not write')));
      expect(Directory('${c.dir}/docs/audit').listSync().map((e) => e.path.split('/').last), isNot(contains(contains('tmp'))));
      expect(c.unmerged(), [kLedger]);
    });

    test('the state is cleared by a fresh start, backups survive, and the stale written/ of an aborted merge is discarded by the identity check', () {
      final c = collisionScenario();
      expectResult(c.run([]), 1, 'pending');
      final firstOut = c.readBytes(kBugClasses);
      final runs1 = backupRuns(c);
      expect(runs1, hasLength(1));
      c.repo.must(['merge', '--abort']);
      sleep(const Duration(milliseconds: 60));
      // a hand re-merge: MERGE_HEAD is a new file with the same SHA, written/ is the old merge's
      expect(c.handMerge().exitCode, 1);
      expect(File(writtenPath(c, kBugClasses)).existsSync(), isTrue, reason: 'the aborted merge left its record behind');
      final r = c.run([]);
      expectResult(r, 1, 'pending');
      expect(c.readBytes(kBugClasses), firstOut, reason: 'overwritten again, not "edited since the tool wrote it"');
      expect(stdoutOf(r), isNot(contains('edited since')));
      final runs2 = backupRuns(c);
      expect(runs2, hasLength(2));
      expect(runs2, containsAll(runs1));
      // and the CLI's own fresh start after another abort clears the state but not the backups
      c.repo.must(['merge', '--abort']);
      final r3 = c.run([]);
      expectResult(r3, 1, 'pending');
      expect(c.readBytes(kBugClasses), firstOut);
      expect(backupRuns(c), hasLength(3));
    });

    test('the post-crash disk state: the output is already in the file but nothing was recorded or staged', () {
      final a = ledgerScenario();
      expectResult(a.run([]), 0, 'ready');
      final output = a.read(kLedger);
      final b = ledgerScenario();
      expect(b.handMerge().exitCode, 1);
      File('${b.dir}/$kLedger').writeAsStringSync(output);
      expect(b.unmerged(), [kLedger]);
      expect(File(writtenPath(b, kLedger)).existsSync(), isFalse);
      final r = b.run([]);
      expectResult(r, 0, 'ready');
      expect(b.unmerged(), isEmpty);
      expect(b.read(kLedger), output);
      expect(File(writtenPath(b, kLedger)).readAsStringSync(), output);
      expect(backupRuns(b), isEmpty, reason: 'nothing was overwritten');
      expect(stdoutOf(r), contains('already in place'));
    });

    test('a git add that fails is "written, NOT staged" and exit 1', () {
      final c = ledgerScenario();
      final path = c.stubPath({'git': 'if [ "\$1" = add ]; then echo "fatal: add refused" >&2; exit 1; fi'});
      final r = c.run([], path: path);
      expectResult(r, 1, 'pending');
      expect(stdoutOf(r), contains(RegExp(r'left\s+docs/audit/gate_test_ledger\.yaml\s+written, NOT staged')));
      expect(c.hasMarkers(kLedger), isFalse);
      expect(c.unmerged(), [kLedger]);
    });

    test('pruning ignores empty run directories, and a run that took no backup prunes nothing', () {
      void plant(String root, int n, {bool emptyToo = false}) {
        for (var i = 1; i <= n; i++) {
          final d = Directory('$root/old-$i')..createSync(recursive: true);
          File('${d.path}/f.md').writeAsStringSync('$i');
          runSpawn('touch', ['-d', '2020-01-${i.toString().padLeft(2, '0')}', d.path], why: 'age the planted run directory');
        }
        if (emptyToo) {
          final e = Directory('$root/empty-run')..createSync();
          runSpawn('touch', ['-d', '2030-01-01', e.path], why: 'make the empty run directory the newest');
        }
      }

      // a run that takes no backup (a clean merge: nothing to overwrite) touches none of them
      final noop = cleanScenario();
      final noopRoot = '${noop.gitDir}/sync_with_main_backup';
      plant(noopRoot, 22, emptyToo: true);
      expectResult(noop.run([]), 0, 'ready');
      expect(Directory(noopRoot).listSync().whereType<Directory>(), hasLength(23));

      // a run that does back up keeps the 20 newest directories that hold files and drops the empty one
      final c = collisionScenario();
      final root = '${c.gitDir}/sync_with_main_backup';
      plant(root, 22, emptyToo: true);
      expectResult(c.run([]), 1, 'pending');
      final runs = backupRuns(c);
      expect(runs, hasLength(20));
      expect(runs, isNot(contains('empty-run')));
      expect(runs, isNot(contains('old-1')));
      expect(runs, isNot(contains('old-3')));
      expect(runs, contains('old-4'));
      expect(runs.any((r) => r.startsWith(c.head.substring(0, 8))), isTrue, reason: 'the newest run directory is kept');
    });

    test('the READY path prunes too: 22 planted run directories + the new backup leave 20', () {
      final c = ledgerScenario();
      final root = '${c.gitDir}/sync_with_main_backup';
      for (var i = 1; i <= 22; i++) {
        final d = Directory('$root/old-$i')..createSync(recursive: true);
        File('${d.path}/f.md').writeAsStringSync('$i');
        runSpawn('touch', ['-d', '2020-01-${i.toString().padLeft(2, '0')}', d.path], why: 'age the planted run directory');
      }
      expectResult(c.run([]), 0, 'ready');
      final runs = backupRuns(c);
      expect(runs, hasLength(20));
      expect(runs, isNot(contains('old-1')));
      expect(runs.any((r) => r.startsWith(c.head.substring(0, 8))), isTrue);
    });

    test('a file changed in the work tree after the tool staged it is named as NOT in the merge commit', () {
      final c = ledgerScenario();
      expectResult(c.run([]), 0, 'ready');
      expect(stdoutOf(c.run([])), isNot(contains('NOT in the merge commit')));
      File('${c.dir}/$kLedger').writeAsStringSync('${c.read(kLedger)}# hand edit after staging\n');
      final r = c.run([]);
      expectResult(r, 0, 'ready');
      expect(stdoutOf(r), contains('NOT in the merge commit'));
      expect(stdoutOf(r), contains(kLedger));
    });

    test('21 runs that each make a backup keep 20 run directories; a no-op rerun creates none', () {
      final c = collisionScenario();
      expectResult(c.run([]), 1, 'pending');
      for (var i = 2; i <= 21; i++) {
        c.repo.must(['checkout', '--merge', '--', kBugClasses]);
        Directory('${c.gitDir}/sync_with_main/written').deleteSync(recursive: true);
        expectResult(c.run([]), 1, 'pending');
      }
      final runs = backupRuns(c);
      expect(runs, hasLength(20));
      final head8 = c.head.substring(0, 8);
      expect(runs, isNot(contains('$head8-1')), reason: 'the oldest run directory was pruned');
      expect(runs, contains('$head8-21'));
      expectResult(c.run([]), 1, 'pending');
      expect(backupRuns(c), runs, reason: 'a no-op rerun creates no run directory and prunes nothing');
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
