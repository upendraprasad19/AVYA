// scripts/retire_worktree_lib.dart
//
// Pure decision logic for scripts/retire_worktree.dart — the missing
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
// THE PREDICATE IS FOUR-LEGGED AND ALL FOUR ARE LOAD-BEARING:
//   1. branch merged into main
//   2. no tracked changes            (git status --porcelain, non-`!!` lines)
//   3. no NON-REGENERABLE ignored files  (--ignored=matching, `!!` lines)
//   4. no unpushed commits           (git log @{u}..), or no upstream at all,
//      in which case leg 1 already guarantees reachability from main
//
// Leg 3 is separate from leg 2 because `git status --porcelain` — the obvious
// spelling of "clean" — EXCLUDES ignored files entirely, so naming it as the
// clean check would name the blind spot as the guard.
//
// LEG 2 IS THE ONE THAT SAVES REAL WORK, and this is measured, not theoretical:
// on 2026-08-09 FIVE worktrees held 21 uncommitted files between them
// (train-signout-notif-bugs 14, persona-sweep-e2e 3, qualification-exam-plans 2,
// admin-dashboard 1, memory-consolidation-log 1) while classifying as MERGED by
// branch tip. A "delete everything merged" sweep destroys all of it. Merge
// status describes a branch; it says nothing about the working tree on top of it.
//
// (An earlier draft of this comment also listed post38-auth-fixes' 15 files,
// making it "five worktrees" over a list of six summing to 36. post38 is NOT
// merged — `git branch --merged main` does not return it — so it was never at
// risk from a merge-only sweep, and including it both broke the arithmetic and
// weakened the very claim it was cited for. Round-1 review caught it.)
//
// LEG 2 MUST ALSO SEE IGNORED FILES. `git status --porcelain` EXCLUDES them by
// default and `git worktree remove` does NOT refuse on them — verified
// 2026-08-09: a merged worktree holding an ignored `secrets/.env` classified
// "merged + clean + pushed", removed with exit 0, file gone. §4.13 has
// new-worktree.sh copy a gitignored `.env` into EVERY worktree, so the blind
// spot sits directly on this repo's documented workflow.
//
// But counting ALL ignored files would make nothing retirable, since that same
// `.env` (plus build output) exists everywhere. So the caller separates
// REGENERABLE ignored paths (.env, .dart_tool/, build/, .flutter-plugins*, all
// reconstructible from main + a build) from everything else, and passes only
// the latter as [ignoredFiles]. Regenerable ones are reported, never blocking.
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
///   6. non-regenerable ignored files -> KEEP  <-- git's own blind spot
///   7. unpushed commits      -> KEEP
///   8. otherwise             -> RETIRE
///
/// [factsReadable] is false when git could not be interrogated for this
/// worktree at all (directory missing, `status` failed, NO UPSTREAM configured
/// so the unpushed leg could not be evaluated, permissions). It is a SEPARATE
/// input from "clean" on purpose: an unreadable worktree must never collapse
/// into the same bucket as a verified-clean one. That conflation is how a check
/// reports health it never established — and it bit exactly here in round 1,
/// where `git log @{u}..` exits 128 with no upstream and the caller read the
/// resulting 0 as "nothing unpushed", printing "merged + clean + pushed" for a
/// leg that was never evaluated at all.
///
/// [ignoredFiles] counts ONLY non-regenerable ignored files (see header). Zero
/// means "no ignored files, or only regenerable ones" — the caller must have
/// already filtered.
RetireDecision classifyWorktree({
  required bool isPrimary,
  required bool isProtected,
  required bool factsReadable,
  required bool merged,
  required int dirtyFiles,
  required int unpushed,
  int ignoredFiles = 0,
  bool upstreamConfigured = true,
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
  if (ignoredFiles > 0) {
    return RetireDecision(
        RetireVerdict.keep,
        '$ignoredFiles non-regenerable ignored file(s) — `git status` hides '
        'these and `git worktree remove` does not refuse on them');
  }
  if (unpushed > 0) {
    return RetireDecision(
        RetireVerdict.keep, '$unpushed unpushed commit(s)');
  }
  // NO UPSTREAM: retire, but SAY SO rather than claiming "pushed".
  //
  // Round 1 flagged that reporting "merged + clean + pushed" for a branch with
  // no tracking ref announces a leg that was never evaluated. The first fix
  // over-corrected — routing it to unreadable/KEEP — which makes the tool inert
  // in any repo without remotes (it kept every worktree in the e2e fixture).
  //
  // The correct resolution: leg 1 already requires the branch be merged into
  // main, so its commits are reachable from main whether or not an upstream
  // exists. Nothing is lost. The defect was the DESCRIPTION, not the decision —
  // so fix the description.
  if (!upstreamConfigured) {
    return const RetireDecision(RetireVerdict.retire,
        'merged + clean (no upstream configured — commits reachable from main)');
  }
  return const RetireDecision(
      RetireVerdict.retire, 'merged + clean + pushed');
}

/// One registered worktree parsed from `git worktree list --porcelain`.
typedef WorktreeRecord = ({String path, String branch, bool locked});

/// Parse `git worktree list --porcelain`.
///
/// FLUSHES ON THE RECORD BOUNDARY, not on the `branch` line. Verified against
/// git 2.53: `locked` is emitted AFTER `branch`, so an earlier version that
/// emitted the record as soon as it saw `branch` never observed the lock at
/// all — `locked` was ALWAYS false and the whole feature was inert, while a
/// code comment claimed it prevented exactly the failure it still produced.
/// Nothing caught it because no test referenced `locked`.
///
///     worktree /path/to/w1
///     HEAD <sha>
///     branch refs/heads/w1
///     locked do not touch      <-- AFTER branch
///
/// A record with neither `branch` nor `detached` (i.e. `bare`) is dropped
/// deliberately rather than mislabelled: a bare primary already exits earlier
/// on `--show-toplevel`.
List<WorktreeRecord> parseWorktreePorcelain(String stdout) {
  final out = <WorktreeRecord>[];
  String? path;
  String? branch;
  var locked = false;

  void flush() {
    if (path != null && branch != null) {
      out.add((path: path!, branch: branch!, locked: locked));
    }
    path = null;
    branch = null;
    locked = false;
  }

  for (final line in stdout.split('\n')) {
    final l = line.trimRight();
    if (l.startsWith('worktree ')) {
      flush(); // close the PREVIOUS record before starting a new one
      path = l.substring(9).trim();
    } else if (l == 'locked' || l.startsWith('locked ')) {
      locked = true;
    } else if (l.startsWith('branch ') && path != null) {
      branch = l.substring(7).trim().replaceFirst('refs/heads/', '');
    } else if (l.startsWith('detached') && path != null) {
      // Detached carries no branch, so leg 1 can never be satisfied. Recorded
      // with an empty branch so it is COUNTED and reported rather than silently
      // skipped — an unlisted worktree reads as "handled" when it was never
      // examined.
      branch = '';
    }
  }
  flush(); // the final record has no trailing `worktree ` line to close it
  return out;
}

/// EXACT, ROOT-ANCHORED ignored paths that may be destroyed. Nothing else.
///
/// THREE SUCCESSIVE REVIEW ROUNDS EACH FOUND A P0 IN THIS ONE FUNCTION, every
/// time because the matching was looser than "exactly this path":
///   round 1 — no ignored check at all: `git status --porcelain` hides ignored
///             files and `git worktree remove` does not refuse, so an ignored
///             `secrets/.env` was destroyed silently.
///   round 2 — PREFIX matching: `.env` also matched `.envrc` (direnv secrets)
///             and the ignored directory `.envs/`; both destroyed. Because
///             `--ignored=matching` collapses a directory to ONE entry, a single
///             false positive authorises deleting an unbounded subtree.
///   round 3 — BASENAME-at-any-depth: `.env` matched `supabase/.env`, which is
///             a REAL 518-byte credentials file in this repo, separately listed
///             at `.gitignore:69`. `p.contains('/build/')` likewise made
///             `android/keystore/build/upload.jks` destroyable. A test in this
///             very suite asserted `supabase/.env` MUST be regenerable — the
///             suite had locked the bug in.
///
/// So: exact match only. No prefix, no basename, no `contains`. A worktree's
/// entire real ignored set here is six entries, so exactness costs NOTHING in
/// retirability while making every path above non-regenerable. If this list
/// ever needs a pattern, that is the signal to keep the worktree instead —
/// inertness is recoverable, a deleted credentials file is not.
///
/// Directory entries end in `/` because that is how `--ignored=matching` emits
/// a collapsed ignored directory.
const regenerableIgnoredPaths = <String>[
  // Copied in by scripts/new-worktree.sh — the ROOT file only.
  '.env',
  // Flutter/Dart build products, all reproduced by `flutter pub get` + a build.
  '.dart_tool/',
  'build/',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.packages',
  'android/local.properties',
  'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
  'ios/Flutter/Generated.xcconfig',
  // Test-generated output written INTO the worktree (OI-128). Each is listed in
  // .gitignore and rewritten from scratch by the run that produces it, so a
  // worktree that merely RAN the suite is not thereby holding anything precious.
  // Before this, any worktree that ran the full suite could never retire — the
  // tool reported "1 non-regenerable ignored file" for a file a test had just
  // written. Enumerated from .gitignore, not guessed:
  'test/plan_generator/v4_diagnostic_output.md', // .gitignore:112, written by
  // test/plan_generator/v4_diagnostic_test.dart:234
  'analyze_output.txt', // .gitignore:107
  'flutter_test_output.txt', // .gitignore:108
  'baseline.json', // .gitignore:132
  'baseline-lints.json', // .gitignore:133
  // DELIBERATELY ABSENT: `test/goldens/**/failures/` (.gitignore:183). It is
  // genuinely regenerable, but it is a PATTERN, and this list's whole rule is
  // exact-match-only — three review rounds each found a P0 here from looser
  // matching. The header's own instruction for this case is to keep the
  // worktree instead: inertness is recoverable, a deleted file is not.
];

/// True when an ignored path is reconstructible and so may be destroyed.
///
/// Exact match against [regenerableIgnoredPaths], after normalising separators.
/// Anything not on the list — including anything NESTED under a listed name —
/// is treated as precious and keeps the worktree.
bool isRegenerableIgnored(String path) {
  final p = path.replaceAll(r'\', '/');
  return regenerableIgnoredPaths.contains(p);
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
/// [entryCount] counts files AND directories. Named for what it measures: an
/// earlier version counted only files and reported directories as "0 files",
/// so a tree of empty subdirectories read as an empty husk.
RetireDecision classifyOrphan({required int entryCount}) {
  if (entryCount == 0) {
    return const RetireDecision(
        RetireVerdict.retire, 'empty husk (0 entries)');
  }
  return RetireDecision(RetireVerdict.keep,
      '$entryCount entr${entryCount == 1 ? "y" : "ies"} and no git to vouch '
      'for them — manual review');
}
