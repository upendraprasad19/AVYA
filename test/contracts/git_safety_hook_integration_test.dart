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

  setUpAll(() {
    repoRoot = Directory.current.path;
  });

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

  Map<String, dynamic> payload(String command) => {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'cwd': repoRoot,
        'tool_input': {'command': command},
      };

  group('git_safety_hook.dart — real subprocess, real JSON wire contract', () {
    test('raw git commit is denied (exit 2)', () async {
      final result = await runHook(payload('git commit -m "x"'));
      expect(result.exitCode, 2);
      expect(result.stderr, contains('safe_commit.sh'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('multi-line raw git commit is denied (F2 regression, at the wire level)',
        () async {
      final result =
          await runHook(payload('git add -A\ngit commit -m "x"'));
      expect(result.exitCode, 2);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('commit via safe_commit.sh wrapper is allowed (exit 0)', () async {
      final result =
          await runHook(payload('sh scripts/safe_commit.sh "msg"'));
      expect(result.exitCode, 0);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('raw git push is denied (exit 2)', () async {
      final result = await runHook(payload('git push origin main'));
      expect(result.exitCode, 2);
      expect(result.stderr, contains('safe_push.sh'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('--no-verify is denied without the override (exit 2)', () async {
      final result =
          await runHook(payload('git commit -m "x" --no-verify'));
      expect(result.exitCode, 2);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a non-git Bash command is allowed silently (exit 0, no output)',
        () async {
      final result = await runHook(payload('ls -la'));
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));

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
    }, timeout: const Timeout(Duration(seconds: 30)));

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
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
