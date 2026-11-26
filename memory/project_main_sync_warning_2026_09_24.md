# Multi-machine main-sync warning + FVM toolchain pin · 2026-09-24

Branch `main-sync-warning` · commits `1db54e4f`, `d662906b`, `bc7d9176`,
`4e456139`, `154999be`, `b1846b01` · merged `main` at `0c92c105`
Diagnose `b2f7e4` (orphaned-subprocess-on-timeout) · B-pass
`docs/reviews/1db54e4f4634-review.md` · plan-review
`docs/plan-reviews/main-sync-warning.md` (2 rounds, converged)

## What this batch was

Started as a read-only "is the VPS in sync with GitHub" check. It was not —
local `main` was 300 commits behind `origin/main`, undetected until a manual
`git status`, alongside several stale/duplicate files hand-copied from the
laptop. After syncing the VPS and cleaning the stale files, the batch became
"harden the discipline that we stay in sync" going forward: a SessionStart
hook extension (`_mainSyncWarning()`) that does a bounded, self-fetching
comparison of local `main` vs `origin/main` on every session start, on
either machine.

## Worth carrying forward

**1. `Future.timeout()` does not kill anything — it just stops waiting.**
The first draft used `Process.run(...).timeout(...)`. A self-triggered
B-pass caught that this never signals the underlying OS process; live
repro with a fake `git` that `exec`s into `sleep 300` showed the defect was
worse than "an orphaned background process" — the whole hook hung for the
full 300s, because `dart:io` keeps the isolate alive while a stream listener
on an open child pipe is pending. Fixed with `Process.start()` +
`process.kill(ProcessSignal.sigkill)` on a timeout scoped to
`process.exitCode`. Caught and fixed entirely pre-merge; zero live exposure.

**2. A new `.gitignore` entry needs a same-commit classification, or it
silently breaks worktree retirement's own test.** Adding `.fvm/` to
`.gitignore` without also adding it to `retire_worktree_lib.dart`'s
`regenerableIgnoredPaths` failed `gitignore_classification_test.dart` at
push time — this is the exact recurring class CLAUDE.md already documents
(a9c4f2, four prior instances), and the existing gate caught the fifth
instance exactly as designed. No new feedback file needed; the existing
documentation already covers this class precisely.

**3. Toolchain drift is a real, separate bug class from anything in the
diff.** The VPS had unpinned Flutter 3.44.9 (snap) while CI pins 3.41.4
exactly. This caused a real local-only test failure with nothing to do with
this batch's own changes — confirmed via CI-green-on-base-commit before
chasing it as a regression. Fixed properly (FVM, pinned via `.fvmrc`) rather
than bypassed, per explicit founder choice from an AskUserQuestion. Residue:
`.dart_tool/hooks_runner`'s cached kernel artifacts for `objective_c`'s
native-assets hook go stale across an SDK version change and must be
`rm -rf`'d before the next `pub get`/test/build-hook run — this recurred
three times across this session (worktree, primary, and once more after
merging) and is not yet fixed at the tooling level; just worked around
each time.

**4. Round 2 of a plan-review catching what round 1 fixed only half of is
the whole point of running two rounds.** Round 1 found a stale test-count
citation in CLAUDE.md and a stale line-number citation in a diagnose-doc's
YAML frontmatter — both fixed in one commit. Round 2, told explicitly not
to trust round 1's verdict, re-derived everything from scratch and found
the SAME stale line number had ALSO survived in the diagnose-doc's PROSE
body (round 1 only touched the YAML field for the same fact). Textbook
instance of why §4.12 requires review #2 to run on the post-#1 hardened
state rather than trusting a "found nothing new" self-report.

**5. `git reset --hard` to unwind a local-only merge (done to insert a
missing plan-review record before it hit CI) also silently discarded an
unrelated, pre-existing uncommitted `pubspec.lock` modification** that
predated this session. It was a lockfile — fully regenerable via
`flutter pub get`, low material risk — but it should have been stashed
first per this repo's own git-safety default, not swept up in a blanket
reset. Caught and disclosed, not silently absorbed.

## Numbers, so they don't get re-guessed

- 2 findings from the B-pass required code changes (P1 timeout/kill, P2
  missing kill switch); 3 were accepted no-fix (1 resolved as a side effect
  of the P1 fix, 2 informational/style).
- Round 1: 2 documentation-citation findings, 0 functional.
- Round 2: 1 documentation-citation finding (the one round 1 missed half
  of), 1 informational cross-function coupling note, 0 functional. No P0/P1
  survived to the merge.
- 13 new tests (5 pure format + 8 real subprocess/git e2e), all
  mutation-proven on the P1 fix (reverting it reddens the hang-kill test
  with the exact predicted failure shape: 0:05:00 wall time vs an expected
  <20s bound).
