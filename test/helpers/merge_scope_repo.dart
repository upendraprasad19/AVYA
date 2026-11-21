// test/helpers/merge_scope_repo.dart
//
// Temp git repositories for the merge-scope tests (landing C1, docs/plans/sync-merge-scope.md):
// a branch that syncs origin/main, built with real git, so scripts/merge_scope_lib.dart and the real
// scripts/check_code_review_pass_exists.dart run against a REAL pending merge.
//
// ISOLATION. Every git command goes through [runSpawn] (the canonical control-variable scrub, so a
// `GIT_DIR` / `GIT_INDEX_FILE` exported by the pre-commit hook this suite may run under cannot reach
// the fixture; see the 2026-07-18 incident in test/contracts/review_gate_staged_content_not_working_tree_test.dart)
// and with `GIT_CONFIG_NOSYSTEM=1` plus a `GIT_CONFIG_GLOBAL` that points at an EMPTY file, so a
// developer's global `diff.*`, `merge.*`, `core.autocrlf`, `core.hooksPath` or `init.templateDir`
// cannot reach a fixture or mask a mutant. The repo-local config pins `user.*`, `commit.gpgsign=false`
// and `diff.renames=true` (a scenario about rename handling must not depend on the machine's default).
//
// The fixture never uses `git commit` through the Bash tool; this file runs inside `flutter test`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/merge_scope_lib.dart';
import 'script_closure_fixture.dart';
import 'spawn.dart';

/// A catastrophic-tier path of docs/blast_radius.yaml (payment).
const String kCatPath = 'supabase/functions/verify-payment/index.ts';

/// A second catastrophic-tier path (the rolling-context cron).
const String kCatPath2 = 'supabase/functions/rolling-context/index.ts';

/// A feature-tier path.
const String kDocPath = 'docs/notes.md';

class ScopeRepo {
  ScopeRepo._(this.dir, this.configFile, this.root);

  /// The worktree directory git runs in.
  final String dir;

  /// The empty global config file every git command is pointed at.
  final String configFile;

  /// The temp directory that owns everything (deleted by [dispose] on the main repo only).
  final Directory root;

  /// A fresh repository on branch `main`, `refs/remotes/origin/main` not yet set.
  static ScopeRepo create({String prefix = 'merge_scope_'}) {
    final root = Directory.systemTemp.createTempSync(prefix);
    final cfg = File('${root.path}/empty.gitconfig')..writeAsStringSync('');
    final dir = Directory('${root.path}/repo')..createSync();
    final repo = ScopeRepo._(dir.path, cfg.path, root);
    repo.must(['init', '-q', '-b', 'main']);
    repo.must(['config', 'user.email', 'test@example.com']);
    repo.must(['config', 'user.name', 'Test']);
    repo.must(['config', 'commit.gpgsign', 'false']);
    repo.must(['config', 'diff.renames', 'true']);
    // The gate's closure and the registry are copied in untracked: keep `git add -A` away from them.
    final exclude = File('${repo.dir}/.git/info/exclude');
    exclude.parent.createSync(recursive: true);
    exclude.writeAsStringSync('/scripts/\n/docs/blast_radius.yaml\n/.rec\n');
    addTearDown(repo.dispose);
    return repo;
  }

  /// The environment every command carries (all `GIT_*` names are control variables, hence [allowControl]).
  Map<String, String> get env => <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': configFile,
      };

  static const Set<String> allowControl = <String>{'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'};

  ProcessResult git(
    List<String> args, {
    Map<String, String> extraEnv = const <String, String>{},
    Set<String> extraAllow = const <String>{},
    Encoding? stdoutEncoding = systemEncoding,
    String? cwd,
  }) =>
      runSpawn(
        'git',
        args,
        why: 'merge_scope_repo: git ${args.join(' ')}',
        workingDirectory: cwd ?? dir,
        extraEnv: <String, String>{...env, ...extraEnv},
        allowControl: <String>{...allowControl, ...extraAllow},
        stdoutEncoding: stdoutEncoding,
      );

  /// Runs git and requires exit 0; returns trimmed stdout.
  String must(List<String> args, {Map<String, String> extraEnv = const <String, String>{}, Set<String> extraAllow = const <String>{}}) {
    final r = git(args, extraEnv: extraEnv, extraAllow: extraAllow);
    expect(r.exitCode, 0, reason: 'setup: git ${args.join(' ')}: ${r.stdout}${r.stderr}');
    return (r.stdout as String).trim();
  }

  void write(String rel, String content) {
    final f = File('$dir/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  void writeBytes(String rel, List<int> bytes) {
    final f = File('$dir/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  void remove(String rel) => File('$dir/$rel').deleteSync();

  void stageAll() => must(['add', '-A']);

  void stage(List<String> rels) => must(['add', '--', ...rels]);

  /// Stages everything and commits; returns the new HEAD.
  String commitAll(String msg) {
    stageAll();
    must(['commit', '-q', '--allow-empty', '-m', msg]);
    return must(['rev-parse', 'HEAD']);
  }

  String head() => must(['rev-parse', 'HEAD']);

  void checkoutNew(String branch, {String? from}) => must(['checkout', '-q', '-b', branch, ?from]);

  void checkout(String branch) => must(['checkout', '-q', branch]);

  /// Points `refs/remotes/origin/main` at [rev].
  void setOriginMain(String rev) => must(['update-ref', 'refs/remotes/origin/main', rev]);

  /// `git merge --no-commit --no-ff -s ort <rev>` with `merge.directoryRenames=conflict` pinned (git's
  /// default differs between versions); exit 0 clean, 1 conflicted.
  ProcessResult merge(String rev, {List<String> extra = const <String>[]}) => git([
        '-c',
        'merge.directoryRenames=conflict',
        'merge',
        '--no-commit',
        '--no-ff',
        '-s',
        'ort',
        ...extra,
        rev,
      ]);

  /// Commits the INDEX as it is (no `git add -A`, which would stage the deletion of a gitlink whose
  /// directory does not exist) with plumbing: write-tree, commit-tree, update-ref.
  String commitIndex(String msg) {
    final tree = must(['write-tree']);
    final parent = git(['rev-parse', '-q', '--verify', 'HEAD']);
    final args = ['commit-tree', tree, if (parent.exitCode == 0) ...['-p', (parent.stdout as String).trim()], '-m', msg];
    final sha = must(args);
    must(['update-ref', 'HEAD', sha]);
    return sha;
  }

  /// The stage numbers the index holds for [rel] (e.g. `[1, 2, 3]` for a conflict, `[0]` resolved).
  List<int> stages(String rel) {
    final out = must(['ls-files', '-s', '--', rel]);
    return out.isEmpty
        ? <int>[]
        : out.split('\n').map((l) => int.parse(l.split(RegExp(r'\s+'))[2])).toList();
  }

  /// A [GitRun] that runs real git in [dir] (or [cwd]).
  GitRun runner({String? cwd, Map<String, String> extraEnv = const <String, String>{}, Set<String> extraAllow = const <String>{}}) =>
      (List<String> args) {
        final r = git(args, cwd: cwd, extraEnv: extraEnv, extraAllow: extraAllow, stdoutEncoding: null);
        return (exitCode: r.exitCode, stdout: r.stdout as List<int>);
      };

  /// Reads the MERGE_HEAD file at [path] relative to [dir] (or absolute); null when absent.
  ReadMergeHead readMergeHead({String? cwd}) => (String path) {
        final f = File(path.startsWith('/') || path.contains(':') ? path : '${cwd ?? dir}/$path');
        try {
          return f.readAsStringSync();
        } on PathNotFoundException {
          return null;
        }
      };

  /// The gate's own staged list (porcelain, hardened).
  List<String> stagedPaths({String? cwd, Map<String, String> extraEnv = const <String, String>{}, Set<String> extraAllow = const <String>{}}) {
    final r = git(stagedPathsArgv, cwd: cwd, extraEnv: extraEnv, extraAllow: extraAllow, stdoutEncoding: null);
    expect(r.exitCode, 0, reason: 'setup: staged list: ${r.stderr}');
    final parsed = parseNulPaths(r.stdout as List<int>);
    expect(parsed, isNotNull, reason: 'setup: staged list not valid UTF-8');
    return parsed!;
  }

  /// [computeMergeScope] against this repo's real git and real MERGE_HEAD file.
  MergeScope scope({String? cwd, Map<String, String> extraEnv = const <String, String>{}, Set<String> extraAllow = const <String>{}}) =>
      computeMergeScope(
        runner(cwd: cwd, extraEnv: extraEnv, extraAllow: extraAllow),
        readMergeHead: readMergeHead(cwd: cwd),
        staged: stagedPaths(cwd: cwd, extraEnv: extraEnv, extraAllow: extraAllow),
      );

  /// A linked worktree of this repository checked out on [branch]; shares the config file.
  ScopeRepo linkedWorktree(String name, String branch) {
    final path = '${root.path}/$name';
    must(['worktree', 'add', '-q', path, branch]);
    return ScopeRepo._(path, configFile, root);
  }

  /// Copies the gate's import closure, the registry and (optionally) nothing else into [dir], untracked
  /// and excluded from `git add -A`, so the REAL gate can be spawned with the repo as its working directory.
  void installGate({String? repoRoot}) {
    final rr = repoRoot ?? Directory.current.path;
    copyScriptClosure(rr, dir, const ['scripts/check_code_review_pass_exists.dart']);
    final reg = File('$dir/docs/blast_radius.yaml');
    reg.parent.createSync(recursive: true);
    File('$rr/docs/blast_radius.yaml').copySync(reg.path);
  }

  /// Spawns the real gate in [cwd] (default [dir]); returns the result with text output.
  ProcessResult gate({
    List<String> args = const <String>[],
    String? cwd,
    Map<String, String> extraEnv = const <String, String>{},
    Set<String> extraAllow = const <String>{},
  }) =>
      runSpawn(
        dartBin(),
        ['scripts/check_code_review_pass_exists.dart', ...args],
        why: 'merge_scope_repo: the real gate in ${cwd ?? dir}',
        workingDirectory: cwd ?? dir,
        extraEnv: <String, String>{...env, ...extraEnv},
        allowControl: <String>{...allowControl, ...extraAllow},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  void dispose() {
    if (root.existsSync()) {
      // The linked worktrees live under root too.
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// The standard branch-sync scenario, up to the pending merge:
///
///  - `base` has [kDocPath], `own.txt` and [baseFiles];
///  - `feature` (branched from base) gets [featureFiles] and commits;
///  - `main` gets [mainFiles] and commits, and `refs/remotes/origin/main` points at it;
///  - back on `feature`, `git merge --no-commit --no-ff -s ort refs/remotes/origin/main` is started.
///
/// Returns the repo with the merge pending (conflicted or not). A `null` value in a map deletes the file.
class SyncScenario {
  SyncScenario(this.repo, this.mergeResult, {required this.baseSha, required this.mainSha, required this.featureSha});
  final ScopeRepo repo;
  final ProcessResult mergeResult;
  final String baseSha;
  final String mainSha;
  final String featureSha;

  static SyncScenario build({
    Map<String, String> baseFiles = const <String, String>{},
    Map<String, String?> featureFiles = const <String, String?>{},
    Map<String, String?> mainFiles = const <String, String?>{},
    bool installGate = false,
    String? mergeRev,
    List<String> mergeExtra = const <String>[],
  }) {
    final repo = ScopeRepo.create();
    repo.write(kDocPath, 'line 1\nline 2\nline 3\n');
    repo.write('own.txt', 'own\n');
    baseFiles.forEach(repo.write);
    final base = repo.commitAll('base');
    repo.checkoutNew('feature');
    void apply(Map<String, String?> files) => files.forEach((k, v) {
          if (v == null) {
            repo.remove(k);
          } else {
            repo.write(k, v);
          }
        });
    apply(featureFiles);
    final feature = repo.commitAll('feature work');
    repo.checkout('main');
    apply(mainFiles);
    final main = repo.commitAll('main work');
    repo.setOriginMain(main);
    repo.checkout('feature');
    if (installGate) repo.installGate();
    final merged = repo.merge(mergeRev ?? 'refs/remotes/origin/main', extra: mergeExtra);
    return SyncScenario(repo, merged, baseSha: base, mainSha: main, featureSha: feature);
  }
}

/// Fails a scenario that returns the catch-all reason by accident (a throwing bug would otherwise
/// read as a conservative `Fallback`).
void expectFallback(MergeScope scope, String reason) {
  expect(scope, isA<Fallback>(), reason: 'expected a Fallback, got $scope');
  expect((scope as Fallback).reason, reason);
}

/// The sorted graded paths of a [Scoped] result.
List<String> gradedOf(MergeScope scope) {
  expect(scope, isA<Scoped>(), reason: 'expected Scoped, got ${scope is Fallback ? 'Fallback(${scope.reason})' : scope}');
  return (scope as Scoped).paths;
}

/// "mode oid" entries of the index (stage 0) by path, from `ls-files -s -z`.
Map<String, String> indexEntries(ScopeRepo r) {
  final out = r.git(['ls-files', '-s', '-z'], stdoutEncoding: null);
  expect(out.exitCode, 0);
  final m = <String, String>{};
  for (final rec in splitNulBytes(out.stdout as List<int>)) {
    final tab = rec.indexOf('\t');
    final head = rec.substring(0, tab).split(' ');
    if (head[2] == '0') m[rec.substring(tab + 1)] = '${head[0]} ${head[1]}';
  }
  return m;
}

/// "mode oid" entries of a tree by path, from `ls-tree -r -z`.
Map<String, String> treeEntries(ScopeRepo r, String treeish) {
  final out = r.git(['ls-tree', '-r', '-z', treeish], stdoutEncoding: null);
  expect(out.exitCode, 0);
  final m = <String, String>{};
  for (final rec in splitNulBytes(out.stdout as List<int>)) {
    final tab = rec.indexOf('\t');
    final head = rec.substring(0, tab).split(' ');
    m[rec.substring(tab + 1)] = '${head[0]} ${head[2]}';
  }
  return m;
}

/// The graded set by an INDEPENDENT reimplementation of the rule, from `ls-files -s` and `ls-tree -r`
/// (byte-string paths, like the lib): the staged paths whose index entry differs from HEAD's and from
/// the tip's. Used as the exact-equality oracle, never as an implementation of the lib.
Set<String> oracleGraded(ScopeRepo r) {
  final idx = indexEntries(r);
  final head = treeEntries(r, 'HEAD');
  final tip = treeEntries(r, 'refs/remotes/origin/main');
  final names = <String>{...idx.keys, ...head.keys};
  final graded = <String>{};
  for (final p in names) {
    final a = idx[p];
    if (a == head[p]) continue; // nothing new: not even staged
    if (a == tip[p]) continue;
    graded.add(p);
  }
  return graded;
}

/// Every blob object id of the tree [treeish] (any path).
Set<String> blobIds(ScopeRepo r, String treeish) => treeEntries(r, treeish).values.map((e) => e.split(' ')[1]).toSet();
