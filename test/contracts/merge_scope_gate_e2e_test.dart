@Timeout(Duration(minutes: 10))
library;

// test/contracts/merge_scope_gate_e2e_test.dart
//
// The REAL scripts/check_code_review_pass_exists.dart, spawned in throwaway git repositories, against
// a REAL pending branch sync (landing C1, docs/plans/sync-merge-scope.md section 5 item 3, closes
// OI-413). The lib's own contract is test/scripts/merge_scope_lib_test.dart (pure) and
// test/scripts/merge_scope_git_test.dart (real git); this file proves the GATE uses it: the tier loop
// iterates the graded set, the hash and the review path still come from the FULL staged diff, the
// NOTE reaches stdout, every failed precondition falls back to today's behavior, and the staged-path
// read the gate does for non-merge commits is exact (renames, non-ASCII and line-terminator names,
// invalid UTF-8, gitlinks under `ignore = all`).
//
// Fixtures: test/helpers/merge_scope_repo.dart (hermetic git environment, the gate's import closure
// copied with copyScriptClosure) and test/helpers/git_tree_fixture.dart (names the porcelain cannot
// create). Every `expect(exitCode, ...)` names the exact code: 0 pass, 1 fail.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/git_tree_fixture.dart';
import '../helpers/merge_scope_repo.dart';
import '../helpers/spawn.dart';

const String _needsReview = 'requires a STAGED review file';

String _out(ProcessResult r) => '--- stdout ---\n${r.stdout}--- stderr ---\n${r.stderr}';

String _short(String sha) => sha.substring(0, 7);

/// The scoped NOTE line, exactly as the gate prints it.
String _scopedNote({
  required String tip,
  required String mergeHead,
  required int staged,
  required List<String> graded,
  String tag = '[Gate]',
}) =>
    '$tag NOTE: branch sync of origin/main (tip ${_short(tip)}, MERGE_HEAD ${_short(mergeHead)}): '
    'grading ${graded.length} path(s) whose entry matches neither HEAD nor origin/main, of $staged '
    'staged${graded.isEmpty ? '' : ': ${graded.join(', ')}'}. Unmerged paths are graded.';

String _fallbackNote(String reason, int staged) =>
    '[Gate] NOTE: branch-sync scoping not applied ($reason): grading all $staged staged path(s)';

/// The first 12 characters of the hash the gate derives from the FULL staged diff (the same pipeline
/// as the gate's `stagedDiffHash`: `docs/reviews/**` and the two code-review skill files excluded).
String _fullDiffHash(ScopeRepo r) {
  final res = runSpawn(
    'sh',
    [
      '-c',
      "git diff --cached --ignore-submodules=none -- ':(top)' ':(top,exclude)docs/reviews' "
          "':(top,exclude).claude/skills/code-review/SKILL.md' "
          "':(top,exclude).claude/skills/code-review/tuning-history.md' | git hash-object --stdin",
    ],
    why: 'merge_scope_gate_e2e: the gate\'s staged-diff hash',
    workingDirectory: r.dir,
    extraEnv: r.env,
    allowControl: ScopeRepo.allowControl,
  );
  expect(res.exitCode, 0, reason: 'setup: hash: ${res.stderr}');
  return (res.stdout as String).trim().substring(0, 12);
}

/// Stages an accepted review named for the FULL staged diff; asserts the hash did not move.
String _stageAcceptedReview(ScopeRepo r) {
  final h = _fullDiffHash(r);
  r.write('docs/reviews/$h-review.md', '---\nverdict: accepted\n---\n\nreviewed\n');
  r.stage(['docs/reviews/$h-review.md']);
  expect(_fullDiffHash(r), h, reason: 'setup: staging the review must not move the hash (docs/reviews/** is excluded)');
  return h;
}

/// A sync whose docs conflict the human resolved, whose catastrophic file the human then EDITED, and
/// which still carries one catastrophic file nobody touched (so the staged set is wider than the
/// graded set). Gate installed. Staged: 3. Graded: kDocPath, kCatPath.
SyncScenario _humanEditedCatastrophic() {
  final sc = SyncScenario.build(
    installGate: true,
    featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
    mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n', kCatPath2: 'rolling v2\n'},
  );
  final r = sc.repo;
  expect(sc.mergeResult.exitCode, 1, reason: 'setup: the docs file must conflict');
  r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
  r.write(kCatPath, 'payment v2 EDITED BY HAND\n');
  r.stage([kDocPath, kCatPath]);
  expect(r.stagedPaths(), <String>[kDocPath, kCatPath2, kCatPath], reason: 'setup: three staged paths (git lists them sorted)');
  return sc;
}

/// A repository with one commit and the gate installed, NOT in a merge.
ScopeRepo _plainRepo({Map<String, String> files = const <String, String>{}}) {
  final r = ScopeRepo.create(prefix: 'merge_scope_gate_');
  r.write(kDocPath, 'line 1\nline 2\nline 3\n');
  r.write('own.txt', 'own\n');
  files.forEach(r.write);
  r.commitAll('base');
  r.installGate();
  return r;
}

void main() {
  group('scoped: the tier loop grades only what the merge added beyond main', () {
    test('G1 a sync that brought a SECURITY DEFINER migration and a catastrophic file, docs conflict resolved by hand: exit 0, scoped NOTE with the exact counts', () {
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {
          kDocPath: 'line 1\nMAIN\nline 3\n',
          kCatPath: 'payment v2\n',
          'supabase/migrations/200_innocuous_name.sql':
              'create function f() returns int language sql security definer as \$\$ select 1 \$\$;\n',
        },
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 1, reason: 'setup: the docs file must conflict');
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.stage([kDocPath]);
      expect(r.stagedPaths(), hasLength(3), reason: 'setup: main\'s two files are staged beside the resolved docs file');

      final res = r.gate();
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 3, graded: <String>[kDocPath])), reason: _out(res));
      expect(res.stdout, contains('PASS: max blast-radius of the graded set = feature'), reason: _out(res));
      expect(res.stdout, isNot(contains('SECURITY DEFINER content forces')), reason: 'main\'s migration is not graded: ${_out(res)}');
      expect(res.stderr, isNot(contains(_needsReview)));
    });

    test('G1b a clean --no-commit merge that brought catastrophic files and was not touched: exit 0, grading 0 paths', () {
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {'own.txt': 'own, feature edit\n'},
        mainFiles: {kCatPath: 'payment v2\n', kCatPath2: 'rolling v2\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0, reason: 'setup: a clean merge');
      expect(r.stagedPaths(), <String>[kCatPath2, kCatPath], reason: 'setup: both catastrophic files are staged');

      final res = r.gate();
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 2, graded: const <String>[])), reason: _out(res));
      expect(res.stdout, contains('PASS: max blast-radius of the graded set = feature'), reason: _out(res));
    });

    test('G2 control: MERGE_HEAD is an OLD main commit and main has changed the catastrophic file since: the result holds a version main no longer holds, exit 1', () {
      final r = ScopeRepo.create();
      r.write(kDocPath, 'line 1\nline 2\nline 3\n');
      r.write('own.txt', 'own\n');
      r.write(kCatPath, 'payment v1\n');
      r.commitAll('base');
      r.checkoutNew('feature');
      r.write('own.txt', 'own, feature edit\n');
      r.commitAll('feature work');
      r.checkout('main');
      r.write(kCatPath, 'payment v2\n');
      final old = r.commitAll('main 1');
      r.write(kCatPath, 'payment v3\n');
      final tip = r.commitAll('main 2');
      r.setOriginMain(tip);
      r.checkout('feature');
      r.installGate();
      final m = r.merge(old);
      expect(m.exitCode, 0, reason: 'setup: ${m.stdout}${m.stderr}');
      expect(File('${r.dir}/$kCatPath').readAsStringSync(), 'payment v2\n', reason: 'setup: the result holds the OLD main version');

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: tip, mergeHead: old, staged: 1, graded: <String>[kCatPath])), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    test('G3 the human edits a catastrophic file main brought: exit 1, the review is demanded', () {
      final sc = _humanEditedCatastrophic();
      final res = sc.repo.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 3, graded: <String>[kDocPath, kCatPath])), reason: _out(res));
      expect(res.stderr, contains('[Gate] FAIL: blast-radius=catastrophic $_needsReview at docs/reviews/${_fullDiffHash(sc.repo)}-review.md'), reason: _out(res));
      expect(res.stderr, contains('Branch sync: 2 graded path(s) (the review file is still named for the hash of the FULL staged diff):\n    $kDocPath\n    $kCatPath\n'), reason: _out(res));
      expect(res.stderr, isNot(contains(kCatPath2)), reason: 'the not-graded catastrophic file is not listed: ${_out(res)}');
    });

    test('G16 more than 20 graded paths: the NOTE cuts at 20 and the FAIL lists every one', () {
      final files = <String, String>{for (var i = 0; i < 22; i++) 'supabase/functions/verify-payment/f${i.toString().padLeft(2, '0')}.ts': 'v1 $i\n'};
      final sc = SyncScenario.build(
        installGate: true,
        baseFiles: files,
        featureFiles: {'own.txt': 'own, feature edit\n'},
        mainFiles: {for (final e in files.entries) e.key: 'v2 main\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0, reason: 'setup: a clean merge');
      for (final k in files.keys) {
        r.write(k, 'v2 main, edited by hand\n');
      }
      r.stage(files.keys.toList());

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains('grading 22 path(s)'), reason: _out(res));
      expect(res.stdout, contains('(+2 more)'), reason: _out(res));
      expect(res.stdout, isNot(contains('f21.ts')), reason: 'the NOTE stops at 20 names: ${_out(res)}');
      expect(res.stderr, contains('Branch sync: 22 graded path(s)'), reason: _out(res));
      for (final k in files.keys) {
        expect(res.stderr, contains('    $k\n'), reason: '$k is listed on the FAIL: ${_out(res)}');
      }
    });

    test('G18 a graded name with a line break is escaped on the NOTE and on the FAIL list (it cannot forge a line)', () {
      if (Platform.isWindows) return; // NTFS cannot hold a line break in a name
      const name = 'supabase/functions/verify-payment/a\nb.ts';
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {'own.txt': 'own, feature edit\n'},
        mainFiles: {name: 'v1\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0, reason: 'setup: a clean merge');
      r.write(name, 'v1, edited by hand\n');
      r.stage([name]);

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      const escaped = r'supabase/functions/verify-payment/a\x0ab.ts';
      expect(res.stdout, contains(': $escaped. Unmerged paths are graded.'), reason: _out(res));
      expect(res.stderr, contains('    $escaped\n'), reason: _out(res));
      expect(res.stderr, isNot(contains('a\nb.ts')), reason: 'no raw line break in the name: ${_out(res)}');
    });

    test('G15 the negative control: the SAME staged paths with no merge pending are graded and refused', () {
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {'own.txt': 'own, feature edit\n'},
        mainFiles: {kCatPath: 'payment v2\n', kCatPath2: 'rolling v2\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 0, reason: 'setup: a clean merge');
      final pending = r.gate();
      expect(pending.exitCode, 0, reason: 'with the sync pending nothing is graded: ${_out(pending)}');

      File('${r.dir}/.git/MERGE_HEAD').deleteSync();
      final plain = r.gate();
      expect(plain.exitCode, 1, reason: 'the staged index is unchanged; only the merge state is gone: ${_out(plain)}');
      expect(plain.stderr, contains(_needsReview), reason: _out(plain));
      expect(plain.stdout, isNot(contains('branch sync')), reason: _out(plain));
    });

    test('G3b the same with an accepted review named for the FULL staged diff (one path is not graded): exit 0', () {
      final sc = _humanEditedCatastrophic();
      final r = sc.repo;
      final h = _stageAcceptedReview(r);

      final res = r.gate();
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains('PASS: catastrophic commit has an accepted, STAGED review at docs/reviews/$h-review.md'), reason: _out(res));
      expect(r.stagedPaths(), contains(kCatPath2), reason: 'the hash covers the not-graded path too (the review is named for the FULL diff)');
    });

    test('G3c a staged review whose verdict is not "accepted" is refused and the graded paths are listed', () {
      final sc = _humanEditedCatastrophic();
      final r = sc.repo;
      final h = _fullDiffHash(r);
      r.write('docs/reviews/$h-review.md', '---\nverdict: pending\n---\n\nnot triaged\n');
      r.stage(['docs/reviews/$h-review.md']);

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains('verdict is not "accepted"'), reason: _out(res));
      // the staged review file itself is a graded path (it differs from HEAD and from main), beside the two edits
      expect(res.stderr, contains('Branch sync: 3 graded path(s)'), reason: _out(res));
      expect(res.stderr, contains('    $kCatPath\n'), reason: _out(res));
    });

    test('G4 the human adds SECURITY DEFINER content to a migration with an innocuous name: exit 1', () {
      const mig = 'supabase/migrations/200_innocuous_name.sql';
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', mig: 'select 1;\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 1, reason: 'setup: the docs file must conflict');
      r.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      r.write(mig, 'create function f() returns int language sql security definer as \$\$ select 1 \$\$;\n');
      r.stage([kDocPath, mig]);

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains('$mig: SECURITY DEFINER content forces catastrophic (path-tier was platform)'), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    test('G5 --warn-only on G3: exit 0, the failure is still reported', () {
      final sc = _humanEditedCatastrophic();
      final res = sc.repo.gate(args: const <String>['--warn-only']);
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stderr, contains('[Gate WARN] FAIL: blast-radius=catastrophic $_needsReview'), reason: _out(res));
      expect(res.stdout, contains('[Gate WARN] NOTE: branch sync of origin/main'), reason: _out(res));
    });

    test('G6 a `-s ours` sync stages nothing: exit 0, "SKIP: no staged changes" and no branch-sync NOTE', () {
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {'own.txt': 'own, feature edit\n'},
        mainFiles: {kCatPath: 'payment v2\n'},
      );
      final r = sc.repo;
      r.must(['merge', '--abort']);
      final ours = r.git(['merge', '--no-commit', '--no-ff', '-s', 'ours', 'refs/remotes/origin/main']);
      expect(ours.exitCode, 0, reason: 'setup: ${ours.stdout}${ours.stderr}');
      expect(File('${r.dir}/${r.must(['rev-parse', '--git-path', 'MERGE_HEAD'])}').existsSync(), isTrue, reason: 'setup: the merge is pending');
      expect(r.stagedPaths(), isEmpty, reason: 'setup: `-s ours` stages nothing');

      final res = r.gate();
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains('SKIP: no staged changes'), reason: _out(res));
      expect(res.stdout, isNot(contains('branch sync')), reason: _out(res));
      expect(res.stdout, isNot(contains('branch-sync')), reason: _out(res));
    });
  });

  group('G8 the environment a hook gives the gate', () {
    SyncScenario scenarioInPrimary() {
      final sc = SyncScenario.build(
        installGate: true,
        featureFiles: {kDocPath: 'line 1\nBRANCH\nline 3\n'},
        mainFiles: {kDocPath: 'line 1\nMAIN\nline 3\n', kCatPath: 'payment v2\n'},
      );
      expect(sc.mergeResult.exitCode, 1, reason: 'setup: the docs file must conflict');
      sc.repo.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      sc.repo.stage([kDocPath]);
      return sc;
    }

    const hookVars = <String>{'GIT_DIR', 'GIT_INDEX_FILE'};

    test('G8a a pending merge in a LINKED worktree with GIT_DIR and an absolute GIT_INDEX_FILE exported: the exact scoped NOTE, no fallback', () {
      final r = ScopeRepo.create();
      r.write(kDocPath, 'line 1\nline 2\nline 3\n');
      r.write('own.txt', 'own\n');
      r.commitAll('base');
      r.checkoutNew('feature');
      r.write(kDocPath, 'line 1\nBRANCH\nline 3\n');
      r.commitAll('feature work');
      r.checkout('main');
      r.write(kDocPath, 'line 1\nMAIN\nline 3\n');
      r.write(kCatPath, 'payment v2\n');
      final main = r.commitAll('main work');
      r.setOriginMain(main);
      // the primary stays on `main`; `feature` lives in the linked worktree
      final wt = r.linkedWorktree('wt', 'feature');
      wt.installGate();
      final m = wt.merge('refs/remotes/origin/main');
      expect(m.exitCode, 1, reason: 'setup: the docs file must conflict: ${m.stdout}${m.stderr}');
      wt.write(kDocPath, 'line 1\nBOTH\nline 3\n');
      wt.stage([kDocPath]);
      final gitDir = wt.must(['rev-parse', '--absolute-git-dir']);
      expect(gitDir, contains('/worktrees/'), reason: 'setup: a linked worktree has its own git dir');
      expect(File('$gitDir/MERGE_HEAD').existsSync(), isTrue, reason: 'setup: the merge is pending in the linked git dir');

      final res = wt.gate(extraEnv: {'GIT_DIR': gitDir, 'GIT_INDEX_FILE': '$gitDir/index'}, extraAllow: hookVars);
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: main, mergeHead: main, staged: 2, graded: <String>[kDocPath])), reason: _out(res));
      expect(res.stdout, isNot(contains('scoping not applied')), reason: _out(res));
    });

    test('G8b the primary worktree with the relative GIT_INDEX_FILE=.git/index a pre-commit hook sets', () {
      final sc = scenarioInPrimary();
      final res = sc.repo.gate(extraEnv: {'GIT_INDEX_FILE': '.git/index'}, extraAllow: hookVars);
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 2, graded: <String>[kDocPath])), reason: _out(res));
      expect(res.stdout, isNot(contains('scoping not applied')), reason: _out(res));
    });

    test('G8c an alternate GIT_INDEX_FILE whose graded result differs from the default index\'s: the gate follows the alternate', () {
      final sc = scenarioInPrimary();
      final r = sc.repo;
      final alt = '${r.root.path}/alt-index';
      File('${r.dir}/.git/index').copySync(alt);
      r.write(kCatPath, 'payment v2 EDITED BY HAND\n');
      r.must(['add', '--', kCatPath], extraEnv: {'GIT_INDEX_FILE': alt}, extraAllow: hookVars);

      final def = r.gate();
      expect(def.exitCode, 0, reason: 'the default index grades only the docs file: ${_out(def)}');
      expect(def.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 2, graded: <String>[kDocPath])), reason: _out(def));

      final res = r.gate(extraEnv: {'GIT_INDEX_FILE': alt}, extraAllow: hookVars);
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 2, graded: <String>[kDocPath, kCatPath])), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });
  });

  group('G14 and the fail-closed paths: today\'s behavior, said out loud', () {
    test('G14 an unresolved conflict in a catastrophic file is graded and the NOTE says so', () {
      final sc = SyncScenario.build(
        installGate: true,
        baseFiles: {kCatPath: 'a\nb\nc\n'},
        featureFiles: {kCatPath: 'a\nBRANCH\nc\n'},
        mainFiles: {kCatPath: 'a\nMAIN\nc\n'},
      );
      final r = sc.repo;
      expect(sc.mergeResult.exitCode, 1, reason: 'setup: the catastrophic file must conflict');
      expect(r.stages(kCatPath), <int>[1, 2, 3], reason: 'setup: unresolved');

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_scopedNote(tip: sc.mainSha, mergeHead: sc.mainSha, staged: 1, graded: <String>[kCatPath])), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    ScopeRepo anotherBranchMerge({required bool withOriginMain}) {
      final r = ScopeRepo.create();
      r.write(kDocPath, 'line 1\nline 2\nline 3\n');
      r.write('own.txt', 'own\n');
      final base = r.commitAll('base');
      r.checkoutNew('feature');
      r.write('own.txt', 'own, feature edit\n');
      r.commitAll('feature work');
      r.checkout('main');
      r.write(kDocPath, 'line 1\nMAIN\nline 3\n');
      final main = r.commitAll('main work');
      if (withOriginMain) r.setOriginMain(main);
      r.checkoutNew('other', from: base);
      r.write(kCatPath, 'payment v2\n');
      r.commitAll('other branch work');
      r.checkout('feature');
      r.installGate();
      final m = r.git(['merge', '--no-commit', '--no-ff', '-s', 'ort', 'other']);
      expect(m.exitCode, 0, reason: 'setup: ${m.stdout}${m.stderr}');
      expect(r.stagedPaths(), <String>[kCatPath], reason: 'setup: the other branch\'s catastrophic file is the only staged path');
      return r;
    }

    test('G11 a pending merge of ANOTHER feature branch that carries a catastrophic path: the fallback NOTE with its exact reason, exit 1', () {
      final r = anotherBranchMerge(withOriginMain: true);
      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_fallbackNote('MERGE_HEAD is not an ancestor of origin/main (or the history is shallow)', 1)), reason: _out(res));
      expect(res.stdout, isNot(contains('branch sync of origin/main')), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    test('G12 no refs/remotes/origin/main at all: the fallback NOTE with its exact reason, exit 1', () {
      final r = anotherBranchMerge(withOriginMain: false);
      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_fallbackNote('refs/remotes/origin/main is missing or not a commit', 1)), reason: _out(res));
      expect(res.stdout, isNot(contains('branch sync of origin/main')), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    test('G13 an unreadable MERGE_HEAD (a directory): the fallback NOTE says MERGE_HEAD unreadable, exit 1', () {
      final r = _plainRepo();
      r.write(kCatPath, 'payment v2\n');
      r.stage([kCatPath]);
      Directory('${r.dir}/.git/MERGE_HEAD').createSync();

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stdout, contains(_fallbackNote('MERGE_HEAD unreadable', 1)), reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });
  });

  group('not a merge: the staged-path read the gate does for every commit', () {
    test('G10 an ordinary commit prints no branch-sync NOTE', () {
      final r = _plainRepo();
      r.write(kDocPath, 'line 1\nline 2 edited\nline 3\n');
      r.stage([kDocPath]);

      final res = r.gate();
      expect(res.exitCode, 0, reason: _out(res));
      expect(res.stdout, contains('PASS: max blast-radius = feature'), reason: _out(res));
      expect(res.stdout, isNot(contains('branch sync')), reason: _out(res));
      expect(res.stdout, isNot(contains('branch-sync')), reason: _out(res));
    });

    test('G7a a rename OUT of a catastrophic directory lists its source: exit 1', () {
      final r = _plainRepo(files: {kCatPath: 'payment line 1\npayment line 2\npayment line 3\npayment line 4\npayment line 5\n'});
      r.must(['mv', kCatPath, 'docs/moved_payment.md']);
      final plain = r.must(['diff', '--cached', '--name-only']);
      expect(plain, 'docs/moved_payment.md', reason: 'setup: git\'s default read pairs the rename and names only the destination');

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    test('G7b a non-ASCII name under a catastrophic glob is not C-quoted out of it: exit 1', () {
      final r = _plainRepo();
      commitFileNamed(r.dir, 'supabase/functions/verify-payment/h${String.fromCharCode(0xe9)}llo.ts', 'feat: a name with an accent');
      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
    });

    for (final lt in <(String, String)>[('LF', '\n'), ('U+2028', String.fromCharCode(0x2028))]) {
      test('G7c a name holding a line terminator (${lt.$1}) under a catastrophic glob still matches it: exit 1', () {
        final r = _plainRepo();
        commitFileNamed(r.dir, 'supabase/functions/verify-payment/a${lt.$2}b.ts', 'feat: a name with a line break');
        final res = r.gate();
        expect(res.exitCode, 1, reason: _out(res));
        expect(res.stderr, contains(_needsReview), reason: _out(res));
      });
    }

    test('G7d a name that is not valid UTF-8, the ONLY staged path under a feature-tier directory: exit 1 with the "not valid UTF-8" text, never "no staged changes" or a pass', () {
      final r = _plainRepo();
      commitFileNamed(r.dir, 'docs/${String.fromCharCodes(const <int>[0xff, 0xfe])}.md', 'docs: a name that is not UTF-8', rawNames: true);
      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains('not valid UTF-8'), reason: _out(res));
      expect(res.stderr, isNot(contains(_needsReview)), reason: _out(res));
      expect(res.stdout, isNot(contains('SKIP: no staged changes')), reason: _out(res));
      expect(res.stdout, isNot(contains('PASS')), reason: _out(res));
    });

    test('G7e the same invalid name under a catastrophic directory: also exit 1 with the "not valid UTF-8" text', () {
      final r = _plainRepo();
      commitFileNamed(r.dir, 'supabase/functions/verify-payment/${String.fromCharCodes(const <int>[0xff, 0xfe])}.ts', 'feat: a name that is not UTF-8', rawNames: true);
      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains('not valid UTF-8'), reason: _out(res));
      expect(res.stderr, isNot(contains(_needsReview)), reason: _out(res));
    });

    test('G7 MIRROR a valid non-ASCII name under a feature-tier directory still passes', () {
      final r = _plainRepo();
      commitFileNamed(r.dir, 'docs/r${String.fromCharCode(0xe9)}sum${String.fromCharCode(0xe9)}.md', 'docs: a note');
      final res = r.gate();
      expect(res.exitCode, 0, reason: 'strictness applies to INVALID bytes only: ${_out(res)}');
      expect(res.stdout, contains('PASS: max blast-radius = feature'), reason: _out(res));
    });

    test('G9 a staged gitlink under a catastrophic glob is seen although .gitmodules says ignore = all: exit 1', () {
      final r = ScopeRepo.create(prefix: 'merge_scope_gate_');
      r.write(kDocPath, 'line 1\nline 2\nline 3\n');
      r.write('.gitmodules',
          '[submodule "payment-sub"]\n\tpath = supabase/functions/verify-payment/sub\n\turl = https://example.invalid/sub.git\n\tignore = all\n');
      final head = r.commitAll('base');
      r.installGate();
      r.must(['update-index', '--add', '--cacheinfo', '160000,$head,supabase/functions/verify-payment/sub']);
      expect(r.git(['diff', '--cached', '--name-only']).stdout, '', reason: 'setup: git\'s default read hides the gitlink under ignore = all');

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains(_needsReview), reason: _out(res));
      // The demanded review is named for a diff that CONTAINS the gitlink, not for the empty diff
      // (e69de29bb2d1 is the hash of nothing: the same name for every gitlink value).
      final h = _fullDiffHash(r);
      expect(h, isNot('e69de29bb2d1'), reason: 'setup: the hash recipe sees the gitlink');
      expect(res.stderr, contains('docs/reviews/$h-review.md'), reason: _out(res));
    });

    test('G17 git cannot list the staged paths (a corrupt index): FAIL, never "no staged changes"; --warn-only still exits 0', () {
      final r = _plainRepo();
      r.write(kCatPath, 'payment v2\n');
      r.stage([kCatPath]);
      File('${r.dir}/.git/index').writeAsStringSync('garbage');
      expect(r.git(['diff', '--cached', '--name-only', '-z']).exitCode, isNot(0), reason: 'setup: git itself fails on this index');

      final res = r.gate();
      expect(res.exitCode, 1, reason: _out(res));
      expect(res.stderr, contains('could not read the staged paths'), reason: _out(res));
      expect(res.stdout, isNot(contains('SKIP: no staged changes')), reason: _out(res));

      final warn = r.gate(args: const <String>['--warn-only']);
      expect(warn.exitCode, 0, reason: _out(warn));
      expect(warn.stderr, contains('[Gate WARN] FAIL: could not read the staged paths'), reason: _out(warn));
    });
  });
}
