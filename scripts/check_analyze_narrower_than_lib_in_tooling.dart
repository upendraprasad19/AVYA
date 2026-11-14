// scripts/check_analyze_narrower_than_lib_in_tooling.dart
//
// Blocks a committed script/skill from instructing `flutter analyze` scoped
// to a single file or narrow path when the class it protects against
// (feedback_green_check_input_set_width.md #29) is exactly that a `part of`
// file's library breakage is invisible to anything narrower than
// `flutter analyze lib/`. See analyze_narrower_than_lib_lib.dart for the full
// rationale and — critically — why this gate's scope EXCLUDES `docs/**`
// (diagnose-docs legitimately cite scoped analyze as historical evidence;
// only tooling/instruction files that DIRECT future action are in scope).
//
// Scope: staged ADDED lines in scripts/*.sh, scripts/*.dart,
// .claude/skills/**/*.md ONLY. Never docs/diagnoses, docs/audit, or any other
// docs/** path — widening this pathspec reintroduces the false-positive flood
// this gate was calibrated to avoid.
//
// Exit 0 = pass (or --warn-only). Exit 1 = a scoped-analyze instruction found.
// Fails OPEN on a git failure (never wedge a commit on an environment quirk —
// same convention as check_worktree_config_integrity.dart).

import 'dart:convert';
import 'dart:io';

import 'analyze_narrower_than_lib_lib.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final tag = warnOnly ? '[analyze-scope-tooling WARN]' : '[analyze-scope-tooling]';

  final result = Process.runSync(
    'git',
    [
      'diff',
      '--cached',
      '--unified=0',
      '--no-color',
      '--',
      'scripts/*.sh',
      'scripts/*.dart',
      '.claude/skills/**/*.md',
      // Self-exclusion: this gate's own doc comments necessarily quote the
      // exact placeholder shape ("flutter analyze <narrow-path>") it exists
      // to detect elsewhere -- a textual scan cannot tell a prose example
      // inside a comment from a real instruction. Same self-referential
      // class as every sibling gate in this batch (feedback_mistake_
      // guard_without_its_mirror.md's "sibling shape" note).
      ':!scripts/check_analyze_narrower_than_lib_in_tooling.dart',
      ':!scripts/analyze_narrower_than_lib_lib.dart',
    ],
    stdoutEncoding: utf8,
  );

  if (result.exitCode != 0) {
    stdout.writeln('$tag NOTE: git diff --cached unavailable — skipping (fail open).');
    exit(0);
  }

  final violations = findScopedAnalyzeInTooling(result.stdout.toString());

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no tooling/skill file instructs a flutter analyze '
        'scoped narrower than lib/.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${violations.length} instruction(s) scope '
      'flutter analyze narrower than lib/ — a part-of file\'s breakage is '
      'invisible to anything less than the whole tree:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln(
    '\n  Use `flutter analyze lib/` (or bare `flutter analyze`) instead. A '
    'single-file or narrow-directory scope goes CLEAN on a broken part-of\n'
    '  sibling library member — feedback_green_check_input_set_width.md #29.\n'
    '  (A diagnose-doc citing a scoped analyze as spot-evidence is fine — this\n'
    '  gate only scans scripts/*.sh, scripts/*.dart and .claude/skills/**/*.md.)',
  );
  exit(warnOnly ? 0 : 1);
}
