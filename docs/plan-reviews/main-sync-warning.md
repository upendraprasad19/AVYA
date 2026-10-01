---
branch: main-sync-warning
date: 2026-09-24
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/1db54e4f4634-review.md
---

# Plan review — SessionStart multi-machine main-sync warning (`main-sync-warning`)

## Why this record exists

`scripts/discipline_hook.dart` is explicitly pinned `platform` tier in
`docs/blast_radius.yaml:225` — the full, unabridged ×2 plan-review process
applies before this branch can merge to `main`.

## Scope

Motivated by a same-day incident: this VPS clone's local `main` had silently
drifted 300 commits behind `origin/main`, undetected until a manual
`git status`. The branch extends the existing SessionStart discipline hook
(`scripts/discipline_hook.dart`) with a bounded, self-fetching comparison of
local `main` against `origin/main`, so drift is surfaced automatically at the
start of every session on either machine (laptop or VPS), rather than
relying on someone noticing.

1. `1db54e4f` — `_mainSyncWarning()` added: a ~4s-bounded `git fetch origin
   main`, then `git rev-list --left-right --count` to detect
   BEHIND/AHEAD/DIVERGED, with exact remediation commands in the output.
   Falls back to a local-only comparison with a staleness caveat on
   fetch failure/timeout. New tests: `discipline_hook_main_sync_format_test.dart`
   (pure formatter) + `discipline_hook_main_sync_e2e_test.dart` (real
   subprocess/git).
2. `d662906b` — a self-triggered B-pass (`docs/reviews/1db54e4f4634-review.md`,
   `verdict: accepted`) found a real P1 before this landed on `main`:
   `Process.run(...).timeout(...)` does not kill the underlying OS process on
   timeout (`Future.timeout()` races a Timer with no cancellation API), so a
   genuinely hung `git fetch` would hang the ENTIRE hook for its full
   duration, not the advertised ~4s bound — live-reproduced with a fake `git`
   that `exec`s into `sleep 300`. Fixed via `_boundedFetch()`:
   `Process.start()` + explicit `process.kill(ProcessSignal.sigkill)` on a
   timeout scoped to `process.exitCode` specifically, plus
   `GIT_TERMINAL_PROMPT=0` and explicit stdout/stderr draining. Also added the
   `DISCIPLINE_HOOK_SYNC_SKIP=1` kill switch (B-pass finding 2). Diagnose-doc:
   `docs/diagnoses/2026-09-24-discipline-hook-fetch-timeout-does-not-kill-process-b2f7e4.md`,
   mutation-proven (reverting the fix reddens the "actually KILLED" test with
   the exact predicted failure shape: 0:05:00 wall time vs an expected <20s
   bound).
3. `4e456139` — `.fvmrc` pinning Flutter 3.41.4 via FVM to match CI's pinned
   SDK, fixing a local-only VPS test failure caused by SDK version drift
   (unrelated to the sync-warning feature itself, but discovered and fixed in
   this same batch while getting the branch's own tests green); classifies
   the new `.fvm/` `.gitignore` entry as regenerable in
   `scripts/retire_worktree_lib.dart`, required by
   `test/scripts/gitignore_classification_test.dart`.
4. `154999be` — round-1 plan-review remediation: fixed a stale test count in
   CLAUDE.md's discipline-hooks pointer row (claimed 6 tests in
   `discipline_hook_main_sync_e2e_test.dart`; it holds 8) and a stale
   file:line citation in the diagnose-doc's YAML frontmatter (claimed
   `_mainSyncWarning()` at line 377; actual 370).
5. This commit — round-2 remediation: the same stale "line 377" citation
   survived in the diagnose-doc's PROSE body (round 1 only fixed the YAML
   `readers:` field), plus this record itself.

## Review timeline (2 rounds + 1 B-pass, all independent/context-blind)

- **B-pass** (before round 1, on commit `1db54e4f` alone): 5 findings.
  P1 (the `Process.run().timeout()` orphaned-process bug, fixed in
  `d662906b`), P2 (missing kill switch, fixed same commit), P2
  (lock-contention concern, resolved as a side effect of the P1 fix), P3/P4
  (message-conflation and repo-root-resolution style notes, accepted
  no-fix). `docs/reviews/1db54e4f4634-review.md`, `verdict: accepted`.
- **Round 1** (fresh `general-purpose` subagent, full branch as of `4e456139`):
  ran the actual test suite (13/13 green, ~11s incl. the hang-kill e2e
  test), `flutter analyze` clean, independently re-derived and confirmed the
  `_boundedFetch()` fix and the concurrency-safety argument for the shared
  `.git` under §4.13's multi-worktree model, confirmed `.fvm/`'s on-disk
  contents are fully reproducible from `.fvmrc`. Found 2 P4 documentation
  citation drifts (stale test count in CLAUDE.md; a diagnose-doc line
  citation off by ~7 lines) and one P4/informational note (a real but
  live-inapplicable gap: `process.kill()` doesn't reach a grandchild the
  credential helper might spawn — this repo's actual `credential.helper` is
  `store`, no subprocess, so no live trigger). No P0/P1.
- **Round 2** (fresh `general-purpose` subagent, on the round-1-hardened
  state at `154999be`): independently re-verified from scratch rather than
  trusting round 1's verdict — re-walked `_boundedFetch()`'s four cases by
  hand, re-confirmed line 370 and the 8-test count directly, confirmed
  `flutter analyze` clean, confirmed the SessionStart wiring calls
  `_mainSyncWarning()` unconditionally on every source, and checked a cross-
  function interaction round 1 didn't: `_mainSyncWarning()`'s fetch mutates
  `refs/remotes/origin/main` before `_oiBoardLine()` reads it later in the
  same switch — informational only (can only make `_oiBoardLine()`'s answer
  *more* current, never wrong; undocumented but not a defect, P4). Found one
  real gap round 1 missed: the same stale "line 377" citation survived in
  the diagnose-doc's prose body (round 1 only fixed the YAML field) — fixed
  in this commit. Confirmed this record was the only remaining blocker
  (P1, structural: CI's keystone gate requires it to exist before merge —
  not a defect in the branch's own logic). `flutter test` could not be run
  directly in that subagent's sandbox (same pre-existing native-asset/kernel-
  version sandbox quirk this batch already diagnosed and worked around
  locally, unrelated to this branch); correctness was instead verified by
  full manual code walkthrough of all four `_boundedFetch()` exit paths.

**Ground truth verified, not just subagent prose**: both rounds independently
ran `flutter analyze` against the real tree and confirmed 0 issues; round 1
executed the real test suite (13/13); both rounds independently grepped the
live file for the disputed line numbers and test counts rather than trusting
each other's or the diagnose-doc's claims; the `.fvm/` regenerability claim
was checked against the actual on-disk directory contents, not just the
commit message.

## Convergence

Two rounds, each finding only cosmetic/documentation drift and no P0-P1
functional defects beyond the single P1 the B-pass already caught and fixed
before round 1 began. Round 2 found nothing round 1 missed except one
already-partially-fixed citation. No new material issues on the second
pass — converged.
