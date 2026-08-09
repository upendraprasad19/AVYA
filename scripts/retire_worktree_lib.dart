// scripts/retire_worktree_lib.dart
//
// Pure decision logic for scripts/retire-worktree.dart — the missing
// counterpart to scripts/new-worktree.sh. Kept separate + git-free so every
// branch is testable deterministically without a git fixture. Named WITHOUT the
// `check_` prefix so the pre-commit `check_*.dart` gate loop (and Gate 33)
// treat neither this nor the retire script as a gate: retirement is an
// operator-invoked action, NOT something that runs on every commit.
//
// WHY THIS EXISTS (2026-08-09):
// §4.13 mandates a worktree per session and defines NO end of life.
// new-worktree.sh creates; nothing retired. The count reached 106 directories /
// 17 GB. That is not neglect — it is an unclosed loop in the rule itself, so it
// regrows no matter how often the backlog is swept.
//
// Stale worktrees are not merely disk: repo-wide greps and globs walk them, so
// any glob-based gate reads N stale copies of the codebase. An input-set-width
// problem sitting underneath the whole gate suite.
//
// THE PREDICATE IS THREE-LEGGED AND ALL THREE ARE LOAD-BEARING:
//   1. branch merged into main
//   2. working tree clean   (git status --porcelain empty)
//   3. no unpushed commits  (git log @{u}.. empty)
//
// LEG 2 IS THE ONE THAT SAVES REAL WORK, and this is measured, not theoretical:
// on 2026-08-09 five worktrees held 21 uncommitted files between them
// (train-signout-notif-bugs 14, post38-auth-fixes 15 incl. staged,
// persona-sweep-e2e 3, qualification-exam-plans 2, admin-dashboard 1,
// memory-consolidation-log 1) while classifying as MERGED by branch tip. A
// "delete everything merged" sweep destroys all of it. Merge status describes a
// branch; it says nothing about the working tree sitting on top of it.
//
// FAIL-SAFE DIRECTION: every uncertainty resolves to KEEP. A worktree wrongly
// kept costs disk; a worktree wrongly removed costs work that was never
// committed anywhere. Those are not symmetric.

enum RetireVerdict { retire, keep }

class RetireDecision {
  final RetireVerdict verdict;
  final String reason;
  const RetireDecision(this.verdict, this.reason);

  bool get shouldRetire => verdict == RetireVerdict.retire;
}

/// Decide whether one worktree may be retired, given observed facts.
///
/// Precedence (first match wins) — ordered so that the cheapest, most absolute
/// protections short-circuit before anything derived from git state:
///   1. primary worktree      -> KEEP (never remove the integration folder)
///   2. explicitly protected  -> KEEP (operator-supplied list)
///   3. facts unreadable      -> KEEP (never act on an unanswered question)
///   4. branch not merged     -> KEEP
///   5. working tree dirty    -> KEEP  <-- the leg that saves uncommitted work
///   6. unpushed commits      -> KEEP
///   7. otherwise             -> RETIRE
///
/// [factsReadable] is false when git could not be interrogated for this
/// worktree at all (directory missing, `status` failed, permissions). It is a
/// SEPARATE input from "clean" on purpose: an unreadable worktree must never
/// collapse into the same bucket as a verified-clean one. That conflation is
/// how a check reports health it never established.
RetireDecision classifyWorktree({
  required bool isPrimary,
  required bool isProtected,
  required bool factsReadable,
  required bool merged,
  required int dirtyFiles,
  required int unpushed,
}) {
  if (isPrimary) {
    return const RetireDecision(
        RetireVerdict.keep, 'primary worktree (integration folder)');
  }
  if (isProtected) {
    return const RetireDecision(RetireVerdict.keep, 'protected');
  }
  if (!factsReadable) {
    return const RetireDecision(RetireVerdict.keep,
        'could not read git state — refusing to act on an unanswered question');
  }
  if (!merged) {
    return const RetireDecision(RetireVerdict.keep, 'branch not merged');
  }
  if (dirtyFiles > 0) {
    return RetireDecision(RetireVerdict.keep,
        '$dirtyFiles uncommitted file(s) — merge status does not see these');
  }
  if (unpushed > 0) {
    return RetireDecision(
        RetireVerdict.keep, '$unpushed unpushed commit(s)');
  }
  return const RetireDecision(
      RetireVerdict.retire, 'merged + clean + pushed');
}

/// Whether an on-disk directory that git does NOT know about may be removed.
///
/// Orphans are a SEPARATE category from registered worktrees, and deliberately
/// far more conservative. `git worktree remove` cannot see them at all, so only
/// a raw delete would work — and an orphan is by definition one git has lost
/// track of, which means "git says it is safe" carries NO information about it.
/// On 2026-08-09 the orphans were: two empty husks (0 files), one 5-file
/// directory, and `pr-ag-handoff-gaps` — 1,945 files including lib/ and docs/
/// with no .git at all, i.e. a detached copy of the repo nothing can vouch for.
///
/// Rule: ONLY a genuinely empty directory is removable automatically. Anything
/// holding a single file is reported for human review, never deleted.
RetireDecision classifyOrphan({required int fileCount}) {
  if (fileCount == 0) {
    return const RetireDecision(
        RetireVerdict.retire, 'empty husk (0 files)');
  }
  return RetireDecision(RetireVerdict.keep,
      '$fileCount file(s) and no git to vouch for them — manual review');
}
