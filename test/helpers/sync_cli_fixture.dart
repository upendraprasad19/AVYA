// test/helpers/sync_cli_fixture.dart
//
// Throwaway repositories for the end-to-end tests of scripts/sync_with_main.dart and its wrapper (landing C2,
// docs/plans/sync-resolver.md section 5). Built on [ScopeRepo] (hermetic git config, user identity, spawn
// scrub) plus a bare `origin` the CLI really fetches from.
//
// The fixture repo carries NO copy of the scripts (the CLI is run from the repository under test, with the
// fixture as its working directory); `scripts/` is excluded from `git add -A` by [ScopeRepo], so the stubs the
// scenarios drop there (`scripts/safe_commit.sh`, `scripts/build_gate_index.dart`) stay untracked.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/no_conflict_markers_lib.dart';
import 'merge_scope_repo.dart';
import 'spawn.dart';
import 'sync_resolver_fixtures.dart';

Map<String, String> defaultFiles() => <String, String>{
      'docs/audit/open_issues.md': board([oi(1), oi(2)]),
      '.claude/skills/debugging/bug-classes.md': '# Bug classes\n\n${bugClass('2.1')}',
      'docs/audit/gate_test_ledger.yaml': '# header\n\n${ledgerRec('check_a')}',
      'docs/audit/GATE_INDEX.md': 'index v0\n',
      '.claude/skills/code-review/tuning-history.md': '# archive\n\nentry a\n',
      'lib/a.dart': 'line1\nline2\nline3\n',
      'README.md': 'readme\n',
    };

/// Absolute path of an executable on the test machine's PATH.
String whichTool(String name) {
  final r = runSpawn('which', [name], why: 'sync_cli_fixture: which $name', stdoutEncoding: utf8);
  expect(r.exitCode, 0, reason: 'the test machine has no `$name`');
  return (r.stdout as String).trim();
}

class SyncCli {
  SyncCli._(this.repo, this.origin, this.srcRoot);

  final ScopeRepo repo;

  /// The bare repository `origin` points at.
  final String origin;

  /// The repository under test (where `scripts/sync_with_main.dart` lives).
  final String srcRoot;

  String get dir => repo.dir;
  String get cli => '$srcRoot/scripts/sync_with_main.dart';
  String get wrapper => '$srcRoot/scripts/sync_with_main.sh';

  /// A fixture on branch `feature`, cut from `main` at `base`, with `origin/main` fetched.
  /// Call inside a test or setUp (the teardown is registered on the current test).
  static SyncCli create({Map<String, String>? files}) {
    final repo = ScopeRepo.create(prefix: 'sync_cli_');
    final srcRoot = Directory.current.path;
    (files ?? defaultFiles()).forEach(repo.write);
    repo.commitAll('base');
    final origin = '${repo.root.path}/origin.git';
    Directory(origin).createSync();
    final init = runSpawn('git', ['init', '-q', '--bare', origin],
        why: 'sync_cli_fixture: bare origin', extraEnv: repo.env, allowControl: ScopeRepo.allowControl, stdoutEncoding: utf8);
    expect(init.exitCode, 0);
    repo.must(['remote', 'add', 'origin', origin]);
    repo.must(['push', '-q', 'origin', 'main']);
    repo.must(['fetch', '-q', 'origin']);
    repo.checkoutNew('feature');
    return SyncCli._(repo, origin, srcRoot);
  }

  /// Commits [files] on `main` (null deletes), publishes it to origin and returns to `feature`.
  String mainCommit(Map<String, String?> files, {String msg = 'main work'}) {
    repo.checkout('main');
    _apply(files);
    final sha = repo.commitAll(msg);
    repo.must(['push', '-q', 'origin', 'main']);
    repo.checkout('feature');
    return sha;
  }

  String featureCommit(Map<String, String?> files, {String msg = 'feature work'}) {
    _apply(files);
    return repo.commitAll(msg);
  }

  void _apply(Map<String, String?> files) => files.forEach((k, v) {
        if (v == null) {
          repo.must(['rm', '-q', '-f', '--', k]);
        } else {
          repo.write(k, v);
        }
      });

  /// Runs the CLI (default) or the wrapper with [args]. [path] replaces PATH; [extra] adds variables.
  ProcessResult run(
    List<String> args, {
    String? cwd,
    String? path,
    Map<String, String> extra = const {},
    Set<String> extraAllow = const {},
    bool viaWrapper = false,
  }) {
    final exe = viaWrapper ? 'sh' : dartBin();
    final argv = viaWrapper ? [wrapper, ...args] : [cli, ...args];
    return runSpawn(
      exe,
      argv,
      why: 'sync_with_main ${args.join(' ')}',
      workingDirectory: cwd ?? dir,
      extraEnv: {...repo.env, 'PATH': ?path, ...extra},
      allowControl: {...ScopeRepo.allowControl, ...extraAllow},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// The paths with unmerged entries.
  List<String> unmerged() {
    final out = repo.must(['ls-files', '-u']);
    return {for (final l in out.split('\n')) if (l.isNotEmpty) l.split('\t').last}.toList()..sort();
  }

  /// The stage numbers of [path] in the index.
  List<int> stagesOf(String path) => repo.stages(path);

  String get gitDir => repo.must(['rev-parse', '--path-format=absolute', '--git-dir']);

  bool get mergePending => File('$gitDir/MERGE_HEAD').existsSync();

  String read(String rel) => File('$dir/$rel').readAsStringSync();

  List<int> readBytes(String rel) => File('$dir/$rel').readAsBytesSync();

  bool hasMarkers(String rel) => conflictsInFile(rel, read(rel)).isNotEmpty;

  List<String> staged() => repo.must(['diff', '--cached', '--name-only']).split('\n').where((l) => l.isNotEmpty).toList();

  String get head => repo.head();

  String get tip => repo.must(['rev-parse', 'refs/remotes/origin/main']);

  /// Starts the merge by hand, the way a developer would (`--no-commit --no-ff` of the tip).
  ProcessResult handMerge() => repo.git(['merge', '--no-commit', '--no-ff', 'refs/remotes/origin/main']);

  /// Everything a refusal must leave untouched.
  String snapshot() => <String>[
        repo.must(['rev-parse', 'HEAD']),
        repo.must(['ls-files', '-s']),
        '${repo.git(['status', '--porcelain=v1', '--untracked-files=no']).stdout}',
        '${repo.git(['diff']).stdout}',
        '$mergePending',
      ].join('\n--\n');

  /// A directory with executable stubs written from [scripts] (name -> sh body) followed by `exec real`
  /// for the tool named like the stub. Returns the PATH to use: the stub directory in front of the machine's PATH.
  String stubPath(Map<String, String> scripts) {
    final d = Directory('${repo.root.path}/stubbin')..createSync(recursive: true);
    scripts.forEach((name, body) {
      final real = whichTool(name);
      final f = File('${d.path}/$name');
      f.writeAsStringSync('#!/bin/sh\n$body\nexec "$real" "\$@"\n');
      runSpawn('chmod', ['+x', f.path], why: 'sync_cli_fixture: chmod stub');
    });
    return '${d.path}:${Platform.environment['PATH']}';
  }

  /// A PATH of symlinks to exactly [tools] (and nothing else).
  String minimalPath(List<String> tools) {
    final d = Directory('${repo.root.path}/minbin${_seq++}')..createSync(recursive: true);
    for (final t in tools) {
      Link('${d.path}/$t').createSync(whichTool(t));
    }
    return d.path;
  }

  static int _seq = 0;
}

/// The last non-empty line of [stdout].
String lastLine(String stdout) {
  final ls = stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();
  return ls.isEmpty ? '' : ls.last;
}

/// Asserts exit code and the `result:` protocol: ONE `result:` line, and it is the last one.
void expectResult(ProcessResult r, int code, String result) {
  final out = r.stdout as String;
  expect(r.exitCode, code, reason: 'exit code\n$out\n${r.stderr}');
  expect(lastLine(out), 'result: $result', reason: out);
  expect(RegExp(r'^result: ', multiLine: true).allMatches(out).length, 1, reason: 'exactly one result line\n$out');
}

String stdoutOf(ProcessResult r) => r.stdout as String;

/// Bytes of [text] (UTF-8).
List<int> bytes(String text) => utf8.encode(text);
