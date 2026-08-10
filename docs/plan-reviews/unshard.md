---
branch: unshard
date: 2026-08-10
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/plan-reviews/unshard.md
---

# Plan-review record — revert the CI shard matrix (platform)

Keystone record for the §4.12 merge gate. The branch reverts the 3-shard `flutter test` matrix added
earlier the same day, keeping the `analyze` job split.

**This record was missing when the merge was made, and the gate caught it** — the local
`git_safety_hook` advisory fired on the push, and an adversarial reviewer independently simulated
the CI job and confirmed it would hard-fail. The merge is unpushed, so the record lands with it
rather than after it. Recorded here because "the gate caught what I forgot" is the useful half of
the entry.

## Ground truth (all re-verified directly, not taken from reviewer prose)

| Claim | Verified how |
|---|---|
| Measured 18.3% (7m49s → 6m23s) | `gh api .../runs/31364967041/jobs` + the 31350916315 baseline |
| Below the 25% floor written IN ADVANCE | `docs/superpowers/plans/2026-08-10-ci-speedup.md` §4, authored before the run existed |
| `--total-shards` slices WITHIN each suite | `test_core/lib/src/runner.dart:496-502` read directly |
| Shard 2 broke `worktree_config_integrity_e2e_test.dart` | CI log: `Expected: contains 'FAIL' / Actual: ''` at `:190` |
| …because the test inherits state from an earlier test in the same file | reproduced locally: `--plain-name "warn-only"` → **1 failed**; whole file → **6 passed** |
| Revert is complete | `yaml.safe_load` parses; no `strategy`/`matrix`/`shard` keys remain; `analyze` job intact |

## Round 1 — context-blind adversarial review

**1 P0 + 4 P1 + 4 P2.** Every load-bearing finding independently re-verified before acceptance.

| # | Finding | Disposition |
|---|---|---|
| P0 | **The revert does not restore green** — no `docs/plan-reviews/unshard.md`, so it trades a red `Unit Tests (2)` for a red `plan-review-record`. Reviewer simulated the gate with `PUSH_BEFORE` and got `REAL_EXIT=1` | **This record.** Verified locally before pushing |
| P1 | **The repo ALREADY refuted sharding on 2026-07-26** — `ci-governance.closure.yaml` G10: same `_shardSuite` mechanism, measured ~2.1× compute, *"refuted before implementation… a rejected option"* | Confirmed verbatim. See "The real lesson" below |
| P1 | The order-dependent test **fails standalone on main today**; the revert does not fix it, and under sharding the repair test passed VACUOUSLY | Fixed in this batch — 3 tests made self-sufficient |
| P1 | CI-9 claimed *"CI green again is the closing evidence"* while no green run existed | Corrected to state actual status |
| P1 | CI-1's `verification:` still described the 3-shard job as the closed state | Amended to the surviving `analyze` split |
| P2 | Ledger header said "7 items" against `total_findings: 9` | Corrected |
| P2 | 18.3% is the WORKFLOW figure; sharding's own share is ~10pp (the analyze split is the rest) | Corrected in the ledger |
| P2 | Plan §4's Rule 2 (">3m22s → raise N") and Rule 3 ("<25% → abort") point OPPOSITE ways on the observed data, and no precedence was written | Rule 2 struck as unsatisfiable — solving the fixed/variable split gives a ~6m00s floor at any N, i.e. ~23%, under the floor forever |

## Round 2 — on the corrected state

Re-ran the gate simulation and the affected tests after the round-1 corrections: the plan-review
record resolves, all three previously order-dependent tests pass standalone AND in-file, the
workflow parses with no residual shard keys, and Gate 40 passes on the amended ledger. No new
material findings — the round-1 set was implementation-complete rather than design-inverting, which
is the §4.12.1 signal that the unit has converged rather than needing a split.

## The real lesson, which is not the one the commit message claimed

The revert commit says the transferable part is *"writing the abort condition BEFORE the
measurement."* That is true but secondary. **The primary failure is that §4.1.5 was never run.**

`docs/audit/ci-governance.closure.yaml` already carried, from 15 days earlier: the `_shardSuite`
within-suite mechanism, a measured 2.1× compute cost, and an explicit `rejected option` verdict. A
bug-history lookup — which §4.1.5 makes a precondition, not a nicety — would have ended the sharding
proposal before the plan was written. Instead it survived a plan, ×2 context-blind review, a B-pass,
implementation, a merge, a red CI, and a revert.

Neither review round asked "has this repo tried this before?" That question is not on any lens, and
its absence cost a full cycle. It is the single highest-value addition this session found.
