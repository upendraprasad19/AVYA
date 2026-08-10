// End-to-end tests for scripts/build_gate_index.dart against real fixture
// trees. The pure lib is covered by gate_index_lib_test.dart; this file covers
// the parts only a real run exercises: the hard-fail exit codes, the
// --warn-only escape hatch, and the unregistered-declaration scan.
//
// The REAL script is executed (not a copy) with cwd pointed at a temp fixture:
// Dart resolves `import` against the script's own URI, so gate_index_lib.dart
// still loads from scripts/, while the script's relative data paths
// (`scripts/`, `docs/audit/`) resolve against the fixture.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subprocess environment with git/CI leakage removed.
///
///   GIT_*      — git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into
///                every hook, and they override BOTH `workingDirectory:` and
///                `git -C <path>`. A fixture that builds its own tree would
///                silently read the REAL repo when this test runs inside
///                pre-commit (feedback_mistake_git_hook_env_leak).
///   GITHUB_*   — this gate reads no GITHUB_* var today, but the family shares
///                one hermetic contract so a future reader of CI env cannot
///                silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

late final String _builder;

ProcessResult _runBuilder(String cwd, {List<String> args = const []}) {
  return Process.runSync(
    'dart',
    ['run', _builder, ...args],
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    runInShell: true,
  );
}

/// A fixture repo root with `scripts/` + `docs/audit/`.
Directory _fixture(Map<String, String> scripts) {
  final dir = Directory.systemTemp.createTempSync('gate_idx_e2e_');
  Directory('${dir.path}/scripts').createSync(recursive: true);
  Directory('${dir.path}/docs/audit').createSync(recursive: true);
  scripts.forEach((name, body) {
    File('${dir.path}/scripts/$name').writeAsStringSync(body);
  });
  return dir;
}

String _gate(String? number, String purpose) {
  final decl = number == null ? '' : '// Gate: $number\n//\n';
  return '// scripts/x.dart\n//\n$decl// $purpose\n\nvoid main() {}\n';
}

void main() {
  setUpAll(() {
    // Absolute path to the real script, resolved before any cwd juggling.
    _builder = File('scripts/build_gate_index.dart').absolute.path;
    expect(File(_builder).existsSync(), isTrue,
        reason: 'run from the repo root');

    // Fail loudly rather than silently testing the real repo.
    final scrubbed = _cleanEnv();
    expect(scrubbed.keys.where((k) => k.toUpperCase().startsWith('GIT_')),
        isEmpty,
        reason: 'env scrub failed — the fixture would read the REAL repo');
  });

  test('a clean gate set exits 0', () {
    final dir = _fixture({
      'check_alpha.dart': _gate('7', 'Alpha purpose.'),
      'check_beta.dart': _gate('8', 'Beta purpose.'),
      'check_gamma.dart': _gate(null, 'Unnumbered, and that is fine.'),
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(File('${dir.path}/docs/audit/GATE_INDEX.md').existsSync(), isTrue);
  });

  test('a duplicate number exits 1 and names BOTH scripts', () {
    final dir = _fixture({
      'check_alpha.dart': _gate('7', 'Alpha.'),
      'check_beta.dart': _gate('7', 'Beta.'),
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 1);
    final out = '${r.stdout}${r.stderr}';
    expect(out, contains('Gate 7'));
    expect(out, contains('check_alpha.dart'));
    expect(out, contains('check_beta.dart'),
        reason: 'naming only one claimant leaves the reader unable to act');
  });

  test('--warn-only exits 0 but STILL writes the index with collisions marked',
      () {
    // The escape hatch exists for exactly one commit — the one that introduces
    // this registry while 5 pre-existing collisions are still live. If it ever
    // stopped marking collisions, or started suppressing the report, it would
    // become a silent permanent bypass. This test is what stops that.
    final dir = _fixture({
      'check_alpha.dart': _gate('7', 'Alpha.'),
      'check_beta.dart': _gate('7', 'Beta.'),
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _runBuilder(dir.path, args: ['--warn-only']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('Gate 7'),
        reason: 'warn-only must still REPORT, not silently pass');

    final index = File('${dir.path}/docs/audit/GATE_INDEX.md').readAsStringSync();
    expect(index, contains('COLLISION'),
        reason: 'the index is the baseline the next commit is checked against; '
            'an unmarked index is not a baseline');
  });

  test('an unregistered canonical declaration under scripts/ exits 1', () {
    // Hard-fail 4. NOT circular: the scan covers all of scripts/, while the
    // index is built from check_* + _extraGateScripts. This is what catches the
    // next validate_*/audit_* script that mints a number without registering.
    final dir = _fixture({
      'check_alpha.dart': _gate('7', 'Alpha.'),
      'validate_rogue.dart': _gate('55', 'Mints a number but is not a gate.'),
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('validate_rogue.dart'));
  });

  test('a PROSE gate mention in a non-gate lib does NOT trip hard-fail 4', () {
    // The loose regex `gate\s*:?\s*\d` over the header window matches 5 real
    // files in this repo — four of them pure libs whose headers explicitly say
    // "treat only the gate itself as a gate, not this lib" — and would make the
    // builder exit 1 forever. Even the narrowed `^//\s*Gate\s*:?\s*\d` still
    // matches worktree_config_integrity_lib.dart:7. Keying on the canonical
    // form is what makes this safe.
    final dir = _fixture({
      'check_alpha.dart': _gate('7', 'Alpha.'),
      'some_lib.dart': '// scripts/some_lib.dart\n'
          '//\n'
          '// Named WITHOUT the check_ prefix so the gate loop (and\n'
          '// Gate 33) treat only the gate itself as a gate, not this lib.\n'
          '\nvoid main() {}\n',
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('a build-apk section disagreeing with the header exits 1', () {
    final dir = _fixture({'check_alpha.dart': _gate('53', 'Alpha.')});
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/.claude/commands').createSync(recursive: true);
    File('${dir.path}/.claude/commands/build-apk.md').writeAsStringSync(
      '### Gate 23 — Alpha\n```bash\ndart run scripts/check_alpha.dart\n```\n',
    );

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 1);
    expect('${r.stdout}${r.stderr}', contains('DIFFERENT numbers'));
  });

  test('a closure ledger mint collides with a header declaration', () {
    // Source 4. The ONLY claim Gate 45 and Gate 7 have in the real repo lives
    // in a ledger — a scan blind to these produced two P0s in review.
    final dir = _fixture({
      'check_alpha.dart': _gate('45', 'Alpha.'),
      'check_beta.dart': _gate(null, 'Numbered only by the ledger.'),
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/docs/audit/some_batch.closure.yaml').writeAsStringSync(
      'verification: scripts/check_beta.dart (Gate 45, hard-fail)\n',
    );

    final r = _runBuilder(dir.path);
    expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('check_beta.dart'),
        reason: '.closure.yaml matches 18 files in the real repo vs 6 for '
            '*_closures.yaml — a glob covering only the latter is blind to '
            'three quarters of the ledgers, including this batch own closure');
  });
}
