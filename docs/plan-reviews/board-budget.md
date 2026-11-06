---
branch: board-budget
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/board-budget-bpass.md
---

# Plan review — board-budget (context-artifact token reclaim + budget gate)

Reclaim the tokens the open-issues board was costing, then stop it recurring. **Platform**
tier — `CLAUDE.md` (`blast_radius.yaml:68`) and `scripts/`, independently.

Shipped in four units: archive 27 CLOSED entries out of `open_issues.md` (−46%); cap the
`Blocked on` / `Verified` columns in `build_oi_index.dart`'s render; add
`check_context_artifact_budget.dart` + pure `context_budget_lib.dart` guarding the byte
size of the always-loaded set; correct the stale claims in `CLAUDE.md` and add lens **L54**.

**The measured problem** (all re-derived at review time, not carried from the plan):
`open_issues.md` 67,895 → 357,664 B over 31 days (~2,600 tok/day); `OPEN_INDEX.md`
3,759 → 18,958 B against a CLAUDE.md §7 claim of "~950 tokens" that was TRUE when written
(`e4bc9040`, 2026-07-29) and that nothing re-derived for a month.

## Review rounds

**Round 1 — context-blind, on the drafted implementation. 6 findings, 0 false alarms.**
Two P1. (a) The budget gate had **no mirror**: every negative drift was `ok`, so a
`CLAUDE.md` truncated to zero bytes reported `PASS: 3 within band`. The one shrink test
exercised the batch's own −45.5% reclaim and stayed green under the bug — the
author-blind-spot shape §4.12 names. (b) The **headline fix had no test**: reverting the
render cap left all 26 tests in `oi_index_test.dart` green. Four P2s were stale or
misattributed numbers, including "+427%" pinned to the wrong filename inside the gate whose
subject is stale numbers. Round 1 also independently reproduced all three mutation claims.

**Round 2 — on the HARDENED result. 4 findings, 0 false alarms, 2 of them created by round
1's own corrections.** (a) Round 1 made the classifier two-sided and left the **report**
hardcoding the growth thresholds and the verb "grew", so the very fixture round 1 built
printed *"grew past the 50% hard band"* for a file that shrank 100%. (b) The corrected
7-day rate was **wrong in magnitude and direction** — ~1,910 tok/day, not ~3,200, and
slower than the average rather than faster. Root cause worth more than the number:
`main@{7 days ago}` is a **reflog** query, not a date query; it resolved to a commit dated
2026-08-18, a 12-day span divided by 7. Plus a mis-round and stale line citations.

**Round 3 — B-pass (`docs/reviews/board-budget-bpass.md`). 5 findings, 0 false alarms.**
Its best finding is one both earlier rounds read past: `--record` executed **before** the
report, so re-baselining blessed whatever was on disk with no comparison and no trace —
and the FAIL path printed `--record` as its own escape hatch. Found by opening the gate the
docstring claims to mirror (`check_apk_size_within_bounds.dart`) and diffing: Gate 13's
`exit(1)` sits ABOVE its record step, and this gate had inverted that ordering. Also: no
re-baselining trigger (the gate would have blocked every commit in ~10–14 days), a citation
wrong for the third time, and a retracted figure still live in `LENS_REGISTRY.md`.

## Convergence

**Converged, and the trend is why.** Round 1 found structural defects (a missing mirror, a
missing test). Round 2 found consequences of round 1's fixes. Round 3 found one real design
gap plus three instances of a single class — stale claims surviving a correction — and
nothing new about the mechanism. Severity fell (2 P1 structural → 2 P1 derived → 1 P1 design
+ documentation), and no round re-opened an earlier round's finding.

§4.12.1's split signal was **considered and rejected on the merits**: the unit is one gate,
one render cap, and the docs describing them, and the pieces are not separable — the gate
needs its baseline, and `CLAUDE.md` documents the index the cap changed. Splitting would
have produced fragments that could not be reviewed independently, not smaller units.

## Ground truth verified

Every numeric claim in this batch was re-derived from `git show`/`wc -c` rather than carried
forward — twice, after two rounds found stale ones. Mutation counts were re-measured against
the same 37-test baseline after every suite change (they had gone stale at 29 and again at
35 *within this batch*). Gate freshness (`OPEN_INDEX.md`, `GATE_INDEX.md`,
`diagnoses/INDEX.md`) confirmed byte-identical to regenerated output. The CRLF/LF risk to a
byte-size baseline on Linux CI was checked against `.gitattributes` (`eol=lf` repo-wide,
tree is 0-CRLF). Board archival reconciled at 147 headings and 6 wave headers before and
after.

## Residuals

**None.** All 15 findings across three rounds fixed in-batch (§4.2). One diagnose-doc,
`d7f3b1`, covers the shrink-floor defect; the recurring class is recorded as instance #19 in
`feedback_mistake_guard_without_its_mirror.md`.

⚠ **Not yet run at the time of writing: the full `flutter test` suite.** Verified so far is
52 targeted tests (25 lib + 15 e2e + 29 `oi_index_test.dart` counted separately), the full
pre-commit gate loop, and five mutation legs. Pre-push at platform tier is the full-suite
gate and it runs before this merges — load-bearing here, because the new e2e spawns 15 real
subprocesses, the documented class that passes targeted and fails under suite contention
(its timeout was raised 4 → 6 min for exactly that).
