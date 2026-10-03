// scripts/worktree_guard_lib.dart
//
// Pure decision logic for the worktree-per-session commit guard
// (scripts/check_commit_from_worktree.dart). Kept separate + git-free so the
// contract test can exercise every branch deterministically without a git
// fixture. Named WITHOUT the `check_` prefix so the pre-commit `check_*.dart`
// gate loop (and Gate 33) treat only the gate itself as a gate, not this lib.
//
// See the gate file header for the full rationale (2 cross-session file-mixing
// incidents 2026-07-07; the shared main worktree's git index is shared, so a
// commit there can mix two sessions' staged files).

class WorktreeGuardResult {
  /// True → the commit must be BLOCKED (exit 1). False → allowed (exit 0).
  final bool blocked;
  final String reason;
  const WorktreeGuardResult(this.blocked, this.reason);
}

/// Decide whether a commit should be blocked, given the observed facts.
///
/// Precedence (first match wins):
///   1. CI                    → allow (this is a LOCAL pre-commit guard).
///   2. ALLOW_MAIN_COMMIT=1    → allow (documented solo-integration escape hatch).
///   3. nothing staged         → allow (nothing to guard).
///   4. merge in progress      → allow (integrating INTO main is fine).
///   5. linked worktree        → allow (isolated index; the safe path).
///   6. otherwise (primary)    → BLOCK (the shared main worktree).
WorktreeGuardResult evaluateWorktreeGuard({
  required bool isCi,
  required bool allowOverride,
  required bool hasStaged,
  required bool mergeInProgress,
  required bool isLinkedWorktree,
}) {
  if (isCi) {
    return const WorktreeGuardResult(
        false, 'CI environment (local pre-commit guard only).');
  }
  if (allowOverride) {
    return const WorktreeGuardResult(false, 'ALLOW_MAIN_COMMIT=1 override.');
  }
  if (!hasStaged) {
    return const WorktreeGuardResult(false, 'no staged changes.');
  }
  if (mergeInProgress) {
    return const WorktreeGuardResult(
        false, 'merge in progress (integration into main allowed).');
  }
  if (isLinkedWorktree) {
    return const WorktreeGuardResult(
        false, 'committing from a linked worktree (isolated index).');
  }
  return const WorktreeGuardResult(
      true, 'primary/shared main worktree — feature commit blocked.');
}
