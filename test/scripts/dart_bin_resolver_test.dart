// test/scripts/dart_bin_resolver_test.dart
//
// Covers scripts/_dart_bin.sh and its four consumers (the installed git hooks).
//
// WHY IT EXISTS. `flutter/bin/dart` is a wrapper that takes the SDK update lock
// and shells out to git on EVERY invocation. The hooks call dart 17 times per
// commit, and the lock SERIALIZES concurrent callers, so the wrapper's cost
// scales with the gate loop's job count instead of dividing by it. Measured on
// the real hook, same worktree, same gates, both exit 0:
//     wrapper 182149 ms  ->  SDK exe 98447 ms
// The resolver picks the exe; these tests keep it picked.
//
// THE MUTATION THIS MUST CATCH is not a subtle logic bug — it is somebody
// "tidying" a hook back to a bare `dart run`, or dropping the `.` source line
// so `"$DART_BIN"` expands to the empty string. Both look harmless in a diff
// and both silently restore the full cost (or, for the second, break the hook
// outright). `hooksInvokeDartThroughResolver` is that mirror test, and it
// matches by REGEX over the real scripts rather than by a literal snippet —
// feedback_mistake_guard_without_its_mirror: a guard matched by literal is
// defeated by reformatting.
//
// SHELL-DRIVEN SETUP, deliberately. Every fixture below is built by a shell
// driver written into a temp dir, not by Dart. Git Bash silently ignores a
// Windows-form `C:/...` entry in PATH, so a Dart-built PATH would fall through
// to the REAL dart and the test would assert nothing (the trap documented at
// length in pre_push_analyze_always_e2e_test.dart's header). Keeping every path
// inside the shell keeps every path POSIX.
//
// ENV SCRUBBING: run inside `pre-commit`, a test spawning a git-touching child
// inherits GIT_DIR / GIT_WORK_TREE, which override both `workingDirectory:` and
// `-C <path>` (feedback_mistake_git_hook_env_leak). Filtered environment +
// includeParentEnvironment: false, matching the gate e2e family.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parent environment minus git/CI range state, so a surrounding hook run
/// cannot steer a child. Mirrors the helper in the other gate e2e suites.
Map<String, String> _cleanEnv() {
  final env = <String, String>{};
  Platform.environment.forEach((k, v) {
    final u = k.toUpperCase();
    if (u.startsWith('GIT_')) return;
    if (u == 'GITHUB_EVENT_PATH' || u == 'GITHUB_REF' || u == 'PUSH_BEFORE') {
      return;
    }
    if (u == 'DART_BIN_OVERRIDE') return;
    env[k] = v;
  });
  return env;
}

ProcessResult _sh(String script, String cwd) => Process.runSync(
      'sh',
      [script],
      workingDirectory: cwd,
      environment: _cleanEnv(),
      includeParentEnvironment: false,
    );

/// Writes [body] as a shell driver that sources the REAL resolver, runs
/// `resolve_dart_bin`, and prints the result. [body] sets up PATH/fixtures.
String _driver(Directory tmp, String resolverPath, String body) {
  final p = '${tmp.path}/driver.sh';
  File(p).writeAsStringSync('''
set -u
$body
. "$resolverPath"
resolve_dart_bin
echo ""
''');
  return p;
}

void main() {
  late String resolver;
  late Directory tmp;

  setUpAll(() {
    resolver = File('scripts/_dart_bin.sh').absolute.path.replaceAll(r'\', '/');
    expect(File(resolver).existsSync(), isTrue,
        reason: 'scripts/_dart_bin.sh must exist — the hooks source it.');
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('dartbin_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* Windows can hold a handle briefly; harmless. */}
  });

  group('resolve_dart_bin', () {
    test('prefers the SDK exe over the Flutter wrapper beside it', () {
      // Fake <flutter>/bin/dart (wrapper) + <flutter>/bin/cache/dart-sdk/bin/dart.exe.
      final d = _driver(tmp, resolver, '''
mkdir -p fake/bin/cache/dart-sdk/bin
printf '#!/bin/sh\\necho wrapper\\n' > fake/bin/dart
printf '#!/bin/sh\\necho sdkexe\\n' > fake/bin/cache/dart-sdk/bin/dart.exe
chmod +x fake/bin/dart fake/bin/cache/dart-sdk/bin/dart.exe
PATH="\$PWD/fake/bin:\$PATH"
export PATH
''');
      final r = _sh(d, tmp.path);
      expect(r.exitCode, 0, reason: 'resolver must never fail: ${r.stderr}');
      expect(
        (r.stdout as String).trim(),
        endsWith('cache/dart-sdk/bin/dart.exe'),
        reason: 'The whole point: skip the wrapper when the SDK exe exists.',
      );
    });

    test('falls back to PATH dart when no cache/dart-sdk sits beside it', () {
      // A standalone Dart SDK, or a Flutter checkout not yet bootstrapped.
      // Both must resolve to the thing on PATH — for the second case the
      // wrapper is what bootstraps the SDK, so bypassing it would be wrong.
      final d = _driver(tmp, resolver, '''
mkdir -p fake/bin
printf '#!/bin/sh\\necho standalone\\n' > fake/bin/dart
chmod +x fake/bin/dart
PATH="\$PWD/fake/bin:\$PATH"
export PATH
''');
      final r = _sh(d, tmp.path);
      expect(r.exitCode, 0);
      final out = (r.stdout as String).trim();
      expect(out, endsWith('fake/bin/dart'));
      expect(out, isNot(contains('dart-sdk')));
    });

    test('DART_BIN_OVERRIDE wins when it is executable', () {
      final d = _driver(tmp, resolver, '''
mkdir -p fake/bin/cache/dart-sdk/bin over
printf '#!/bin/sh\\necho wrapper\\n' > fake/bin/dart
printf '#!/bin/sh\\necho sdkexe\\n' > fake/bin/cache/dart-sdk/bin/dart.exe
printf '#!/bin/sh\\necho chosen\\n' > over/mydart
chmod +x fake/bin/dart fake/bin/cache/dart-sdk/bin/dart.exe over/mydart
PATH="\$PWD/fake/bin:\$PATH"
export PATH
DART_BIN_OVERRIDE="\$PWD/over/mydart"
export DART_BIN_OVERRIDE
''');
      final r = _sh(d, tmp.path);
      expect(r.exitCode, 0);
      expect((r.stdout as String).trim(), endsWith('over/mydart'),
          reason: 'Override exists for SDK layouts our path guess misses.');
    });

    test('a non-executable DART_BIN_OVERRIDE is ignored, not obeyed', () {
      // Fail-safe: a stale or mistyped override must not wedge a hook, and must
      // not be handed to the caller as a command that cannot run.
      final d = _driver(tmp, resolver, '''
mkdir -p fake/bin/cache/dart-sdk/bin over
printf '#!/bin/sh\\necho wrapper\\n' > fake/bin/dart
printf '#!/bin/sh\\necho sdkexe\\n' > fake/bin/cache/dart-sdk/bin/dart.exe
printf 'not executable\\n' > over/notexec
chmod +x fake/bin/dart fake/bin/cache/dart-sdk/bin/dart.exe
chmod -x over/notexec
PATH="\$PWD/fake/bin:\$PATH"
export PATH
DART_BIN_OVERRIDE="\$PWD/over/notexec"
export DART_BIN_OVERRIDE
''');
      final r = _sh(d, tmp.path);
      expect(r.exitCode, 0);
      expect((r.stdout as String).trim(), endsWith('cache/dart-sdk/bin/dart.exe'),
          reason: 'Must fall through to normal resolution, never emit a '
              'path it just proved is not runnable.');
    });

    test('emits the bare name when there is no dart at all', () {
      // The caller's own error path then reports "dart: not found" exactly as
      // it did before this file existed. The resolver never invents a failure.
      final d = _driver(tmp, resolver, '''
mkdir -p emptybin
PATH="\$PWD/emptybin"
export PATH
''');
      final r = _sh(d, tmp.path);
      expect(r.exitCode, 0);
      expect((r.stdout as String).trim(), equals('dart'));
    });
  });

  group('hooks invoke dart through the resolver (MIRROR TEST)', () {
    // DERIVED from setup-hooks.sh, not restated.
    //
    // This list used to be four hardcoded names described as "the four hooks
    // scripts/setup-hooks.sh installs". setup-hooks.sh installed FIVE by then:
    // scripts/pre-merge-commit.sh — added in the same batch as this test — was
    // exempt from every assertion below, so reverting IT to a bare `dart run`
    // reddened nothing. Review round 1 (2026-08-17) found it.
    //
    // A hand-maintained roster of a thing that grows is a guarantee of exactly
    // this, and always fails in the reassuring direction. Deriving it is the
    // same design that made
    // test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
    // catch the new hook missing from docs/blast_radius.yaml, and that made
    // Gate 32 catch it uninstalled.
    final installer = File('scripts/setup-hooks.sh');
    final hooks = installer.existsSync()
        ? (RegExp(
              r'^\s*install_hook\s+"[^"]*?(scripts/[A-Za-z0-9._-]+)"',
              multiLine: true,
            )
            .allMatches(installer.readAsStringSync())
            .map((m) => m.group(1)!)
            .toList()
          ..sort())
        : <String>[];

    test('the derived hook list is non-empty and covers every installed hook',
        () {
      // An empty list would make every per-hook test below silently vanish —
      // the suite would go green having asserted nothing. This is the guard on
      // the guard.
      expect(installer.existsSync(), isTrue,
          reason: 'scripts/setup-hooks.sh must exist to derive the list from');
      expect(hooks, isNotEmpty,
          reason: 'parsed ZERO install_hook lines — either the installer call '
              'shape changed or this parser is stale. Either way the per-hook '
              'assertions below would all disappear without failing.');
      expect(hooks.length, greaterThanOrEqualTo(5),
          reason: 'the repo installs at least five hooks (pre-commit, pre-push, '
              'commit-msg, prepare-commit-msg, pre-merge-commit); got $hooks');
    });

    /// Strips `#` comments and the one user-facing hint line that legitimately
    /// prints the literal `dart run ...` for a human to copy. Matching raw text
    /// would make this test unfalsifiable in the direction that matters.
    List<String> _executableLines(String src) => src
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => !RegExp(r'^\s*#').hasMatch(l))
        .where((l) => !RegExp(r'^\s*echo\b').hasMatch(l))
        .toList();

    for (final hook in hooks) {
      test('$hook sets DART_BIN and never calls bare `dart run`', () {
        final f = File(hook);
        expect(f.existsSync(), isTrue, reason: '$hook must exist');
        final src = f.readAsStringSync();
        final lines = _executableLines(src);

        // 1. It must SOURCE the resolver. Without this, "$DART_BIN" expands to
        //    the empty string and the hook breaks outright — a failure mode the
        //    "no bare dart run" assertion alone would happily pass.
        expect(
          lines.any((l) => RegExp(r'^\s*\.\s+.*_dart_bin\.sh').hasMatch(l)),
          isTrue,
          reason: '$hook must source scripts/_dart_bin.sh.',
        );

        // 1b. AND THE SOURCE MUST BE GUARDED. Assertion 1 alone is satisfied by
        //     an UNGUARDED `. scripts/_dart_bin.sh`, so deleting the guard
        //     reddened nothing — while the guard is the entire reason the
        //     resolver cannot wedge a hook. Every one of these hooks runs under
        //     `set -e`, where dotting a missing file aborts outright, and a
        //     SYNTACTICALLY BROKEN one aborts even through `|| true` (POSIX
        //     requires a non-interactive shell to abort on a syntax error in a
        //     dotted script — verified, it exits 2). So the guard must test
        //     readability AND parse the file before sourcing it.
        //
        //     The old comment in these hooks claimed
        //     pre_push_analyze_always_e2e_test.dart covered this; that test
        //     copies only scripts/pre-push.sh, so it incidentally covered ONE
        //     hook and the claim was false for the other four.
        // Match the `[ -r ... _dart_bin.sh ]` TEST anywhere on the line, not
        // immediately after `if`. prepare-commit-msg.sh legitimately writes
        // `if [ -n "$root" ] && [ -r "$root/scripts/_dart_bin.sh" ]`, and an
        // `if\s+\[` anchor called that unguarded — a false BLOCK on a hook that
        // was correct, which is the failure mode a guard must never have.
        final guarded = lines.any((l) =>
            RegExp(r'\[\s+-r\s+"?[^"]*_dart_bin\.sh"?\s+\]').hasMatch(l));
        expect(guarded, isTrue,
            reason: '$hook must guard the source with `[ -r ... ]` — an '
                'unguarded `.` of a missing helper aborts the hook under set -e.');
        final parseChecked = lines.any(
            (l) => RegExp(r'sh\s+-n\s+.*_dart_bin\.sh').hasMatch(l));
        expect(parseChecked, isTrue,
            reason: '$hook must parse-check _dart_bin.sh (`sh -n`) before '
                'sourcing it. `[ -r ]` passes on a CORRUPT helper, which then '
                'wedges commit, push, merge and commit-msg simultaneously.');

        // 1c. And a fallback must exist, so a resolver that loads but cannot
        //     answer still leaves DART_BIN usable rather than empty.
        expect(
          lines.any((l) => RegExp(r'DART_BIN="dart"').hasMatch(l)),
          isTrue,
          reason: '$hook must fall back to a bare `dart` when the resolver is '
              'unavailable — an empty DART_BIN breaks every gate invocation.',
        );

        // 2. It must ASSIGN DART_BIN from the resolver.
        expect(
          lines.any(
              (l) => RegExp(r'DART_BIN=.*resolve_dart_bin').hasMatch(l)),
          isTrue,
          reason: '$hook must set DART_BIN="\$(resolve_dart_bin)".',
        );

        // 3. THE MUTATION GUARD: no executable line may invoke `dart run`
        //    directly. Regex, not literal — tolerates flags and spacing.
        final offenders = lines
            .where((l) => RegExp(r'(^|[^"\w/.$-])dart\s+run\b').hasMatch(l))
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: '$hook invokes dart directly instead of through '
              '"\$DART_BIN". That silently restores the Flutter wrapper cost '
              '(182149 ms -> 98447 ms measured on the real pre-commit run). '
              'Offending line(s): ${offenders.join(" | ")}',
        );

        // 4. And it must actually USE it at least once, or 1-3 are decoration.
        expect(
          lines.any((l) => l.contains(r'"$DART_BIN" run')),
          isTrue,
          reason: '$hook sets DART_BIN but never uses it.',
        );
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // EXECUTION GUARD (2026-08-30).
  //
  // The resolver defines a function and nothing else, so `sh _dart_bin.sh run
  // <script>` exits 0 having done NOTHING. A session did exactly that
  // repeatedly on 2026-08-30 and reported gates as passing and diagnose-docs
  // as validating on the strength of that exit code. These tests pin the
  // guard AND — the half that actually matters — pin that it does not fire on
  // any supported path, because a guard that breaks all five hooks is far
  // worse than the silent no-op it replaces.
  group('execution guard', () {
    test('executing the resolver FAILS loudly instead of no-op-ing', () {
      final r = Process.runSync(
        'sh',
        [resolver, 'run', 'scripts/whatever.dart'],
        workingDirectory: Directory.current.path,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      );
      expect(r.exitCode, 64,
          reason: 'must exit EX_USAGE(64), not 0 — an exit 0 here is the '
              'exact false-confidence signal this guard exists to remove.');
      expect('${r.stderr}', contains('must be SOURCED'),
          reason: 'the message must say what went wrong');
      expect('${r.stderr}', contains('resolve_dart_bin'),
          reason: 'and must teach the correct form');
    });

    test('a BARE-FILENAME execution fails too (the pattern\'s second arm)', () {
      // Round-1 review finding 2. The guard's pattern is
      // `*/_dart_bin.sh|_dart_bin.sh`; the second alternative exists for an
      // invocation with NO directory component (`cd scripts && sh
      // _dart_bin.sh`). Every other test here passes an absolute path, so only
      // the first arm was ever exercised — deleting `|_dart_bin.sh` left all
      // 15 tests green while reopening the original silent-no-op bug for this
      // shape. Same guard-without-its-mirror class the file header names, one
      // dimension over from the backslash case the B-pass closed.
      final scriptsDir = File(resolver).parent.path;
      final r = Process.runSync(
        'sh',
        ['_dart_bin.sh', 'run', 'foo'],
        workingDirectory: scriptsDir,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      );
      expect(r.exitCode, 64,
          reason: 'invoked by bare filename from inside scripts/, the guard '
              'must still fire — an exit 0 here is the original bug.');
      expect('${r.stderr}', contains('must be SOURCED'));
    });

    // Round-2 review P2. The `tr '\' '/'` normalization was added for
    // B-pass finding 2 (a Windows-form path bypassed the guard), and NOTHING
    // tested it: removing the normalization reproduced the silent-exit-0 bug
    // in full while all 16 tests stayed green. A defense the suite cannot see
    // is a defense the next refactor deletes for free. Note this is NOT the
    // bare-filename case above — that path contains no backslash to normalize,
    // so it exercises a different arm.
    for (final entry in const {
      'scripts/_dart_bin.sh': r'scripts\_dart_bin.sh',
      'scripts/_git_lock.sh': r'scripts\_git_lock.sh',
    }.entries) {
      test('a WINDOWS-BACKSLASH path still fails: ${entry.value}', () {
        expect(File(entry.key).existsSync(), isTrue,
            reason: 'setup: ${entry.key} must exist');
        final r = Process.runSync(
          'sh',
          [entry.value],
          workingDirectory: Directory.current.path,
          environment: _cleanEnv(),
          includeParentEnvironment: false,
        );
        expect(r.exitCode, 64,
            reason: 'a backslash path is the DOMINANT spelling in this '
                'environment; without `tr \\ /` the guard silently exits 0 '
                'and the original no-op bug is back.');
        expect('${r.stderr}', contains('must be SOURCED'));
      });
    }

    test('SOURCING still resolves a real dart binary (guard does not fire)',
        () {
      // The supported path. If the guard ever widened to match a sourced
      // invocation, this reddens — and so would all five hooks in production.
      final out = _sh(_driver(tmp, resolver, ''), tmp.path);
      expect(out.exitCode, 0, reason: 'stderr: ${out.stderr}');
      expect('${out.stdout}'.trim(), isNotEmpty,
          reason: 'sourcing must still yield a resolved path');
    });

    test('`sh -n` parse-check still passes — every hook runs it before sourcing',
        () {
      // All five hooks gate their `.` on `sh -n <resolver>`. If the guard made
      // the file unparseable, every hook would silently fall back to bare
      // `dart` and the measured 182s→98s win would evaporate with no error.
      final r = Process.runSync(
        'sh',
        ['-n', resolver],
        workingDirectory: Directory.current.path,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      );
      expect(r.exitCode, 0,
          reason: 'the guard must not break the hooks\' own parse-check');
    });

    test('the twin guard on _git_lock.sh behaves identically', () {
      // Same class, same batch: _git_lock.sh also only defines functions, so
      // executing it acquires no lock and exits 0.
      final lock =
          File('scripts/_git_lock.sh').absolute.path.replaceAll(r'\', '/');
      expect(File(lock).existsSync(), isTrue);

      final executed = Process.runSync(
        'sh',
        [lock],
        workingDirectory: Directory.current.path,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      );
      expect(executed.exitCode, 64,
          reason: 'executing the lock helper must fail, not silently no-op');
      expect('${executed.stderr}', contains('must be SOURCED'));

      // And sourcing must still define both entry points.
      final probe = '${tmp.path}/lockprobe.sh';
      File(probe).writeAsStringSync(
          'set -u\n. "$lock"\ntype git_lock_acquire >/dev/null 2>&1 || exit 3\n'
          'type git_lock_release >/dev/null 2>&1 || exit 4\necho OK\n');
      final sourced = _sh(probe, tmp.path);
      expect(sourced.exitCode, 0,
          reason: 'sourcing must still define git_lock_acquire/release; '
              'stderr: ${sourced.stderr}');
      expect('${sourced.stdout}', contains('OK'));
    });
  });
}
