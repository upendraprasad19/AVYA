// End-to-end tests for scripts/check_gate_index_fresh.dart.
//
// This gate is NEW, so CLAUDE.md rule 24 binds it: it ships with a test that
// FAILS when its protection is neutered. Without this file the rule would have
// failed on its own first application — the batch that introduced it would have
// shipped an untested gate.
//
// Runs against an isolated fixture repo rather than the real tree, because the
// red path requires deliberately corrupting GATE_INDEX.md and a crash mid-test
// would otherwise leave the real index wrong.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subprocess environment with git/CI leakage removed.
///
///   GIT_*      — git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into
///                every hook, and they override BOTH `workingDirectory:` and
///                `git -C <path>`. A fixture that builds its own tree would
///                silently read the REAL repo when this test runs inside
///                pre-commit (feedback_mistake_git_hook_env_leak).
///   GITHUB_*   — this gate reads no GITHUB_* var today; scrubbed anyway so the
///                family shares one hermetic contract.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

late final String _freshGate;

/// The freshness gate shells out to `dart run scripts/build_gate_index.dart`
/// with a RELATIVE path, so the fixture must carry its own copies of the
/// builder and its lib.
Directory _fixture() {
  final dir = Directory.systemTemp.createTempSync('gate_fresh_e2e_');
  Directory('${dir.path}/scripts').createSync(recursive: true);
  Directory('${dir.path}/docs/audit').createSync(recursive: true);
  for (final name in ['build_gate_index.dart', 'gate_index_lib.dart']) {
    File('scripts/$name').copySync('${dir.path}/scripts/$name');
  }
  File('${dir.path}/scripts/check_alpha.dart').writeAsStringSync(
    '// scripts/check_alpha.dart\n//\n// Gate: 7\n//\n// Alpha.\n\nvoid main() {}\n',
  );
  return dir;
}

ProcessResult _run(String exe, List<String> args, String cwd) => Process.runSync(
      exe,
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

void main() {
  setUpAll(() {
    _freshGate = File('scripts/check_gate_index_fresh.dart').absolute.path;
    expect(File(_freshGate).existsSync(), isTrue,
        reason: 'run from the repo root');
    expect(_cleanEnv().keys.where((k) => k.toUpperCase().startsWith('GIT_')),
        isEmpty,
        reason: 'env scrub failed — the fixture would read the REAL repo');
  });

  test('a freshly generated index PASSES', () {
    final dir = _fixture();
    addTearDown(() => dir.deleteSync(recursive: true));

    final build = _run('dart', ['run', 'scripts/build_gate_index.dart'], dir.path);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');

    final r = _run('dart', ['run', _freshGate], dir.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('a STALE index FAILS — the red path', () {
    final dir = _fixture();
    addTearDown(() => dir.deleteSync(recursive: true));

    _run('dart', ['run', 'scripts/build_gate_index.dart'], dir.path);
    // A gate added without regenerating: exactly the drift this gate exists to
    // catch.
    File('${dir.path}/scripts/check_beta.dart').writeAsStringSync(
      '// scripts/check_beta.dart\n//\n// Gate: 8\n//\n// Beta.\n\nvoid main() {}\n',
    );

    final r = _run('dart', ['run', _freshGate], dir.path);
    expect(r.exitCode, 1, reason: 'a stale index must block, not warn');
    expect('${r.stdout}${r.stderr}', contains('stale'));
  });

  test('a missing index FAILS rather than silently passing', () {
    final dir = _fixture();
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _run('dart', ['run', _freshGate], dir.path);
    expect(r.exitCode, 1);
  });

  test('the gate does NOT enforce collisions — freshness only', () {
    // Deliberate separation. If this gate also hard-failed on collisions it
    // would need a flag flipped in lockstep with the builder, and during the
    // commit that introduces the registry (5 live collisions) it would block
    // its own introducing commit — it is auto-picked up by the check_*.dart
    // loop and runs bare.
    final dir = _fixture();
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/scripts/check_beta.dart').writeAsStringSync(
      '// scripts/check_beta.dart\n//\n// Gate: 7\n//\n// Collides.\n\nvoid main() {}\n',
    );
    _run('dart', ['run', 'scripts/build_gate_index.dart', '--warn-only'], dir.path);

    final r = _run('dart', ['run', _freshGate], dir.path);
    expect(r.exitCode, 0,
        reason: 'collisions are the builder\'s job in the regen block; '
            '${r.stdout}${r.stderr}');
  });
}
