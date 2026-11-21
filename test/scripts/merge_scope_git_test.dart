@Timeout(Duration(minutes: 5))
library;

// test/scripts/merge_scope_git_test.dart
//
// scripts/merge_scope_lib.dart against REAL git: a branch syncs origin/main with
// `git merge --no-commit --no-ff -s ort`, the human resolves, and the returned set is asserted as
// full-set equality. Scenarios S1-S12 and S14-S21 of docs/plans/sync-merge-scope.md section 5 (the
// seeded fuzz S13 is test/scripts/merge_scope_git_fuzz_test.dart). Fixtures: test/helpers/merge_scope_repo.dart
// (hermetic environment, empty global git config, repo-local pins).
//
// Every scenario asserts the merge SHAPE it needs (stage numbers, exit code) before it asserts the
// verdict, so a git version that behaves differently fails loudly at setup rather than passing for
// the wrong reason.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/merge_scope_lib.dart';
import '../helpers/merge_scope_repo.dart';

const String _doc3 = 'line 1\nline 2\nline 3\n';

String _lines(List<String> l) => '${l.join('\n')}\n';

/// Ten lines of "code" so git's rename detection sees a similar file.
String _code(String tag, {String? line3}) => _lines(<String>[
      'export const a = 1;',
      'export const b = 2;',
      line3 ?? 'export const c = 3;',
      'export const d = 4;',
      'export const e = 5;',
      'export const f = 6;',
      'export const g = 7;',
      'export const h = 8;',
      'export const i = 9;',
      'export const j = 10; // $tag',
    ]);

void main() {
  group('S1-S5: the human resolution', () {
    test('S1 a conflicted docs file resolved by hand: only it is graded, main\'s catastrophic files are not', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {
          kDocPath: 'line 1\nMAIN\nline 3\n',
          kCatPath: 'payment v2\n',
          'supabase/migrations/200_x.sql': 'create function x() security definer returns int as \$\$ select 1 \$\$ language sql;\n',
        },
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 1, reason: 'setup: the docs file must conflict');
      expect(r.stages(kDocPath), <int>[1, 2, 3], reason: 'setup: three stages');
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.stage([kDocPath]);
      final staged = r.stagedPaths();
      expect(staged, containsAll(<String>[kDocPath, kCatPath, 'supabase/migrations/200_x.sql']), reason: 'setup: main\'s files are staged');
      final s = r.scope();
      expect(gradedOf(s), <String>[kDocPath]);
      expect((s as Scoped).tip, sc.mainSha);
      expect(s.mergeHead, sc.mainSha);
    });

    test('S2 the human edits main\'s catastrophic file: it is graded', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.write(kCatPath, 'payment v2 TAMPERED\n');
      r.stage([kDocPath, kCatPath]);
      expect(gradedOf(r.scope()), <String>[kDocPath, kCatPath]);
    });

    test('S3 both sides edit different regions of one catastrophic file and git merges it cleanly: it is graded', () {
      final sc = SyncScenario.build(
        baseFiles: {kCatPath: _lines(<String>['a', 'b', 'c', 'd', 'e'])},
        featureFiles: {kCatPath: _lines(<String>['A', 'b', 'c', 'd', 'e'])},
        mainFiles: {kCatPath: _lines(<String>['a', 'b', 'c', 'd', 'E'])},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0, reason: 'setup: a clean merge');
      expect(File('${r.dir}/${r.must(['rev-parse', '--git-path', 'MERGE_HEAD'])}').existsSync(), isTrue, reason: 'setup: the merge is pending');
      expect(File('${r.dir}/$kCatPath').readAsStringSync(), _lines(<String>['A', 'b', 'c', 'd', 'E']));
      expect(gradedOf(r.scope()), <String>[kCatPath]);
    });

    test('S4 the human takes main\'s whole version with `checkout <TIP> -- path`: not graded; `-X theirs` over a file the branch also edited elsewhere: graded', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.must(['checkout', sc.mainSha, '--', kDocPath]);
      expect(gradedOf(r.scope()), isEmpty);
      expect(r.stagedPaths(), contains(kDocPath), reason: 'setup: the taken file differs from HEAD, so it is staged');

      final sc2 = SyncScenario.build(
        baseFiles: {kDocPath: _lines(<String>['l1', 'l2', 'l3', 'l4', 'l5'])},
        featureFiles: {kDocPath: _lines(<String>['B1', 'l2', 'B3', 'l4', 'l5'])},
        mainFiles: {kDocPath: _lines(<String>['l1', 'l2', 'M3', 'l4', 'M5'])},
        mergeExtra: <String>['-X', 'theirs'],
      );
      expect(File('${sc2.repo.dir}/$kDocPath').readAsStringSync(), _lines(<String>['B1', 'l2', 'M3', 'l4', 'M5']), reason: 'setup: -X theirs mixes both sides');
      expect(gradedOf(sc2.repo.scope()), <String>[kDocPath]);
    });

    test('S5 the human restores HEAD\'s version of a file main changed: not graded and not even staged', () {
      final sc = SyncScenario.build(
        baseFiles: {kCatPath: 'payment v1\n'},
        mainFiles: {kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      expect(r.stagedPaths(), contains(kCatPath));
      r.must(['checkout', 'HEAD', '--', kCatPath]);
      expect(r.stagedPaths(), isNot(contains(kCatPath)));
      final s = r.scope();
      expect(gradedOf(s), isEmpty);
      expect(oracleGraded(r).map((p) => p).toSet(), isEmpty);
    });
  });

  group('S6-S9: git moves content to a path neither side changed', () {
    test('S6 main renames a catastrophic file while the branch edited the old path: exactly the NEW path is graded', () {
      final sc = SyncScenario.build(
        baseFiles: {kCatPath: _code('v1')},
        featureFiles: {kCatPath: _code('v1', line3: 'export const c = 333; // branch edit')},
      );
      // main renames (built on the same repo: switch, commit, switch back, redo the merge)
      final r = sc.repo;
      r.must(['merge', '--abort']);
      r.checkout('main');
      r.must(['mv', kCatPath, 'supabase/functions/verify-payment/index2.ts']);
      final main = r.commitAll('main renames');
      r.setOriginMain(main);
      r.checkout('feature');
      final m = r.merge('refs/remotes/origin/main');
      expect(m.exitCode, 0, reason: 'setup: ort follows the rename and merges cleanly: ${m.stdout}${m.stderr}');
      const newPath = 'supabase/functions/verify-payment/index2.ts';
      expect(File('${r.dir}/$newPath').readAsStringSync(), contains('branch edit'), reason: 'setup: the branch\'s edit followed the rename');
      expect(gradedOf(r.scope()), <String>[newPath]);
    });

    test('S7 the branch renames into a catastrophic directory and main edits the old path: the new path is graded', () {
      final sc = SyncScenario.build(
        baseFiles: {'lib/pay_logic.ts': _code('v1')},
        featureFiles: {},
      );
      final r = sc.repo;
      r.must(['merge', '--abort']);
      r.must(['reset', '-q', '--hard', sc.baseSha]);
      Directory('${r.dir}/supabase/functions/verify-payment').createSync(recursive: true);
      r.must(['mv', 'lib/pay_logic.ts', 'supabase/functions/verify-payment/pay_logic.ts']);
      r.commitAll('feature renames into the catastrophic directory');
      r.checkout('main');
      r.write('lib/pay_logic.ts', _code('v1', line3: 'export const c = 333; // main edit'));
      final main = r.commitAll('main edits the old path');
      r.setOriginMain(main);
      r.checkout('feature');
      final m = r.merge('refs/remotes/origin/main');
      expect(m.exitCode, 0, reason: 'setup: ${m.stdout}${m.stderr}');
      const newPath = 'supabase/functions/verify-payment/pay_logic.ts';
      expect(File('${r.dir}/$newPath').readAsStringSync(), contains('main edit'), reason: 'setup: main\'s edit followed the rename');
      expect(gradedOf(r.scope()), <String>[newPath]);
    });

    test('S8 main renames a directory into a catastrophic one and the branch added a file under the old directory, accepted unchanged: graded', () {
      final repo = ScopeRepo.create();
      repo.write('olddir/a.txt', _code('a'));
      repo.write('olddir/b.txt', _code('b'));
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      repo.checkoutNew('feature');
      repo.write('olddir/extra.ts', 'export const extra = 1;\n');
      repo.commitAll('feature adds a file under the old directory');
      repo.checkout('main');
      Directory('${repo.dir}/supabase/functions/verify-payment').createSync(recursive: true);
      repo.must(['mv', 'olddir', 'supabase/functions/verify-payment/newdir']);
      final main = repo.commitAll('main moves the directory');
      repo.setOriginMain(main);
      repo.checkout('feature');
      final m = repo.merge('refs/remotes/origin/main');
      const moved = 'supabase/functions/verify-payment/newdir/extra.ts';
      expect(repo.stages(moved), isNotEmpty, reason: 'setup: git relocated the branch\'s file (exit ${m.exitCode}): ${m.stdout}');
      repo.must(['add', '--', moved]);
      expect(repo.stages(moved), <int>[0]);
      expect(base, isNotEmpty);
      expect(gradedOf(repo.scope()), contains(moved));
    });

    test('S9 rename/rename and file-versus-directory conflicts: the set equals the independent oracle', () {
      final repo = ScopeRepo.create();
      repo.write('r1.txt', _code('r1'));
      repo.write(kDocPath, _doc3);
      repo.commitAll('base');
      repo.checkoutNew('feature');
      repo.must(['mv', 'r1.txt', 'fa.txt']);
      repo.write('df', 'a file on the branch\n');
      repo.commitAll('feature');
      repo.checkout('main');
      repo.must(['mv', 'r1.txt', 'ma.txt']);
      repo.write('df/inner.txt', 'a directory on main\n');
      final main = repo.commitAll('main');
      repo.setOriginMain(main);
      repo.checkout('feature');
      final m = repo.merge('refs/remotes/origin/main');
      expect(m.exitCode, 1, reason: 'setup: conflicts expected: ${m.stdout}');
      repo.stageAll();
      final graded = gradedOf(repo.scope()).map(byteString).toSet();
      expect(graded, isNotEmpty);
      expect(graded, oracleGraded(repo));
    });
  });

  group('S10-S12: which MERGE_HEAD is trusted', () {
    test('S10a an INTERIOR commit of a --no-ff PR that adds a catastrophic file a later commit removes: graded', () {
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      repo.checkoutNew('pr');
      repo.write(kCatPath2, 'cron v1\n');
      final p1 = repo.commitAll('pr: add');
      repo.remove(kCatPath2);
      repo.commitAll('pr: remove');
      repo.checkout('main');
      repo.must(['merge', '--no-ff', '-q', '-m', 'Merge pull request #1 from x/pr', 'pr']);
      repo.setOriginMain(repo.head());
      repo.checkoutNew('feature', from: base);
      repo.write('own.txt', 'own\n');
      repo.commitAll('feature');
      final m = repo.merge(p1);
      expect(m.exitCode, 0, reason: 'setup: ${m.stdout}${m.stderr}');
      expect(repo.stagedPaths(), contains(kCatPath2), reason: 'setup: the interior commit brings the file');
      expect(gradedOf(repo.scope()), <String>[kCatPath2]);
    });

    test('S10b a fast-forwarded interior commit and the head of a PR that main reverted: graded; a PR head whose content main still holds: not graded', () {
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      // linear main: c1 adds the file, c2 removes it
      repo.write(kCatPath2, 'cron v1\n');
      final c1 = repo.commitAll('c1 adds');
      repo.remove(kCatPath2);
      repo.commitAll('c2 removes');
      // a PR that main merged and then reverted
      repo.checkoutNew('pr2', from: base);
      repo.write(kCatPath, 'payment v1\n');
      final prHead = repo.commitAll('pr2');
      repo.checkout('main');
      repo.must(['merge', '--no-ff', '-q', '-m', 'Merge pull request #2 from x/pr2', 'pr2']);
      repo.remove(kCatPath);
      repo.commitAll('revert pr2');
      // a PR that main merged and still holds
      repo.checkoutNew('pr3', from: base);
      repo.write('docs/kept.md', 'kept\n');
      final keptHead = repo.commitAll('pr3');
      repo.checkout('main');
      repo.must(['merge', '--no-ff', '-q', '-m', 'Merge pull request #3 from x/pr3', 'pr3']);
      repo.setOriginMain(repo.head());

      for (final entry in <(String, String, String)>[('c1', c1, kCatPath2), ('prHead', prHead, kCatPath)]) {
        repo.checkoutNew('feature_${entry.$1}', from: base);
        repo.write('own_${entry.$1}.txt', 'own\n');
        repo.commitAll('feature');
        final m = repo.merge(entry.$2);
        expect(m.exitCode, 0, reason: 'setup ${entry.$1}: ${m.stdout}${m.stderr}');
        expect(gradedOf(repo.scope()), <String>[entry.$3], reason: entry.$1);
        repo.must(['merge', '--abort']);
        repo.checkout('main');
      }

      repo.checkoutNew('feature_kept', from: base);
      repo.write('own_kept.txt', 'own\n');
      repo.commitAll('feature');
      expect(repo.merge(keptHead).exitCode, 0);
      expect(repo.stagedPaths(), contains('docs/kept.md'));
      expect(gradedOf(repo.scope()), isEmpty);
      repo.must(['merge', '--abort']);

      // the tip itself
      repo.checkout('feature_kept');
      expect(repo.merge('refs/remotes/origin/main').exitCode, 0);
      expect(gradedOf(repo.scope()), isEmpty);
    });

    test('S11 a tag, a branch and a local main that all look like origin/main do not shadow the ref', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.stage([kDocPath]);
      r.must(['tag', 'origin/main', sc.baseSha]);
      r.must(['branch', 'origin/main', sc.baseSha]);
      r.must(['branch', '-f', 'main', sc.baseSha]);
      final s = r.scope();
      expect(gradedOf(s), <String>[kDocPath]);
      expect((s as Scoped).tip, sc.mainSha);
    });

    test('S12a no refs/remotes/origin/main, an octopus merge, another branch as MERGE_HEAD, a shallow cut: each is a Fallback with its own reason', () {
      // no origin/main
      final sc = SyncScenario.build(mainFiles: {kCatPath: 'payment v2\n'});
      sc.repo.must(['update-ref', '-d', 'refs/remotes/origin/main']);
      expectFallback(sc.repo.scope(), 'refs/remotes/origin/main is missing or not a commit');

      // another feature branch as MERGE_HEAD: not an ancestor of the tip
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      repo.setOriginMain(base);
      repo.checkoutNew('other');
      repo.write(kCatPath, 'payment from another branch\n');
      repo.commitAll('other');
      repo.checkoutNew('feature', from: base);
      repo.write('own.txt', 'own\n');
      repo.commitAll('feature');
      expect(repo.merge('other').exitCode, 0);
      expectFallback(repo.scope(), 'MERGE_HEAD is not an ancestor of origin/main (or the history is shallow)');
    });

    test('S12b an octopus merge is a Fallback (MERGE_HEAD holds two lines)', () {
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      repo.setOriginMain(base);
      repo.checkoutNew('b1');
      repo.write('one.txt', '1\n');
      repo.commitAll('b1');
      repo.checkoutNew('b2', from: base);
      repo.write('two.txt', '2\n');
      repo.commitAll('b2');
      repo.checkout('main');
      final m = repo.git(['merge', '--no-commit', '--no-ff', 'b1', 'b2']);
      expect(m.exitCode, 0, reason: 'setup: octopus: ${m.stdout}${m.stderr}');
      expectFallback(repo.scope(), 'MERGE_HEAD has 2 lines (octopus merge or empty file)');
    });

    test('S12c a shallow cut that hides the answer is a Fallback', () {
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      final base = repo.commitAll('base');
      repo.write('m1.txt', '1\n');
      final c1 = repo.commitAll('c1');
      repo.write('m2.txt', '2\n');
      final c2 = repo.commitAll('c2');
      repo.setOriginMain(c2);
      repo.checkoutNew('feature', from: base);
      repo.write('own.txt', 'own\n');
      repo.commitAll('feature');
      expect(repo.merge(c1).exitCode, 0);
      // cut c2 off from its parents: c1 is no longer reachable from the tip
      File('${repo.dir}/.git/shallow').writeAsStringSync('$c2\n');
      expectFallback(repo.scope(), 'MERGE_HEAD is not an ancestor of origin/main (or the history is shallow)');
    });
  });

  group('S14-S21: names, gitlinks, hostile environments', () {
    test('S14 a gitlink moved under .gitmodules ignore = all is still graded', () {
      final repo = ScopeRepo.create();
      repo.write('.gitmodules', '[submodule "sm"]\n\tpath = sm\n\turl = https://example.invalid/sm.git\n\tignore = all\n');
      repo.write(kDocPath, _doc3);
      repo.must(['add', '--', '.gitmodules', kDocPath]);
      const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const c = 'cccccccccccccccccccccccccccccccccccccccc';
      repo.must(['update-index', '--add', '--cacheinfo', '160000,$a,sm']);
      repo.commitIndex('base');
      repo.checkoutNew('feature');
      repo.must(['update-index', '--cacheinfo', '160000,$b,sm']);
      repo.commitIndex('feature moves the gitlink');
      repo.checkout('main');
      repo.write(kDocPath, 'line 1\nMAIN\nline 3\n');
      repo.must(['add', '--', kDocPath]);
      final main = repo.commitIndex('main edits the doc');
      repo.setOriginMain(main);
      repo.checkout('feature');
      final m = repo.merge('refs/remotes/origin/main');
      expect(m.exitCode, 0, reason: 'setup: ${m.stdout}${m.stderr}');
      repo.must(['update-index', '--cacheinfo', '160000,$c,sm']);
      expect(repo.stagedPaths(), contains('sm'), reason: 'setup: the hardened reader sees the gitlink');
      expect(gradedOf(repo.scope()), <String>['sm']);
    });

    test('S15 a conflict-resolved non-ASCII name and an emoji-named new file are graded by their real names', () {
      final accented = 'docs/r${String.fromCharCode(0xe9)}sum${String.fromCharCode(0xe9)}.md';
      final emoji = 'docs/${String.fromCharCodes(const <int>[0xd83d, 0xde00])}.md';
      final sc = SyncScenario.build(
        baseFiles: {accented: _doc3},
        featureFiles: {accented: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {accented: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 1);
      r.write(accented, 'line 1\nBOTH\nline 3\n');
      r.write(emoji, 'new\n');
      r.stage([accented, emoji]);
      expect(gradedOf(r.scope()).toSet(), <String>{accented, emoji});
    });

    test('S16 files named HEAD, the tip\'s hex name and MERGE_HEAD\'s hex name in the worktree root do not break the diff-index calls', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.stage([kDocPath]);
      r.write('HEAD', 'a file called HEAD\n');
      r.write(sc.mainSha, 'a file named by the tip\n');
      expect(gradedOf(r.scope()), <String>[kDocPath]);
    });

    test('S17 an intent-to-add entry makes the two index reads disagree: Fallback', () {
      final sc = SyncScenario.build(mainFiles: {kCatPath: 'payment v2\n'});
      final r = sc.repo;
      r.write('ita.txt', 'intent to add\n');
      r.must(['add', '-N', '--', 'ita.txt']);
      expectFallback(r.scope(), 'index reads disagree');
    });

    test('S18 MERGE_HEAD is an OLD main commit: what main no longer holds is graded, and restoring the tip\'s version ungrades it', () {
      final repo = ScopeRepo.create();
      repo.write(kDocPath, _doc3);
      repo.write(kCatPath, 'payment v0\n');
      final base = repo.commitAll('base');
      repo.write(kCatPath, 'payment v1\n');
      final m1 = repo.commitAll('main v1');
      repo.write(kCatPath, 'payment v2\n');
      final m2 = repo.commitAll('main v2');
      repo.setOriginMain(m2);
      repo.checkoutNew('feature', from: base);
      repo.write('own.txt', 'own\n');
      repo.commitAll('feature');
      expect(repo.merge(m1).exitCode, 0);
      expect(File('${repo.dir}/$kCatPath').readAsStringSync(), 'payment v1\n');
      expect(gradedOf(repo.scope()), <String>[kCatPath], reason: 'v1 is what main no longer holds');
      repo.must(['checkout', m2, '--', kCatPath]);
      expect(gradedOf(repo.scope()), isEmpty, reason: 'v2 is what main holds today');
    });

    test('S19 rewriting the mtime of a main-brought file after the merge does not grade it', () {
      final sc = SyncScenario.build(mainFiles: {kCatPath: 'payment v2\n'});
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0);
      File('${r.dir}/$kCatPath').setLastModifiedSync(DateTime.utc(2001, 1, 1));
      expect(r.stagedPaths(), contains(kCatPath));
      expect(gradedOf(r.scope()), isEmpty);
    });

    test('S20 a hostile repo-local config (diff.orderFile, diff.ignoreSubmodules=all) changes neither the set nor Scoped', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n', 'zz.md': 'z\n'},
      );
      final r = sc.repo;
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.stage([kDocPath]);
      final before = gradedOf(r.scope());
      File('${r.root.path}/order.txt').writeAsStringSync('zz.md\nsupabase\ndocs\n');
      r.must(['config', 'diff.orderFile', '${r.root.path}/order.txt']);
      r.must(['config', 'diff.ignoreSubmodules', 'all']);
      expect(gradedOf(r.scope()), before);
    });

    test('S21 a pending merge in a LINKED worktree (an absolute MERGE_HEAD path) is scoped', () {
      final sc = SyncScenario.build(
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.must(['merge', '--abort']);
      r.checkout('main');
      final wt = r.linkedWorktree('wt', 'feature');
      final m = wt.merge('refs/remotes/origin/main');
      expect(m.exitCode, 1, reason: 'setup: ${m.stdout}${m.stderr}');
      wt.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      wt.stage([kDocPath]);
      final gp = wt.must(['rev-parse', '--git-path', 'MERGE_HEAD']);
      expect(gp.startsWith('/'), isTrue, reason: 'setup: a linked worktree reports an absolute path, got $gp');
      expect(gradedOf(wt.scope()), <String>[kDocPath]);
    });
  });
}
