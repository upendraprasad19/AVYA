@Timeout(Duration(minutes: 10))
library;

// test/scripts/land_pr_replay_test.dart
//
// The plan-review-record replay of scripts/land_pr.dart (landing D, docs/plans/merge-train.md section 3.5) against the REAL gate
// `scripts/check_plan_review_record_exists.dart` in throwaway repositories. The gate's script closure and the real tier registry are
// tracked in the fixture with `git add -f` (ScopeRepo excludes /scripts/ and /docs/blast_radius.yaml from `git add -A`, and the gate reads
// the registry with `git show <rev>:docs/blast_radius.yaml`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/land_pr_fixture.dart';
import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';
import '../helpers/sync_cli_fixture.dart';

String out(ProcessResult r) => '${r.stdout}';

const String goodRecord = '''---
branch: feature
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/probe.md
---
''';

/// A fixture whose main (and feature, at its base) carries the gate closure and the registry.
LandFixture replayFixture({bool registry = true}) {
  final fx = LandFixture.create();
  final repo = fx.cli.repo;
  repo.checkout('main');
  copyScriptClosure(fx.cli.srcRoot, fx.dir, ['scripts/check_plan_review_record_exists.dart']);
  if (registry) {
    Directory('${fx.dir}/docs').createSync(recursive: true);
    File('${fx.cli.srcRoot}/docs/blast_radius.yaml').copySync('${fx.dir}/docs/blast_radius.yaml');
  }
  repo.must(['add', '-f', 'scripts', if (registry) 'docs/blast_radius.yaml']);
  repo.commitAll('add the gate closure');
  repo.must(['push', '-q', 'origin', 'main']);
  repo.checkout('feature');
  repo.must(['merge', '--ff-only', '-q', 'main']);
  repo.must(['push', '-q', 'origin', 'feature']);
  return fx;
}

ProcessResult realReplay(LandFixture fx, {Map<String, String> env = const {}, Set<String> allow = const {}}) =>
    runLand(fx, ['191', ...seamArgs(fx, recordGate: false)], env: env, allow: allow);

List<String> replayDirs(LandFixture fx) {
  final common = fx.cli.repo.must(['rev-parse', '--path-format=absolute', '--git-common-dir']);
  return Directory(common)
      .listSync()
      .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .where((n) => n.startsWith('land_pr_replay-'))
      .toList();
}

void main() {
  test('a platform-tier change with NO record: record-failed, exit 5, the gate FAIL line is printed, no merge', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'pubspec.yaml': 'name: probe\n'});
    final r = realReplay(fx);
    expectResult(r, 5, 'record-failed');
    expect(out(r), contains('gate!> [plan-review-record] FAIL'));
    expect(fx.calls, isNot(contains('merge')));
  });

  test('origin/main moving between the ancestry check and the replay (another session fetched): needs-human, never a replay on the wrong main, no merge', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'pubspec.yaml': 'name: probe\n'});
    fx.movesMain('pr-head', 1, fetchLocal: true);
    final r = realReplay(fx);
    expectResult(r, 1, 'needs-human');
    expect(out(r), contains('moved'));
    expect(fx.calls, isNot(contains('merge')));
  });

  test('the same change WITH a valid record and review file: merged, the gate passed on the merge commit', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'pubspec.yaml': 'name: probe\n', 'docs/plan-reviews/feature.md': goodRecord, 'docs/reviews/probe.md': 'verdict: accepted\n'});
    final r = realReplay(fx);
    expectResult(r, 0, 'merged');
    expect(out(r), contains('plan-review-record gate: PASS on the merge commit'));
    expect(out(r), contains('gate> [plan-review-record] PASS: every landing in'));
    expect(fx.calls, containsAllInOrder(['gh pr-head', 'merge']));
  });

  test('OI-483: dart walks UP, so the gate in <repo>/.git/<replay> reads <repo>/.dart_tool: a lost race there is retried, never a false record-failed on the first try', () {
    for (final off in [false, true]) {
      final fx = replayFixture();
      fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
      // After the last commit: ScopeRepo does not exclude .dart_tool, `add -A` would take an earlier one. Untracked, so
      // the dirty check does not see it. The CLI runs from srcRoot, so only the gate in the replay clone reads this file.
      File('${fx.dir}/.dart_tool/native_assets.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      final r = realReplay(fx, env: off ? const {'AVYA_DART_RUN_RETRY': '0'} : const {}, allow: const {'AVYA_DART_RUN_RETRY'});
      expectResult(r, 5, 'record-failed');
      expect(RegExp(r'\[dart-run-retry\]').allMatches('${r.stderr}').length, off ? 0 : 2, reason: '${r.stderr}');
      expect(out(r), contains('File not formatted as yaml'), reason: 'the gate died on the race, not on something else');
      expect(fx.calls, isNot(contains('merge')));
      expect(replayDirs(fx), isEmpty, reason: 'the scratch clone is still cleaned up');
    }
  });

  test('a docs-only change needs no record: merged', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    expectResult(realReplay(fx), 0, 'merged');
  });

  test('a record whose bpass_review file is prose without a `verdict: accepted` line (the #119/#124 class): record-failed', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'pubspec.yaml': 'name: probe\n', 'docs/plan-reviews/feature.md': goodRecord, 'docs/reviews/probe.md': 'The reviewer accepted it.\n'});
    final r = realReplay(fx);
    expectResult(r, 5, 'record-failed');
    expect(fx.calls, isNot(contains('merge')));
  });

  test('HEAD equal to main (a deduplicated single-parent commit, "0 merge(s)"): record-failed (kills a verdict that accepts any PASS)', () {
    final fx = replayFixture();
    final r = realReplay(fx);
    expectResult(r, 5, 'record-failed');
    expect(fx.calls, isNot(contains('merge')));
  });

  test('the registry missing from the repository (the gate cannot tier the change): record-failed, never merged', () {
    final fx = replayFixture(registry: false);
    fx.cli.featureCommit({'pubspec.yaml': 'name: probe\n'});
    expectResult(realReplay(fx), 5, 'record-failed');
    expect(fx.calls, isNot(contains('merge')));
  });

  test('the gate script missing from the merge commit: record-failed', () {
    final fx = LandFixture.create();
    fx.cli.featureCommit({'docs/notes.md': 'x\n'});
    final r = realReplay(fx);
    expectResult(r, 5, 'record-failed');
    expect(out(r), contains('is missing from the merge commit'));
  });

  test('a replay leaves the real repository untouched and its scratch clone is gone', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    final before = fx.cli.snapshot();
    String refs() => fx.cli.repo
        .must(['for-each-ref', '--format=%(refname) %(objectname)'])
        .split('\n')
        .where((l) => !l.startsWith('refs/remotes/origin/feature'))
        .join('\n');
    final before2 = refs();
    expectResult(realReplay(fx), 0, 'merged');
    expect(fx.cli.snapshot(), before);
    expect(refs(), before2, reason: 'no ref is created or moved in the real repository (the push stub moves origin/feature only)');
    expect(refs(), isNot(contains('refs/replay')));
    expect(replayDirs(fx), isEmpty);
  });

  test('an inherited GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (a git hook) cannot point the replay at the real repository', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    final before = fx.cli.snapshot();
    String refs() => fx.cli.repo
        .must(['for-each-ref', '--format=%(refname) %(objectname)'])
        .split('\n')
        .where((l) => !l.startsWith('refs/remotes/origin/feature'))
        .join('\n');
    final before2 = refs();
    final r = realReplay(fx,
        env: {'GIT_DIR': fx.cli.gitDir, 'GIT_WORK_TREE': fx.dir, 'GIT_INDEX_FILE': '${fx.cli.gitDir}/index'},
        allow: {'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'});
    expectResult(r, 0, 'merged');
    expect(fx.cli.snapshot(), before);
    expect(refs(), before2);
    expect(refs(), isNot(contains('refs/replay')));
  });

  test('a replay clone older than a day is swept at the start; a fresh one and a foreign directory are not', () {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    final common = fx.cli.repo.must(['rev-parse', '--path-format=absolute', '--git-common-dir']);
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = Directory('$common/land_pr_replay-1-1000')..createSync();
    final fresh = Directory('$common/land_pr_replay-1-${now + 1000000}')..createSync();
    final foreign = Directory('$common/land_pr_other-1-1000')..createSync();
    File('${old.path}/f').writeAsStringSync('x');
    expectResult(realReplay(fx), 0, 'merged');
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(foreign.existsSync(), isTrue);
    fresh.deleteSync(recursive: true);
    foreign.deleteSync(recursive: true);
  });

  test('TERM during the real replay: the running git finishes, the scratch clone is deleted, result: error, exit 4', () async {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    final ready = '${fx.stub}/replay_ready';
    final path = fx.cli.stubPath({'git': 'case "\$*" in *commit-tree*) : > "$ready"; sleep 2;; esac'});
    final p = await startSpawn(dartBin(), [fx.landCli, '191', ...seamArgs(fx, recordGate: false)],
        workingDirectory: fx.dir,
        extraEnv: {...fx.cli.repo.env, 'PATH': path},
        allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
    final o = StringBuffer();
    final e = StringBuffer();
    final d1 = p.stdout.transform(utf8.decoder).forEach(o.write);
    final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!File(ready).existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(File(ready).existsSync(), isTrue, reason: 'the replay never reached commit-tree\n$o');
    expect(replayDirs(fx), isNotEmpty, reason: 'the scratch clone exists while the replay runs');
    p.kill(ProcessSignal.sigterm);
    final code = await p.exitCode.timeout(const Duration(seconds: 60));
    await Future.wait([d1, d2]);
    reportSpawn(code, o.toString(), e.toString(), 'land_pr TERM during the replay');
    expect(code, 4, reason: o.toString());
    expect(lastLine(o.toString()), 'result: error');
    expect(o.toString(), contains('interrupted'));
    expect(replayDirs(fx), isEmpty, reason: 'the scratch clone must be deleted');
    expect(fx.calls, isNot(contains('merge')));
  });

  test('OI-483: a TERM while the gate is losing the race ends the run there: no retry note, no backoff, the interrupted result', () async {
    final fx = replayFixture();
    fx.cli.featureCommit({'docs/notes.md': 'notes\n'});
    // A FIFO is the seam: dart's own read of the yaml blocks until the writer closes, then sees it empty and exits
    // 254 for real. So the signal lands with the attempt demonstrably in flight, and `sg` cannot catch it first.
    final yaml = '${fx.dir}/.dart_tool/native_assets.yaml';
    Directory('${fx.dir}/.dart_tool').createSync(recursive: true);
    expect(runSpawn('mkfifo', [yaml], why: 'the gate blocks inside its read of the yaml').exitCode, 0);
    final p = await startSpawn(dartBin(), [fx.landCli, '191', ...seamArgs(fx, recordGate: false)],
        workingDirectory: fx.dir,
        extraEnv: fx.cli.repo.env,
        allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
    addTearDown(() => p.kill(ProcessSignal.sigkill));
    final o = StringBuffer();
    final e = StringBuffer();
    final d1 = p.stdout.transform(utf8.decoder).forEach(o.write);
    final d2 = p.stderr.transform(utf8.decoder).forEach(e.write);
    final writer = await File(yaml).open(mode: FileMode.writeOnly).timeout(const Duration(seconds: 60));
    p.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // A plain empty file from here on: a retry the code must not make finds the same race and does not hang the test.
    File(yaml).deleteSync();
    File(yaml).writeAsStringSync('');
    await writer.close();
    final code = await p.exitCode.timeout(const Duration(seconds: 60));
    await Future.wait([d1, d2]);
    reportSpawn(code, o.toString(), e.toString(), 'land_pr TERM during a lost gate race');
    expect(code, 4, reason: '$o$e');
    expect(lastLine(o.toString()), 'result: error');
    expect(o.toString(), contains('interrupted'));
    expect('$o$e', contains('File not formatted as yaml'), reason: 'the gate must really have lost the race');
    expect('$o$e', isNot(contains('[dart-run-retry]')));
    expect(replayDirs(fx), isEmpty);
    expect(fx.calls, isNot(contains('merge')));
  });

  test('the gate prints a PASS count the verdict pins: the final line still reads "N merge(s)" (a wording change in the gate fails HERE, not every landing)', () {
    final src = File('scripts/check_plan_review_record_exists.dart').readAsStringSync();
    expect(src, contains('PASS: every landing in'));
    expect(RegExp(r'merge\(s\)').hasMatch(src), isTrue);
  });
}
