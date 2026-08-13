@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
//
// Every test in this file spawns `dart run <script>` as a real subprocess, and a
// cold `dart run` costs seconds on its own (VM start + kernel compile). Measured
// standalone with ZERO contention: this file takes ~33s wall for its handful of
// tests — already brushing the 30s PER-TEST default.
//
// The merge-commit regression-catalog walk then runs ~700 tests concurrently, so
// the same subprocesses take far longer and these tests time out. That produced
// false failures that blocked a merge twice while the file passed standalone
// every time. The default is simply wrong for a test whose body starts a Dart VM;
// this matches what test/scripts/*_e2e_test.dart already declare for the same
// reason.
//
// This is a TIMEOUT, not a retry: a genuine hang still fails, just later.

// Integration test for scripts/git_safety_hook.dart — the actual PreToolUse
// wire contract, not just the pure lib functions.
//
// B-pass finding #5 (discipline-overhead batch, 2026-07-19): the original
// coverage (git_safety_lib_test.dart) only unit-tested the pure regex
// helpers; nothing exercised the hook's real stdin JSON parsing + exit-code
// contract. This is exactly the surface a Claude Code harness field-name
// change (hook_event_name / tool_name / tool_input.command / cwd) would
// silently break without ANY test catching it. Spawns the actual script as
// a subprocess and pipes real JSON, same as Claude Code's harness does.
//
// Slower than the pure-function tests (each case pays a `dart run` cold
// start) — kept to the specific cases that validate the wire contract
// itself, not exhaustive branch coverage (git_safety_lib_test.dart already
// covers that at unit-test speed).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String repoRoot;

  /// A directory with NO merge/cherry-pick/revert in progress, used as the
  /// payload `cwd` for every DENY assertion.
  ///
  /// Why this exists (diagnose b7e4c2, 2026-07-27): the hook deliberately
  /// exempts raw `git commit` while MERGE_HEAD/CHERRY_PICK_HEAD/REVERT_HEAD
  /// exists, because resolving a conflict REQUIRES a raw commit. The original
  /// tests passed `cwd: repoRoot` — the live repo — so the moment a conflicted
  /// merge was in progress the exemption fired and both deny assertions failed.
  ///
  /// That is not a cosmetic flake. The pre-commit hook runs the full suite on
  /// a merge commit, so these two tests were guaranteed to fail exactly when
  /// someone was doing an integration merge — the one moment the raw-commit
  /// guard matters most. A guard that cries wolf during the operation it
  /// governs teaches people to `--no-verify` past it.
  late Directory neutralCwd;

  setUpAll(() {
    repoRoot = Directory.current.path;
    neutralCwd = Directory.systemTemp.createTempSync('git_safety_neutral_');
  });

  tearDownAll(() {
    if (neutralCwd.existsSync()) neutralCwd.deleteSync(recursive: true);
  });

  /// Parent environment minus the three variables git exports to its own
  /// hooks.
  ///
  /// GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE override BOTH `workingDirectory:`
  /// and `git -C <path>` — so when this suite runs INSIDE pre-commit, an
  /// inherited GIT_DIR makes the hook's `_gitOk(cwd, ...)` resolve against the
  /// real repo no matter which cwd the payload names, and `neutralCwd` alone
  /// would not save us. Same class as `feedback_mistake_git_hook_env_leak`,
  /// reached by a different route (there it defeated a test's own temp repo).
  ///
  /// Removed case-insensitively: Windows env keys are case-insensitive, and
  /// `Map.from(Platform.environment)` yields a case-SENSITIVE copy, so a
  /// literal `.remove('GIT_DIR')` could silently miss a `Git_Dir`.
  Map<String, String> scrubbedEnv() {
    const leaky = {'git_dir', 'git_work_tree', 'git_index_file'};
    return {
      for (final e in Platform.environment.entries)
        if (!leaky.contains(e.key.toLowerCase())) e.key: e.value,
    };
  }

  // A typed record instead of dart:io's ProcessResult -- that SDK class
  // types stdout/stderr as `dynamic` (it supports byte-list mode too),
  // which trips `avoid_dynamic_calls` (a WARNING, fatal to pre-commit's
  // `flutter analyze --no-fatal-infos` even though infos are non-fatal) the
  // moment a caller does `result.stdout.trim()`. This repo hit the identical
  // class before (workout-generator batch: an untyped-JSON avoid_dynamic_calls
  // in a test) -- typed decode at the source instead of casting at each
  // call site.
  Future<({int exitCode, String stdout, String stderr})> runHook(
    Map<String, dynamic> payload,
  ) async {
    final process = await Process.start(
      'dart',
      ['run', '--verbosity=error', 'scripts/git_safety_hook.dart'],
      workingDirectory: repoRoot,
      environment: scrubbedEnv(),
      includeParentEnvironment: false,
      // runInShell: Windows' Process.start does not do PATHEXT resolution
      // the way a shell does -- without this, even a PATH-available `dart`
      // fails with "system cannot find the file specified" on Windows.
      runInShell: true,
    );
    process.stdin.write(jsonEncode(payload));
    await process.stdin.close();
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    return (exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  /// Defaults `cwd` to [neutralCwd], NOT the live repo — see its doc comment.
  /// Pass an explicit [cwd] only when the test is about cwd-dependent state.
  Map<String, dynamic> payload(String command, {String? cwd}) => {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'cwd': cwd ?? neutralCwd.path,
        'tool_input': {'command': command},
      };

  group('git_safety_hook.dart — real subprocess, real JSON wire contract', () {
    test('raw git commit is denied (exit 2)', () async {
      final result = await runHook(payload('git commit -m "x"'));
      expect(result.exitCode, 2);
      expect(result.stderr, contains('safe_commit.sh'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('multi-line raw git commit is denied (F2 regression, at the wire level)',
        () async {
      final result =
          await runHook(payload('git add -A\ngit commit -m "x"'));
      expect(result.exitCode, 2);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('commit via safe_commit.sh wrapper is allowed (exit 0)', () async {
      final result =
          await runHook(payload('sh scripts/safe_commit.sh "msg"'));
      expect(result.exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 3)));

    // The other half of the contract, and the half that had no test at all
    // until b7e4c2. Resolving a conflicted merge REQUIRES a raw `git commit`
    // — safe_commit.sh cannot stand in for it — so the exemption is load-
    // bearing, not a loophole. Previously it was "covered" only by accident:
    // when a merge happened to be in progress it silently flipped the two
    // deny tests to failures, which reads as a broken guard rather than as
    // evidence the exemption works.
    test('raw git commit IS allowed while a merge is in progress (exit 0)',
        () async {
      final repo = Directory.systemTemp.createTempSync('git_safety_merging_');
      addTearDown(() {
        if (repo.existsSync()) repo.deleteSync(recursive: true);
      });

      // Env must be scrubbed here too: run inside pre-commit, an inherited
      // GIT_DIR would point every one of these commands at the REAL repo.
      ProcessResult git(List<String> args) => Process.runSync(
            'git',
            args,
            workingDirectory: repo.path,
            environment: scrubbedEnv(),
            includeParentEnvironment: false,
            runInShell: true,
          );

      expect(git(['init']).exitCode, 0, reason: 'temp repo init failed');
      git(['config', 'user.email', 't@example.com']);
      git(['config', 'user.name', 'T']);
      File('${repo.path}/f.txt').writeAsStringSync('x');
      git(['add', 'f.txt']);
      expect(git(['commit', '-m', 'seed']).exitCode, 0);

      // Simulate the mid-merge state directly. A real conflicted merge would
      // work too, but MERGE_HEAD is just a ref file and the hook only asks
      // `rev-parse --verify MERGE_HEAD` — so writing it is the same signal
      // with far less setup that could itself flake.
      // Cast before use: ProcessResult types stdout as `dynamic`, and a
      // dynamic call is an avoid_dynamic_calls WARNING — fatal to pre-commit's
      // `flutter analyze --no-fatal-infos`. Same trap this file's header
      // documents for the runHook record.
      final head = (git(['rev-parse', 'HEAD']).stdout as String).trim();
      final gitDir = (git(['rev-parse', '--git-dir']).stdout as String).trim();
      final mergeHead = gitDir == '.git' || gitDir.isEmpty
          ? '${repo.path}/.git/MERGE_HEAD'
          : '$gitDir/MERGE_HEAD';
      File(mergeHead).writeAsStringSync('$head\n');
      expect(git(['rev-parse', '-q', '--verify', 'MERGE_HEAD']).exitCode, 0,
          reason: 'MERGE_HEAD simulation did not take — the rest of this test '
              'would pass vacuously against a repo with no merge in progress.');

      final result =
          await runHook(payload('git commit -m "resolve"', cwd: repo.path));
      expect(result.exitCode, 0,
          reason: 'A raw commit during a merge must be allowed — it is the '
              'only way to complete a conflict resolution.');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('raw git push is denied (exit 2)', () async {
      final result = await runHook(payload('git push origin main'));
      expect(result.exitCode, 2);
      expect(result.stderr, contains('safe_push.sh'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('--no-verify is denied without the override (exit 2)', () async {
      final result =
          await runHook(payload('git commit -m "x" --no-verify'));
      expect(result.exitCode, 2);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a non-git Bash command is allowed silently (exit 0, no output)',
        () async {
      final result = await runHook(payload('ls -la'));
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a non-Bash tool is allowed (exit 0) — field-name contract check',
        () async {
      final process = await Process.start(
        'dart',
        ['run', '--verbosity=error', 'scripts/git_safety_hook.dart'],
        workingDirectory: repoRoot,
        runInShell: true,
      );
      process.stdin.write(jsonEncode({
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Read',
        'cwd': repoRoot,
        'tool_input': {'file_path': 'x'},
      }));
      await process.stdin.close();
      final exitCode = await process.exitCode;
      expect(exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('malformed JSON on stdin fails open (exit 0, never crashes the call)',
        () async {
      final process = await Process.start(
        'dart',
        ['run', '--verbosity=error', 'scripts/git_safety_hook.dart'],
        workingDirectory: repoRoot,
        runInShell: true,
      );
      process.stdin.write('{not valid json');
      await process.stdin.close();
      final exitCode = await process.exitCode;
      expect(exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
