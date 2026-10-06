// test/scripts/no_conflict_markers_test.dart
//
// Tests for `scripts/check_no_conflict_markers.dart` and its pure lib.
//
// TWO LAYERS, BOTH REQUIRED:
//   - the pure group certifies the detector's decisions (what counts, what does
//     not, and the separator rule that keeps prose dividers from false-firing);
//   - the e2e group runs the REAL gate binary against a throwaway git repo, which
//     is the only thing that proves the gate enumerates via `git ls-files`, reads
//     the working tree, and maps a detection to exit 1. Unit-testing a helper
//     certifies the helper, not the gate (the Gate-44 lesson).
//
// NO LITERAL MARKERS APPEAR IN THIS FILE. Every fixture builds its markers at
// runtime from repeated characters, and writes them to a temp dir — never into
// the repo. That is what lets the gate scan `scripts/` and `test/` with no path
// exclusions: an exclusion would be a bypass, and `test/` is exactly where real
// merges conflict.
//
// ENV SCRUBBING IS LOAD-BEARING. Run inside `pre-commit`, a test that spawns its
// own git repo inherits GIT_DIR / GIT_WORK_TREE, which override BOTH
// `workingDirectory:` and `-C <path>` (feedback_mistake_git_hook_env_leak). This
// gate enumerates via git, so a leak would make it scan the REAL repo — passing
// standalone while asserting nothing about the fixture. We pass a filtered
// environment with includeParentEnvironment: false and ABORT LOUDLY if the
// isolation did not take.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/no_conflict_markers_lib.dart';

/// Built at runtime so this source file contains no conflict marker of its own.
final _open = '<' * 7;
final _sep = '=' * 7;
final _close = '>' * 7;

/// Parent environment minus anything git-related. Scrubs the same three keys as
/// the rest of the gate-e2e family (test/contracts/gate_e2e_env_hermetic_test.dart
/// enforces this uniformly):
///   GIT_*       — GIT_DIR / GIT_WORK_TREE override both `workingDirectory:` and
///                 `-C <path>`; this gate enumerates via git, so a leak makes it
///                 report on the REAL repo while appearing to pass.
///   GITHUB_*    — this gate reads no GITHUB_* var today. Scrubbed anyway so the
///                 family shares one hermetic contract and a future reader of CI
///                 env cannot silently acquire the c3f8e1 failure mode.
///   PUSH_BEFORE — same rationale as GITHUB_*.
Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd) {
  return Process.runSync(
    exe,
    args,
    workingDirectory: cwd,
    environment: _cleanEnv(),
    includeParentEnvironment: false,
    runInShell: true,
  );
}

void main() {
  group('conflictsInFile — what counts', () {
    test('a full conflict block yields all three markers', () {
      final content = [
        'intro line',
        '$_open HEAD',
        'ours',
        _sep,
        'theirs',
        '$_close some-branch',
        'outro',
      ].join('\n');

      final conflicts = conflictsInFile('board.md', content);

      expect(conflicts, hasLength(3));
      expect(conflicts.map((c) => c.kind).toList(),
          equals(['open', 'separator', 'close']));
      expect(conflicts.map((c) => c.line).toList(), equals([2, 4, 6]),
          reason: 'line numbers are 1-indexed and must point at the marker');
    });

    test('a clean file yields nothing', () {
      final conflicts =
          conflictsInFile('clean.md', 'alpha\nbeta\ngamma\n');
      expect(conflicts, isEmpty);
    });

    // THE FALSE-POSITIVE GUARD. A run of `=` on its own line is an ordinary
    // prose divider (setext heading, ASCII rule) and this repo's docs contain
    // them. Flagging it unconditionally would buy a whole class of false
    // positives for no detection: a conflict cannot exist without an open
    // marker. Deleting the `sawOpenOrClose` condition reddens this test.
    test('a lone separator line is NOT a conflict without an open marker', () {
      final content = 'A Heading\n$_sep\nbody text\n';
      expect(conflictsInFile('doc.md', content), isEmpty,
          reason: 'a bare rule of = is prose, not an unresolved merge');
    });

    test('but a separator IS counted once the file also has an open marker', () {
      final content = 'A Heading\n$_sep\n$_open HEAD\nx\n';
      final conflicts = conflictsInFile('doc.md', content);
      expect(conflicts.map((c) => c.kind).toList(),
          equals(['separator', 'open']),
          reason: 'ordered by line, and the earlier separator now counts');
    });

    test('CRLF input is normalised before matching', () {
      final content = 'a\r\n$_open HEAD\r\nb\r\n';
      final conflicts = conflictsInFile('crlf.md', content);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, 'open');
    });

    test('a marker-like token mid-line is not a marker', () {
      final content = 'the operator $_open is written inline here\n';
      expect(conflictsInFile('prose.md', content), isEmpty,
          reason: 'only a line START begins a conflict hunk');
    });
  });

  group('scanPaths — unreadable is not the same answer as clean', () {
    test('reports conflicts across files and records skips separately', () {
      final result = scanPaths(
        paths: ['good.md', 'bad.md', 'binary.png'],
        readFile: (p) {
          if (p == 'binary.png') return null;
          if (p == 'bad.md') return '$_open HEAD\nx\n';
          return 'all fine\n';
        },
      );

      final conflicts = result.conflicts;
      expect(conflicts, isNotEmpty);
      expect(conflicts.single.path, 'bad.md');
      expect(result.skipped, equals(['binary.png']),
          reason: 'a file that could not be read must never land in the clean '
              'pile — "could not look" and "looked and found nothing" are '
              'different answers');
    });

    test('an empty path list produces an empty result, not a crash', () {
      final result = scanPaths(paths: const [], readFile: (_) => null);
      expect(result.conflicts, isEmpty);
      expect(result.skipped, isEmpty);
    });
  });

  group('check_no_conflict_markers.dart — e2e against a real repo', () {
    late Directory tmp;
    late String repo;
    final srcRoot = Directory.current.path;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('no_conflict_markers_e2e_');
      repo = '${tmp.path}/repo';
      Directory(repo).createSync(recursive: true);

      _run('git', ['init', '-q', '-b', 'main', '.'], repo);
      _run('git', ['config', 'user.email', 'test@example.invalid'], repo);
      _run('git', ['config', 'user.name', 'Test'], repo);

      // Prove the isolation took, rather than assuming it. If GIT_DIR leaked,
      // this resolves to the REAL repo and we must not continue — the gate
      // would then scan the real tree and the assertions would be meaningless.
      final top = _run('git', ['rev-parse', '--show-toplevel'], repo);
      final resolved = (top.stdout as String).trim();
      if (!resolved.toLowerCase().contains('no_conflict_markers_e2e_')) {
        throw StateError(
            'ENV LEAK: throwaway git resolved to "$resolved", not the temp repo. '
            'GIT_DIR/GIT_WORK_TREE scrubbing failed — aborting rather than '
            'running assertions against the real repository.');
      }

      Directory('$repo/scripts').createSync(recursive: true);
      for (final f in const [
        'check_no_conflict_markers.dart',
        'no_conflict_markers_lib.dart',
      ]) {
        File('$srcRoot/scripts/$f').copySync('$repo/scripts/$f');
      }
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed'], repo);
    });

    tearDownAll(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows can hold a handle briefly; a leaked temp dir is harmless.
      }
    });

    ProcessResult runGate() =>
        _run('dart', ['scripts/check_no_conflict_markers.dart'], repo);

    test('exits 0 on a clean tracked tree', () {
      final result = runGate();
      expect(result.exitCode, 0,
          reason: 'clean repo must pass. stdout=${result.stdout} '
              'stderr=${result.stderr}');
      expect(result.stdout.toString(), contains('PASS'));
    });

    test('exits 1 when a TRACKED file carries markers', () {
      final victim = File('$repo/docs/board.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('intro\n$_open HEAD\nours\n$_sep\ntheirs\n'
            '$_close other-branch\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'land a conflicted merge'], repo);

      final result = runGate();

      expect(result.exitCode, 1,
          reason: 'this is the 2026-08-14 incident reproduced: a merge '
              'committed unresolved. stdout=${result.stdout}');
      expect(result.stderr.toString(), contains('docs/board.md'));
      expect(result.stderr.toString(), contains('3 unresolved'));

      victim.deleteSync();
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'resolve'], repo);
      expect(runGate().exitCode, 0, reason: 'and green again once resolved');
    });

    test('an UNTRACKED file with markers does not fail the gate', () {
      final stray = File('$repo/scratch.md')
        ..writeAsStringSync('$_open HEAD\nx\n');
      expect(runGate().exitCode, 0,
          reason: 'the input set is tracked files; an untracked scratch file is '
              'deliberately out of scope and the gate must say so by passing');
      stray.deleteSync();
    });

    test('the gate scans its OWN source and fixtures without excluding them',
        () {
      // The anti-bypass property. `scripts/` is tracked and copied into this
      // repo, and the gate still exits 0 — because its patterns are synthesised
      // rather than spelled. If someone "fixes" a self-flag by adding a path
      // exclusion for scripts/ or test/, this test still passes but the earlier
      // tracked-file test is what would then need excluding too — so the pair
      // is what documents the intent.
      final tracked = _run('git', ['ls-files'], repo).stdout.toString();
      expect(tracked, contains('scripts/check_no_conflict_markers.dart'));
      expect(runGate().exitCode, 0);
    });
  });
}
