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
    // The four hooks scripts/setup-hooks.sh installs.
    const hooks = <String>[
      'scripts/pre-commit.sh',
      'scripts/pre-push.sh',
      'scripts/commit-msg.sh',
      'scripts/prepare-commit-msg.sh',
    ];

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
}
