---
branch: oi520-enforce-lockfile
date: 2026-11-22
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi520-enforce-lockfile-bpass.md
---

# Plan-review record: oi520-enforce-lockfile (platform; one CI workflow change plus its contract test, tier M)

Plan: `docs/plans/2026-11-22-oi520-enforce-lockfile.md` (v2.3). The change: the required `Analyze` job of `.github/workflows/test.yml` gains a step that fails a PR whose `pubspec.lock` Flutter 3.41.4's `flutter pub get` would change (or that deletes the lock), so `scripts/safe_pr_merge.sh` refuses it; the contract test `test/contracts/ci_lockfile_enforced_test.dart` pins the shape of that step and of the job around it; a comment in `.github/dependabot.yml` and a section in `docs/architecture/hooks.md` record the guard and its cost. `pubspec.yaml`, `pubspec.lock` and `lib/` are untouched. It implements option (a) of OI-520 on the founder's answer "Yes, add CI check" (2026-11-22), as `pub get` + a tracked-file check + `git diff --exit-code` rather than the literal `--enforce-lockfile` flag, which was measured to pass two kinds of drift.
`bpass: accepted` since the `/code-review` B-pass ran on the committed three-dot diff `origin/main...ffd2906c` (one fresh read-only seat that mutated copies of the test in its own detached worktree; 6 findings: 2 P2, 4 P3, no P0 or P1; every one accepted and folded in this branch, none rejected; `docs/reviews/oi520-enforce-lockfile-bpass.md`). The verdict in that file is the coordinator's triage, self-attested. This record lands in the same commit as the review and the closure ledger; no hash names the review (the staged-hash gate `check_code_review_pass_exists.dart` is catastrophic-only). The tier is stated from `docs/blast_radius.yaml`: `.github/workflows/test.yml` is `platform` (`:403`), `docs/architecture/hooks.md` is `platform` (`:124`), the other paths are `feature` or `docs`.

## Round 1 (context-blind Sonnet, read-only, on head `e631c595`, the first built draft; CI green)

8 findings: 1 P1, 4 P2, 3 P3. Reviewer verdict: NOT converged. Every finding was checked by the coordinator against the file or by measurement before it was folded (table in the plan, R1-1 to R1-8). Material fixes: the remediation the first comment gave (fix the lock on the Dependabot branch) is a dead end, because a human commit on a `dependabot/*` branch loses the merge gate's Dependabot exemption (`scripts/check_plan_review_record_exists.dart:611-619`) and no record can satisfy it, so the real routes are written down and the cost is reported to the founder; the merge needs `--allow-workflow-change`; the gate demands of the closing commit were spelled out; and `--enforce-lockfile` was REPRODUCED as narrower than "a clean tree after `pub get`" (it exits 0 on metadata-only drift and on an added `collection: any`), so the mechanism was changed to `flutter pub get` followed by `git diff --exit-code -- pubspec.lock`, with the test, the comment and the board text following.

## Author finding between rounds (A-1)

The v2 verify step passed a PR that DELETES the lock (`pub get` regenerates it untracked and `git diff` ignores an untracked file; measured exit 0). v2.1 prepends `git ls-files --error-unmatch -- pubspec.lock &&`; two mirror mutants and 12 real mutations followed, and the deletion case went red on a real runner (throwaway PR 321, closed unmerged).

## Round 2 (a fresh context-blind Sonnet, read-only, on the HARDENED plan, head `adf1c48a`)

6 findings: 1 P2, 5 P3. Reviewer verdict: NOT converged. The P2 was a reader gap (`_jobKeys` stopped at `steps:`, so a job key written after the steps was never judged); the P3 were an overclaim ("EXACTLY what the pinned Flutter writes"; a CRLF lock under `eol=lf` is left untouched by `pub get`), residual evasions (a quoted `name:` twin, a twin in another workflow file), missing killing mutants and an operator-facing record. All folded in v2.2 (`15e906ad`), CI green before round 3.

## Round 3 (a fresh context-blind Sonnet, read-only, narrow, on the folds, head `ffd2906c`, CI green)

Reviewer verdict: **converged** (0 P0, 0 P1, 0 P2, 4 P3; it re-ran a real mutation itself and probed 13 one-line regressions of the test's helpers, 11 of which survived). The 4 P3 were folded in v2.3 (not left optional, CLAUDE.md §4.2): a twin named by its id only, a non-canonical step line merged into the previous step, tolerances without a killing mutant, and two wording defects.

## Why `converged` is recorded after two "NOT converged" reviewer verdicts

Rounds 1 and 2 each found material issues (a P1 in round 1, a P2 in round 2), so each was folded and a further, fresh round was run on the hardened plan; the plan was NOT declared converged on the strength of rounds it had not survived. Round 3 found no P0, P1 or P2. The parallel B-pass then found 2 P2 and 4 P3 in the same code (the reader's silent-merge of unparsed step shapes, which round 3 had named as a P3 in a weaker form, and a hard-coded Flutter pin), and those were folded and the whole mutation harness re-run on the folded head: 55 real mutations as intended, 0 survivors (plan F14). The unit stayed small (one workflow step and its test), the finding severity fell round over round (P1, P2, then P3 only), and no round after the third found anything in the mechanism itself; the changes since round 3 hardened the TEST's reader, not the guard. That is the coordinator's judgement and is self-attested.

## Ground-truth verification

Every reviewer verified claims against the live worktree at file:line, and every number the plan states was re-derived by the coordinator. The mechanism was verified by running, not by reading: in scratch repositories `flutter pub get --enforce-lockfile` exits 0 on a metadata-only drift and on an added `collection: any` while `pub get` plus `git diff --exit-code` fails both, and `git ls-files --error-unmatch` fails a deleted lock; on a real runner the check went red on a pre-PR-314 lock (PR 319, flag version), on an edited `sdks` floor (PR 320) and on a deleted lock (PR 321), and green on the good lock (runs 44990058448, 44993118794, 44998296576, and the run on the final code head). The contract test was mutated 55 ways on the committed head (the reader's own helpers included): 0 survivors. NOT verified by anyone: the behaviour of a `pubspec.lock` that is a symlink (this Windows machine cannot create one), and whether GitHub treats the job ids `analyze` and `Analyze` as distinct check names (the test compares them case-insensitively).
