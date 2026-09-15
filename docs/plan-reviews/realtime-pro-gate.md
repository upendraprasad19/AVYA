---
branch: realtime-pro-gate
date: 2026-09-10
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/4f6eb6532418-review.md
---

# Plan-review record — realtime PRO gate (e4a7c9), replayed onto a 25-day-newer main

Keystone record for the §4.12 merge gate. Blast radius computed, not estimated:
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
-> `platform`. Not catastrophic -> no Hermes required.

## What this is

A cherry-pick of three commits (`bfb0415c`, `b6b0c89e`, `52602ac9`) authored
2026-08-16 on `claude/debugging-stuck-issue-89b2e9`. **The code is unchanged from
what was reviewed then.** Merging that branch wholesale conflicts in 5 files, every
one of them the migration/gate/docs half that `main` has since superseded via
OI-132 — so only the `lib/` half was replayed.

`realtime.list_changes()` was **6,463s of 18,279s lifetime DB CPU (35.4%), 900,823
calls**, serving a PRO-only feature to a PRO population of ~zero, because the
entitlement check lived on one of two callers. The gate moved to the SINK.

## Rounds

| round | when | findings | outcome |
|---|---|---|---|
| 1-2 (×2 plan review) | 2026-08-15/16 | see `claude-debugging-stuck-issue-89b2e9.md` | converged |
| B-pass (original) | 2026-08-16 | 1 P0 in the fix itself | accepted, fixed |
| B-pass (rebase) | 2026-09-10 | 6 (0 P0, 2 P1, 3 P2, 1 P3) | **all accepted, 0 false alarms** |

⚠ **`review_rounds: 3` counts the two original rounds plus this rebase pass, and
the distinction matters:** rounds 1-2 reviewed the DESIGN and are not re-run here
because not one line of the design changed. What had never been reviewed is the
REBASE — and that is where every 2026-09-10 finding came from.

## Why a fresh pass was required at all

The August review is a statement about the code against an August `main`. Six
commits touched `lib/core/services/` since the merge-base; `sync_service.dart`
alone moved four. **Git auto-merged every `lib/` file with no conflict, and
auto-merge means textually compatible, not semantically correct.** The pass was
scoped at that gap specifically.

**It found no functional defect** — the reviewer ran the suite (9/9) and performed
its own independent mutation (`proStateSnapshot()` -> `isPro()` -> 8 pass / 1 red)
rather than trusting the diff. Every finding was in the documentation layer, and
one of them was hard-blocking.

## Ground truth verified — each of these was RUN, not reasoned

- **`check_sot_registry_parity.dart` FAILED on the staged tree** (EXIT=1, 2 errors)
  and PASSES on clean `main` (EXIT=0). The commit was literally unlandable.
- **The reviewer's stated CAUSE for that was wrong, and checking is what found it.**
  It blamed four intervening commits on `main`. Main passes. The shift comes from
  THIS diff's own insertions into `sync_service.dart` moving every method below
  them — CLAUDE.md §4.9's "extracting or moving code breaks source-grep contracts
  in files you never touched", in its adding-code form.
- **The gate rejected my first fix for F1.** Citing the precise call site
  (`974-977`) failed because the gate requires the method NAME inside the range;
  the call site does not contain it. Corrected to the declaration span `871-1004`.
  Precision and gate-satisfiability are different targets.
- **The PRO sink guard still discriminates on today's main**, not merely runs:
  neutering it reddens **4 of 9**.
- **F5 measured, not argued**: `grep -c realtime_subscribe_skipped_free_tier
  lib/core/services/error_telemetry.dart` -> 0.
- **F3 measured**: 30 single-number vs 640 dash-form `line_range:` entries.

## An error of mine, recorded because the shape recurs

**I ran the parity gate mid-cherry-pick — after 1 of 3 commits — and reported
PASS.** The two later commits are what broke it. A gate run against a partial tree,
reported as validation of the whole. Fourth instance of
`feedback_green_check_input_set_width` in this session, and the second where I was
the one who narrowed the input set.

## Residues, stated rather than closed

1. **OI-180** — the parity gate skips single-number `line_range:` entirely (30 of
   670), and its dash-form check is satisfied by a *reference* to a method rather
   than its definition. Filed rather than fixed: `scripts/**` is platform-tier and
   needs its own gate test plus a rule-24 ledger entry.
2. **Free -> PRO upgrade latency is by design** — a newly-upgraded user starts
   receiving realtime on the next `AppLifecycleState.resumed` or the next
   `checkAndSync`, not instantly. Unchanged by this batch; stated so it is not
   later read as a regression.
3. **The dev-panel PRO toggle bypasses `_downgradeLocally`**, so QA revoking PRO
   there does not exercise the teardown hook. Pre-existing, documented, not
   user-reachable.
