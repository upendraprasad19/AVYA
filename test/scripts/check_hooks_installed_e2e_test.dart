// test/scripts/check_hooks_installed_e2e_test.dart
//
// E2E for scripts/check_hooks_installed.dart (Gate 32) — the FIRST dedicated
// test this gate has had (grandfathered pre-2026-08-10, per
// docs/audit/gate_test_ledger.yaml, and previously exercised only by manual
// live-testing per its own header comments).
//
// Covers the OI-104 addition (2026-09-23): full-content freshness comparison
// replacing the header-line-anchor check. MUTATION-PROOF for that addition:
// see the "STALE hook" test below and its header note on what was verified.
//
// Spawns the real gate binary against a real git repo — parseInstalledHooks'
// regex parsing and the git-path resolution both need a real `git` process,
// so this is e2e rather than a pure unit test.

@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

ProcessResult _git(String cwd, List<String> args) => Process.runSync(
      'git',
      args,
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
      runInShell: true,
    );

late final String _gateSource;

const _installerScript = '''
#!/bin/sh
set -e
REPO_ROOT="\$(git rev-parse --show-toplevel)"
HOOKS_DIR="\$(git rev-parse --git-common-dir)/hooks"
mkdir -p "\$HOOKS_DIR"
install_hook() {
  cp "\$1" "\$2"
}
install_hook "\$REPO_ROOT/scripts/pre-commit.sh" "\$HOOKS_DIR/pre-commit"
install_hook "\$REPO_ROOT/scripts/pre-push.sh" "\$HOOKS_DIR/pre-push"
''';

const _preCommitSource = '#!/bin/sh\n# pre-commit body v1\necho pre-commit\n';
const _prePushSource = '#!/bin/sh\n# pre-push body v1\necho pre-push\n';

/// A minimal repo with the gate + a fake setup-hooks.sh installing two
/// stub hooks. Returns the repo root.
Directory _repoWithInstalledHooks() {
  final dir = Directory.systemTemp.createTempSync('gate32_e2e_');
  final root = dir.path;
  Directory('$root/scripts').createSync(recursive: true);
  File('$root/scripts/check_hooks_installed.dart')
      .writeAsStringSync(File(_gateSource).readAsStringSync());
  File('$root/scripts/setup-hooks.sh').writeAsStringSync(_installerScript);
  File('$root/scripts/pre-commit.sh').writeAsStringSync(_preCommitSource);
  File('$root/scripts/pre-push.sh').writeAsStringSync(_prePushSource);

  _git(root, ['init', '-q']);
  _git(root, ['config', 'user.email', 't@t.t']);
  _git(root, ['config', 'user.name', 't']);
  File('$root/seed.txt').writeAsStringSync('seed\n');
  _git(root, ['add', '.']);
  _git(root, ['commit', '-q', '-m', 'seed']);

  // "Install" the hooks by literally copying, mirroring setup-hooks.sh's own
  // mechanism -- this is what the fake installer script would do if run.
  final hooksDir = Directory('$root/.git/hooks')..createSync(recursive: true);
  File('${hooksDir.path}/pre-commit').writeAsStringSync(_preCommitSource);
  File('${hooksDir.path}/pre-push').writeAsStringSync(_prePushSource);

  return dir;
}

ProcessResult _runGate(String cwd) => Process.runSync(
      'dart',
      ['run', 'scripts/check_hooks_installed.dart'],
      workingDirectory: cwd,
      runInShell: true,
    );

/// The gate writes WARN lines to stderr and the PASS/FAIL summary to stdout
/// -- combine both so a test does not have to know which stream carries which.
String _combined(ProcessResult r) => '${r.stdout}\n${r.stderr}';

void main() {
  setUpAll(() {
    _gateSource = File('scripts/check_hooks_installed.dart').absolute.path;
  });

  test('all hooks installed and fresh -> PASS, no warnings', () {
    final dir = _repoWithInstalledHooks();
    try {
      final result = _runGate(dir.path);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('PASS'));
      expect(_combined(result), isNot(contains('WARN')));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a missing installed hook -> hard FAIL (exit 1)', () {
    final dir = _repoWithInstalledHooks();
    try {
      File('${dir.path}/.git/hooks/pre-push').deleteSync();
      final result = _runGate(dir.path);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('NOT INSTALLED'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // THE OI-104 REGRESSION CASE, MUTATION-PROOF STYLE: this is exactly the
  // real 2026-08-20 incident this gate now catches -- a BODY edit (not a
  // header edit) to the source, with the installed copy left stale. Before
  // this batch's fix, this scenario printed clean PASS (the anchor -- the
  // first 6 lines -- was untouched). Confirmed by reverting the fix locally
  // and re-running this exact test: it went green (no WARN) against the old
  // anchor-only logic, which is the false-negative OI-104 documents.
  test('a BODY-only edit (source changed, installed copy stale) -> WARN, still exit 0', () {
    final dir = _repoWithInstalledHooks();
    try {
      // Edit the SOURCE only, mid-file (not the header) -- installed copy is
      // now stale, exactly the shape a header-anchor check cannot see.
      File('${dir.path}/scripts/pre-push.sh')
          .writeAsStringSync('#!/bin/sh\n# pre-push body v1\necho pre-push\necho NEW LINE ADDED\n');

      final result = _runGate(dir.path);
      expect(result.exitCode, 0, reason: 'staleness must WARN, never hard-fail');
      expect(_combined(result), contains('WARN'));
      expect(_combined(result), contains('STALE'));
      expect(_combined(result), contains('pre-push'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('an identical installed copy after the edit -> clean again, no WARN', () {
    final dir = _repoWithInstalledHooks();
    try {
      const edited = '#!/bin/sh\n# pre-push body v1\necho pre-push\necho NEW LINE ADDED\n';
      File('${dir.path}/scripts/pre-push.sh').writeAsStringSync(edited);
      File('${dir.path}/.git/hooks/pre-push').writeAsStringSync(edited); // re-installed

      final result = _runGate(dir.path);
      expect(result.exitCode, 0);
      expect(_combined(result), isNot(contains('WARN')));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a missing SOURCE script degrades the freshness check to presence-only, with a WARN', () {
    final dir = _repoWithInstalledHooks();
    try {
      File('${dir.path}/scripts/pre-push.sh').deleteSync();
      final result = _runGate(dir.path);
      expect(result.exitCode, 0);
      expect(_combined(result), contains('WARN'));
      expect(_combined(result), contains('PRESENCE only'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // REGRESSION (round-1 review, P2, 2026-09-23): the freshness comparison
  // read two files with no surrounding try/catch, so an unreadable installed
  // hook would throw UNCAUGHT and crash the process with a non-zero exit --
  // an accidental hard FAIL for exactly the case the gate's own comments say
  // must never happen. `File.existsSync()` returns false for a path that is
  // actually a directory (verified directly before writing this test), so
  // that shape can't reach the read call at all -- invalid UTF-8 bytes are
  // used instead: the file genuinely EXISTS (existsSync() stays true) but
  // `readAsStringSync()`'s default UTF-8 decoder throws a FormatException.
  test('an unreadable (invalid-UTF-8) installed hook degrades to a WARN, never crashes', () {
    final dir = _repoWithInstalledHooks();
    try {
      final hookPath = '${dir.path}/.git/hooks/pre-push';
      File(hookPath).writeAsBytesSync([0xFF, 0xFE, 0x00, 0xD8, 0x00, 0x00]);
      final result = _runGate(dir.path);
      expect(result.exitCode, 0, reason: 'an unreadable file must WARN, never crash the gate');
      expect(_combined(result), contains('WARN'));
      expect(_combined(result), contains('could not be read'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // REGRESSION (round-2 review, 2026-09-23): the try/catch above guards the
  // two hook-freshness reads, but left the INSTALLER read itself (line ~104,
  // `installerFile.readAsStringSync()`) unguarded -- existsSync() confirms
  // present, not readable, so an unreadable installer would throw UNCAUGHT
  // and crash this "never hard-fail" gate. Same invalid-UTF-8 technique as
  // the test above, applied to setup-hooks.sh instead of an installed hook.
  test('an unreadable (invalid-UTF-8) installer script degrades to UNDETERMINED, never crashes', () {
    final dir = _repoWithInstalledHooks();
    try {
      File('${dir.path}/scripts/setup-hooks.sh')
          .writeAsBytesSync([0xFF, 0xFE, 0x00, 0xD8, 0x00, 0x00]);
      final result = _runGate(dir.path);
      expect(result.exitCode, 0,
          reason: 'an unreadable installer must UNDETERMINED-pass, never crash the gate');
      expect(_combined(result), contains('UNDETERMINED'));
      expect(_combined(result), contains('could not be read'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
