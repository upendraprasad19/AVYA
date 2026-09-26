// test/scripts/discipline_hook_memory_path_test.dart
//
// Pure unit tests for `resolveMemoryIndexPath` in scripts/discipline_hook.dart.
//
// Regression coverage for the bug fixed 2026-09-23 (discipline-v3-phase3 batch):
// the function used to mangle `Directory.current.path` (the WORKTREE path in
// every §4.13 session) instead of the PRIMARY repo root derived from
// `--git-common-dir`. In a linked worktree that produced a mangled directory
// name that does not exist, so the MEMORY.md size nudge silently never fired
// from any worktree session. MUTATION: reverting the fix to mangle a raw
// worktree-shaped `gitCommonDirOutput` directly (skipping `primaryRootFrom`)
// reddens the "linked worktree" test below.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/discipline_hook.dart';

void main() {
  group('resolveMemoryIndexPath', () {
    test('override always wins, regardless of other inputs', () {
      final path = resolveMemoryIndexPath(
        override: '/custom/path/MEMORY.md',
        home: null,
        gitCommonDirOutput: null,
      );
      expect(path, '/custom/path/MEMORY.md');
    });

    test('returns null when home is missing', () {
      final path = resolveMemoryIndexPath(
        override: null,
        home: '',
        gitCommonDirOutput: 'C:/Upendra/Claude Code/Fitness App/.git',
      );
      expect(path, isNull);
    });

    test('returns null when git-common-dir is unresolvable', () {
      final path = resolveMemoryIndexPath(
        override: null,
        home: 'C:/Users/upend',
        gitCommonDirOutput: null,
      );
      expect(path, isNull);
    });

    test('derives the PRIMARY root path from the shared main worktree', () {
      final path = resolveMemoryIndexPath(
        override: null,
        home: 'C:/Users/upend',
        gitCommonDirOutput: 'C:/Upendra/Claude Code/Fitness App/.git',
      );
      expect(
        path,
        'C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/MEMORY.md',
      );
    });

    // THE REGRESSION CASE. In a linked worktree, --git-common-dir still points
    // at the PRIMARY's .git (git's own contract), so the derived path must be
    // IDENTICAL to the shared-worktree case above — never the worktree's own
    // mangled path. This is exactly what the bug got wrong: mangling
    // Directory.current.path (the worktree path) instead of this value.
    test('linked worktree resolves to the PRIMARY path, not the worktree path', () {
      final path = resolveMemoryIndexPath(
        override: null,
        home: 'C:/Users/upend',
        gitCommonDirOutput: 'C:/Upendra/Claude Code/Fitness App/.git',
      );
      expect(
        path,
        'C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/MEMORY.md',
      );
      // The bug's shape: mangling the WORKTREE path directly would have produced
      // this WRONG, nonexistent directory name instead.
      const wrongMangledFromWorktreePath =
          'C--Upendra-Claude-Code-Fitness-App---claude-worktrees-supabase-outage-check-e79200';
      expect(path!.contains(wrongMangledFromWorktreePath), isFalse);
    });
  });
}
