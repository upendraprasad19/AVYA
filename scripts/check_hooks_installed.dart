// scripts/check_hooks_installed.dart
//
// Gate 32 (Tech-debt audit 2026-05-20, finding I8): assert that the
// repo's pre-commit hook is installed (i.e. `.git/hooks/pre-commit` exists
// and references `scripts/pre-commit.sh`).
//
// The audit finding: `setup-hooks.sh` install is opt-in and never verified.
// Fresh clone or new contributor can commit without the analyze/test gate.
// CI catches it on PR but local hygiene degrades + dirty pushes hit main.
//
// Exit 0 = pass: hook installed.
// Exit 1 = fail: hook missing or doesn't invoke scripts/pre-commit.sh.

import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  // Worktree-aware: in a git worktree `.git` is a FILE (gitdir pointer) and the
  // hooks live in the COMMON dir, so a hardcoded `.git/hooks/pre-commit` is
  // absent even though the hook IS installed and running (it invoked this gate).
  // Resolve the real path via git; fall back to the literal path if git fails.
  var hookPath = '.git/hooks/pre-commit';
  try {
    final r = Process.runSync('git', ['rev-parse', '--git-path', 'hooks/pre-commit']);
    if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
      hookPath = (r.stdout as String).trim();
    }
  } catch (_) {}
  final hookFile = File(hookPath);
  if (!hookFile.existsSync()) {
    stderr.writeln('[Gate 32] FAIL: .git/hooks/pre-commit not installed');
    stderr.writeln('  Fix: run `sh scripts/setup-hooks.sh` (see CLAUDE.md §0).');
    exit(warnOnly ? 0 : 1);
  }
  final content = hookFile.readAsStringSync();
  // The hook must either invoke scripts/pre-commit.sh OR be a verbatim copy.
  // We accept any content that references the canonical script path.
  if (!content.contains('scripts/pre-commit.sh') && !content.contains('flutter analyze')) {
    stderr.writeln('[Gate 32] FAIL: .git/hooks/pre-commit exists but does not invoke scripts/pre-commit.sh');
    stderr.writeln('  Fix: re-run `sh scripts/setup-hooks.sh` to install the canonical hook.');
    exit(warnOnly ? 0 : 1);
  }
  stdout.writeln('[Gate 32] PASS: pre-commit hook installed.');
  exit(0);
}
