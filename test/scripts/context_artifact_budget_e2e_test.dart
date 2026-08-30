// End-to-end tests for scripts/check_context_artifact_budget.dart against real
// fixture trees. The decision logic is covered by context_budget_lib_test.dart;
// this file covers what only a real run exercises: the exit codes, the
// --warn-only escape hatch, --record, and the three fail-open paths (absent,
// malformed, and unreadable baselines) that a pure lib test cannot reach
// because they live in the JSON-loading shell.
//
// The REAL script is executed (not a copy) with cwd pointed at a temp fixture:
// Dart resolves `import` against the script's own URI, so context_budget_lib
// still loads from scripts/, while the script's relative data paths
// (`CLAUDE.md`, `docs/audit/`, `backups/`) resolve against the fixture.

@Timeout(Duration(minutes: 4))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT. This file spawns real `dart run`
// subprocesses and each pays the flutter/bin/dart wrapper cost CLAUDE.md §0
// measures at 3.4-10.5s for a no-op. Six sequential spawns fit inside 30s when
// the file runs ALONE and do not when the suite runs ~40 files concurrently — a
// targeted run is a DIFFERENT input set from the suite, not a subset.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subprocess environment with git/CI leakage removed — same hermetic contract
/// as the other `test/scripts/` e2e files. git exports GIT_DIR / GIT_WORK_TREE
/// into every hook and they override `workingDirectory:`, so a fixture that
/// builds its own tree would silently read the REAL repo when this test runs
/// inside pre-commit (feedback_mistake_git_hook_env_leak).
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

late final String _gate;

ProcessResult _run(String cwd, {List<String> args = const []}) => Process.runSync(
      'dart',
      ['run', _gate, ...args],
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

/// A fixture root carrying the three tracked artifacts at chosen sizes.
Directory _fixture({
  required int claudeMd,
  required int index,
  required int board,
  String? baselineJson,
}) {
  final dir = Directory.systemTemp.createTempSync('ctx_budget_e2e_');
  Directory('${dir.path}/docs/audit').createSync(recursive: true);
  Directory('${dir.path}/backups').createSync(recursive: true);
  File('${dir.path}/CLAUDE.md').writeAsStringSync('x' * claudeMd);
  File('${dir.path}/docs/audit/OPEN_INDEX.md').writeAsStringSync('x' * index);
  File('${dir.path}/docs/audit/open_issues.md').writeAsStringSync('x' * board);
  if (baselineJson != null) {
    File('${dir.path}/backups/context_artifact_sizes.json')
        .writeAsStringSync(baselineJson);
  }
  return dir;
}

String _baselines({required int claudeMd, required int index, required int board}) =>
    '{"CLAUDE.md":{"bytes":$claudeMd},'
    '"docs/audit/OPEN_INDEX.md":{"bytes":$index},'
    '"docs/audit/open_issues.md":{"bytes":$board}}';

void main() {
  setUpAll(() {
    _gate = File('scripts/check_context_artifact_budget.dart').absolute.path;
    expect(File(_gate).existsSync(), isTrue,
        reason: 'run from the repo root; gate not found at $_gate');
  });

  final trash = <Directory>[];
  tearDownAll(() {
    // Cleanup NEVER throws. A timed-out child still holds a Windows handle into
    // the temp dir, so deleteSync raises PathAccessException and stacks a SECOND
    // failure that HIDES the real one. %TEMP% is reaped by the OS regardless.
    for (final d in trash) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Directory track(Directory d) {
    trash.add(d);
    return d;
  }

  test('within band → exit 0', () {
    final dir = track(_fixture(
      claudeMd: 1000,
      index: 1000,
      board: 1000,
      baselineJson: _baselines(claudeMd: 1000, index: 1000, board: 1000),
    ));
    final r = _run(dir.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout.toString(), contains('PASS'));
  });

  test('past the HARD band → exitCode, 1 and the file is named', () {
    // THE RED PATH. Neuter the hard band in context_budget_lib.dart and this
    // exits 0 instead — the gate stops being able to block anything.
    final dir = track(_fixture(
      claudeMd: 1000,
      index: 2000, // +100%
      board: 1000,
      baselineJson: _baselines(claudeMd: 1000, index: 1000, board: 1000),
    ));
    final r = _run(dir.path);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect(r.stderr.toString(), contains('OPEN_INDEX.md'));
    expect(r.stderr.toString(), contains('FAIL'));
  });

  test('past the SOFT band only → warns but exit 0', () {
    final dir = track(_fixture(
      claudeMd: 1000,
      index: 1250, // +25%: past soft 15%, under hard 50%
      board: 1000,
      baselineJson: _baselines(claudeMd: 1000, index: 1000, board: 1000),
    ));
    final r = _run(dir.path);
    expect(r.exitCode, 0, reason: 'a warning must never block');
    expect(r.stdout.toString(), contains('WARN'));
  });

  test('--warn-only downgrades a hard breach to exit 0', () {
    final dir = track(_fixture(
      claudeMd: 1000,
      index: 5000,
      board: 1000,
      baselineJson: _baselines(claudeMd: 1000, index: 1000, board: 1000),
    ));
    expect(_run(dir.path).exitCode, 1);
    expect(_run(dir.path, args: ['--warn-only']).exitCode, 0);
  });

  test('no baseline file at all → SKIPPED, exit 0 (fails open)', () {
    final dir = track(_fixture(claudeMd: 1000, index: 1000, board: 1000));
    final r = _run(dir.path);
    expect(r.exitCode, 0);
    expect(r.stdout.toString(), contains('SKIPPED'));
    expect(r.stdout.toString(), isNot(contains('FAIL')));
  });

  test('malformed baseline JSON → SKIPPED, exit 0 (fails open)', () {
    final dir = track(_fixture(
      claudeMd: 9999,
      index: 9999,
      board: 9999,
      baselineJson: '{not valid json at all',
    ));
    final r = _run(dir.path);
    expect(r.exitCode, 0, reason: 'a corrupt baseline must not wedge commits');
    expect(r.stdout.toString(), contains('SKIPPED'));
  });

  test('--record writes baselines, and the next check passes', () {
    final dir = track(_fixture(claudeMd: 1234, index: 2345, board: 3456));
    final rec = _run(dir.path, args: ['--record']);
    expect(rec.exitCode, 0);
    expect(rec.stdout.toString(), contains('RECORDED 3'));

    final written =
        File('${dir.path}/backups/context_artifact_sizes.json').readAsStringSync();
    expect(written, contains('1234'));
    expect(written, contains('3456'));

    final r = _run(dir.path);
    expect(r.exitCode, 0);
    expect(r.stdout.toString(), contains('3 within band'));
  });

  test('a tracked artifact missing from the tree is SKIPPED, not a breach', () {
    final dir = track(_fixture(
      claudeMd: 1000,
      index: 1000,
      board: 1000,
      baselineJson: _baselines(claudeMd: 1000, index: 1000, board: 1000),
    ));
    File('${dir.path}/docs/audit/open_issues.md').deleteSync();
    final r = _run(dir.path);
    expect(r.exitCode, 0, reason: 'unreadable must fail OPEN');
    expect(r.stdout.toString(), contains('SKIPPED'));
  });
}
