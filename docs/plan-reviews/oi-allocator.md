---
branch: oi-allocator
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi-allocator-bpass.md
---

# Plan review — oi-allocator (OI numbers are allocated, never eyeballed)

An allocator for the OI board's sequential identifiers: `scripts/mint_oi.sh` reserves the next
free number as the remote branch `refs/heads/oi/N` through a server-side compare-and-swap (GitHub
refuses to create a ref that exists — `gh api` 422 on the laptop, `git push --force-with-lease=<ref>:`
in the cloud), then appends the stub; `check_oi_numbering_unique.dart` gains Check B′ (the
working-tree arm, closing OI-176 / diagnose `f3a9c1`) and Check C (an unreserved minted number
fails the commit); the SessionStart hook prints the next free number from local refs. Blast
radius **platform** (`scripts/check_oi_numbering_unique.dart` and `oi_numbering_lib.dart` are
pinned platform; this batch pins `mint_oi.sh` and `discipline_hook.dart` the same). Spec:
`docs/superpowers/specs/2026-09-12-oi-allocator-design.md`. Plan: `docs/plans/oi-allocator.md`.

## Review rounds (≥2, before code)

- **Round 1 (context-blind, on the plan `e9e8f892`) → VERDICT: harden — 4 P1 + 13 P2, all
  folded in `57643ee8`.** P1s: the vacuous collision `PASS (vacuous)` co-printed with a
  reservation SKIP/FAIL on the same run (guard it; `reservationSkipped` is a DIFFERENT fact from
  `undetermined`); a bare `drain()` is an `unawaited_futures` WARNING and would have failed the
  pre-push analyze; the existing lib e2e fixture `'uncontested'` mints an unreserved number and
  would go red under Check C (reserve it — strengthen, never loosen); the SessionStart fetch
  measured 2.9–3.2 s over SSH on every source incl. `compact`, so spec §7.4's own 2 s rule fired
  before the code existed → the hook reads LOCAL refs only. P2s worth naming: Check C is VACUOUS
  at CI-on-main by design (published numbers exempt because `--prune` may already have removed
  their reservation) and meaningful at pre-commit, pre-merge-commit (the hookless-cloud backstop)
  and CI-on-a-PR; `next_free` must include LOCAL `main` (the §4.13 merged-but-unpushed state);
  `--reserve 0`/`007` rejected; orphans need `--release N`; `mint_oi.sh` and `discipline_hook.dart`
  fell through `scripts/**` to `feature`; the collision FIX text prescribed an eyeballed "next
  free is OI-N"; a mutation-confirm grep that counted header comments.
- **Round 2 (context-blind, on the hardened plan `57643ee8`) → VERDICT: harden (1 P1 + 4 P2 +
  5 P3, surgical), all folded in `5c5c1eed`; convergence declared after the fold** per this
  repo's record convention (`docs/plan-reviews/workout-progression-resolver.md`). P1: a SECOND lib
  fixture (`'clean merge'`) mints unreserved — round 1 named the SITE, the CLASS had two members
  (`feedback_mistake_guard_without_its_mirror` #26; grep the file for the class). P2s: `--release`
  and the unfiled list were blind to a LIVE sibling worktree's in-flight number (exclude any local
  branch's numbers; print the ledger line); Vercel builds EVERY pushed branch and a reservation is
  a new commit carrying main's tree → `vercel.json` `ignoreCommand` for `oi/*`; the `ls-remote`
  bound raised 5 → 10 s and the SKIPPED text must not promise "CI re-runs it" (nothing re-checks a
  reservation once the number is published); the hook fixture's `other` clone has an unborn HEAD.
  No further material issue → no split.

## Ground-truth verification (true)

- **Spikes, live against GitHub (2026-09-12):** laptop `gh api POST git/refs` for an existing name
  → HTTP 422 `Reference already exists`; cloud `git push` to `refs/oi/*` → HTTP 403 (the cloud
  credential writes `refs/heads/**` only), to `refs/heads/oi/spike-cloud` → `[new branch]`;
  cross-transport CAS proven (API create vs an existing branch → 422). Both spike refs deleted;
  `git ls-remote origin 'refs/heads/oi/*'` → 0 refs before the batch.
- **No allocator existed:** `build_oi_index.dart:110-111` ("minted by eyeballing the board's tail");
  six manual renumbers by 2026-09-12 (100–105, 106–108→125–127, 128→130, 167–169, 177/178→186/187
  at `de52f1e8` while this spec was being written; 189/190 hand-minted during review round 1).
- **OI-176 shape is real:** `git log --merges -1 --format=%h main` == `git rev-parse --short main`
  == `39111d1e` — main's tip is a merge commit, so every fresh worktree starts in the vacuous
  shape; e2e test 1 reproduced the exact `PASS (vacuous)` line against the pre-fix gate.
- **Pre-push cost of a plain `git push` reservation:** `scripts/pre-push.sh` runs `flutter analyze`
  unconditionally and computes the tier from `origin/main..HEAD` (empty from the primary → the
  fail-safe FULL suite) — hence the API transport on the laptop (not a `git push`; no hook runs).
- **Real-repo cardinality:** 205 local branches (`git for-each-ref refs/heads | wc -l`) — the
  measurement that found the sibling-branch scan cost (15.7 s / 24.6 s → 1.3 s / 4.1 s,
  `050e70ab`) after both review rounds had passed a loop every fixture ran at n = 2.

## Execution evidence

- Commits `93cceeef` → `e2006319` (Tasks 1–7 + perf fix + B-pass remediation), one commit per
  task, each with its mutations applied-and-confirmed (`grep -c` the removed token before the run)
  and counts in the message.
- Tests: `test/scripts/mint_oi_e2e_test.dart` 15, `oi_numbering_gate_e2e_test.dart` 10,
  `discipline_hook_oi_line_e2e_test.dart` 4, `oi_numbering_lib_test.dart` 24 (two fixtures now
  reserve their number). Full suite once at `9b1f47da`: `TZ=Asia/Kolkata flutter test test/
  --exclude-tags golden` → 5,576 passed / 0 failed / 7 skipped (8m34s); later commits covered by
  the affected e2e files (17/17, 25/25). `flutter analyze scripts/ test/scripts/` → 0 warnings.
  `sh scripts/pre-commit.sh` loop green on the clean tree before the B-pass dispatch (§4.12.5).
- **B-pass (`bpass: accepted`):** `docs/reviews/oi-allocator-bpass.md` — fresh context-blind
  agent, 4 findings (2 P2, 2 P3), 0 false alarms, all fixed in `e2006319` with a regression test
  and a mutation each (`--` for dash titles; a push rejection is a lost race only if the ref now
  exists; an unreadable MERGE_HEAD is UNDETERMINED and is located via `--git-path`, which also
  fixed a pre-existing worktree blind spot in the octopus count; diagnose citations repointed).
  Tuning entry appended to `.claude/skills/code-review/SKILL.md` (2026-09-13).

## Residues carried (spec §7, all stated, none deferred)

Ownership of a reservation is reported (ledger line), not enforced; the cloud has no hooks
(pre-merge-commit on the laptop is its backstop); `oi/*` branches accumulate until the next laptop
mint prunes published ones (Vercel skips them); the SessionStart line is local-only ("at least N
as of the last sync"); Check C is vacuous at CI-on-main by design; orphans are adopted by hand or
`--release`d after reading the ledger line; the API transport's parentless `POST /git/commits`
(root commit) is documented by GitHub and proven only by the first real laptop mint (fallback: an
explicit `"parents": []` body — one line in `cas_write`).
