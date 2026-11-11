---
branch: review-ci-suite-lock
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/review-ci-suite-lock-bpass.md
---

# Plan review — review-ci-suite-lock (A: review rounds take the full suite from CI; B: one local full suite at a time)

Founder decision 2026-11-11 (chat): A + B, and a standing permission to push feature branches for review CI.
Plan `docs/plans/review-ci-suite-lock.md`. Blast radius **platform** (CLAUDE.md, git hooks, `land_pr`). Execution
mode inline, one worktree. `feat(process)`, no bug, so no diagnose-doc.

## Review rounds (context-blind Sonnet, each on the previous round's hardened plan, BEFORE code)

- **Round 1 → `harden`:** P1 nested deadlock (two existing tests run the REAL hooks in the REAL repo on the locked
  paths; inside a suite started by `run_full_suite.sh` they would wait on the lock their own suite holds) → nesting
  marker `AVYA_SUITE_LOCK_HELD`; P1 a hook waiting inside `safe_commit`/`safe_push`'s git lock → hooks use
  `--no-wait`; P2s: unbounded wait, `ci-green` = exit 0, headers that said "merges", repeated flags, pins, blast-radius
  entries, SIGKILL orphan semantics; P3s: commit + PR + push all needed, other texts, catastrophic exception, stated
  limits. All folded (plan §6).
- **Round 2 → `harden`:** verified round 1 by dash + bash experiments (`--no-wait || exit 1` under `set -e` with a
  shadowing `flutter()` function, fd 9 closed for the stub child, only two tests run a real hook in the real repo).
  New: P1 marker classification (STRIPPED + `allowControl`), P2 `/build-apk` Gate 5 (stated limit with reason), P2 the
  runner must check the acquire status (else a mutant survives), P2 broken-helper fallback test, P3s. All folded (§7).
- **Round 3 → `converged`:** no P0–P2; verified the round-2 resolutions and the four env-manifest requirements, no
  deadlock on the runtime path, the Gate 5 limit accurate. Three P3 (file paths, `allowControl` in new tests, marker
  unconditional in both e2e `runHook`s) folded (§8).

## Ground truth used

`flock` at `/usr/bin/flock`; CI runs on `pull_request` into main (`test.yml:6`) with per-PR cancel-in-progress; the
plan-review-record job is main-push only (`test.yml:421-423`); `check_code_review_pass_exists.dart` gates the commit
only at catastrophic tier (header :5-9); local full suite 76:52–116:28 min over 11 logged runs vs ~16 min on CI.

## Mutation evidence (§4.4 rule 21)

- A: `--ci-only` return disabled (`o.ciOnly && false`) → 2 red (`CI green: result ci-green…`, `an unpushed commit is
  pushed…`); once-check deleted → 1 red (`--ci-only given twice…`). Applied-checks by `grep -c`; file restored, `cmp` equal.
- B (`test/scripts/suite_lock_e2e_test.dart`, 10 mutants, every one red): no serialisation 4; no `9>&-` in the runner
  2; missing-flock returns 1 → 1; marker ignored 2; `--no-wait` ignored 2; no `sh -n` guard in pre-push 2; no exec
  guard 2; runner without marker 1; pre-push acquire removed 2; pre-commit FULL acquire removed 1.
