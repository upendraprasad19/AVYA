---
branch: ci-speedup
date: 2026-08-10
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/ci-speedup-bpass.md
---

# Plan-review record — CI cycle-time reduction (platform)

Keystone record for the §4.12 merge gate. Plan:
[`docs/superpowers/plans/2026-08-10-ci-speedup.md`](../superpowers/plans/2026-08-10-ci-speedup.md).

Tier is platform via `docs/blast_radius.yaml:183` (`.github/workflows/test.yml`) and `:101`
(`scripts/pre-commit.sh`), both edited. `bpass: accepted` is unconditional at ≥platform.

## Ground-truth audit

**The plan's first version measured nothing.** That is the headline finding of this record: it
proposed parallelising a job and sharding another without ever reading a single CI timing. Both
reviewers pulled real numbers from `gh api`, and the main thread re-derived every load-bearing one
directly before accepting (`feedback_audit_verifier_cannot_trust_own_subagent`).

| Claim | Verified how |
|---|---|
| Workflow wall clock 7m49s; `Analyze & Unit Tests` IS the whole of it | `gh api .../runs/31350916315/jobs` |
| `audit-gates` gate loop = **32s**, job ends 6m46s before the workflow | same, step-level |
| `flutter analyze` = 47s, SERIAL before the 6m38s test step | same, step-level |
| Fixed per-job overhead = **21s** (not the "1.5–2 min" v1 assumed) | same, step-level |
| `flutter test --total-shards/--shard-index` exists | `flutter test --help` on this machine |
| **Sharding is WITHIN each suite, not across files** | `test_core/lib/src/runner.dart:496-502` read directly |
| Tag exclusion precedes partitioning | `runner.dart:297` passes the filtered suite into `_shardSuite` |
| pre-commit case block = **15 arms** (not 16 — one name is in a comment) | counted arm lines in source |
| 86 gate files → 71 run in the pre-commit loop | `ls` + arm count |
| CI skip list = 13 → 73 run | `test.yml` case block |
| `supabase-tests` runs zero tests, reports green, no secrets exist | live run steps `skipped` + `gh secret list` empty |
| `new-worktree.sh` bases off stale main | read `:42-46`; reproduced live this batch |
| Both waivers resolved; gate exits 0 flagless | `docs/skipped-discipline.md:5-6` + ran it |

## Round 1 — two context-blind lenses (CI mechanics · risk/scope)

**2 P0 + 7 P1 + 8 P2.** Both reviewers independently reached the same two P0s.

| # | Finding | Disposition |
|---|---|---|
| P0 | **Parallelising `audit-gates` saves ZERO wall clock** — 32s step, 6m46s slack. It was the plan's highest-risk change | **DROPPED.** Not a deferral — measured worthless, and the measurement is recorded so it is not re-proposed |
| P0 | **`flutter test` ships native sharding**; the hand-rolled partition + a new completeness gate were unnecessary | Replaced with `--total-shards`/`--shard-index` |
| P1 | The "86" replacement count was itself wrong (loops run 71/73) | Corrected, with the "2 skipped-but-invoked-explicitly" caveat |
| P1 | The Gate 33 mechanism claim was wrong — `extractCaseSkips` is provably inert | Moot once the rewrite was dropped; recorded |
| P1 | `supabase-tests` runs zero tests and reports green | Added to scope |
| P1 | The proposed completeness gate would be bare-invoked by both gate loops (the `check_closes_oi_cited` failure shape) | Moot — gate deleted |
| P2 | Per-leg cost model 5× wrong, in the plan's own disfavour | Corrected to measured 21s |
| P2 | `flutter analyze` runs serially before the tests — a free win the plan never noticed | Added as §3.2 |

## Round 2 — on the rewritten plan

**1 P0 + 3 P1 + 5 P2, and the P0 was introduced by round 1's own correction** — precisely why §4.12
runs #2 on the hardened text.

| # | Finding | Introduced by R1? | Disposition |
|---|---|---|---|
| P0 | Switching to native flags was right, but the plan kept v1's **file-level** model of sharding. Source: `_shardSuite` slices WITHIN each suite, so every shard still compiles and loads all ~693 files. Wall clock does NOT divide by N; §4's "~3m25s, floored by the APK job" and "N>3 buys nothing" were unsupportable | **yes** | Verified at source by the main thread. Plan now predicts **no number** and fixes a falsifiable decision rule in advance instead |
| P1 | 16/70 → **15/71**; a name in a comment is not a skip arm | **yes** | Corrected, plus the explicitly-invoked caveat |
| P1 | §3.5's remedy not implementable — `jobs.<id>.if` cannot read `secrets` | no | Rewritten: job-level `env:` hoist + an always-run `::warning::` step; probe-job alternative recorded and rejected with reasons |
| P1 | A **second** live line-citation missed: `open_issues.md:603` → `test.yml:171`, an OPEN board entry | no | Both citations re-pointed to stable anchors |
| P2 | `--is-ancestor` returns 0 for equal refs, so the worktree predicate needed an explicit equality branch; and "fail loud" on divergence is a ship-stop | no | 4 explicit branches + no-remote guard; diverged warns and continues |
| P2 | The new test would inherit `GIT_*` under pre-commit — and it CREATES worktrees, so destructively | no | `_cleanEnv()` copied verbatim; registered in the hermetic meta-gate |
| P2 | Shard count hand-synced in two places; job name stale after the split | no | `strategy.job-total`; job renamed |

## Why no round 3

Round 1 **inverted the plan's core** (dropped its headline change, replaced its mechanism). Round 2
**inverted no decision** — it corrected the arithmetic, the counts, and the implementability of one
remedy, all closed in the plan before any code was written. §4.12.1's prescribed response to
repeated material findings is *split and ship the smallest converged piece*, which §7 does (C1 / C2 /
C3). A third round would re-review the same design. The self-initiated B-pass over the real diff is
the backstop, and unlike a plan review it reads code.

**The residual uncertainty is named, not hidden:** the magnitude of the sharding win is unmeasured
for this suite, because sharding does not divide fixed compile cost. The plan therefore predicts no
number and commits in advance to a decision rule — including "if improvement < 25%, sharding is the
wrong lever and the answer is path filters, not more shards."
