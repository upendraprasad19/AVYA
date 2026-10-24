---
branch: coach-measurement-sheet
date: 2026-10-11
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-measurement-sheet-bpass.md
---

# Plan-review record — L2b Landing A: measurement bounds (`coach-measurement-sheet`)

Plan: `docs/plans/coach-measurement-sheet-l2b.md` (v3.1). This record covers **Landing A** only — values bounded where they enter (chat parse, writer) and where the coach reads them; account tier; live for every user, no flag. Landing B (the dark measurements sheet, platform tier) and Landing C (the Progress Comparison card and the chat chip) are in the same plan but are NOT covered by this record: each is reviewed again against the merged A and gets its own record (`coach-measurement-sheet-ui.md`, `coach-measurement-surfaces.md`). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (v3.2, landing L2: OI-297, OI-304).

`bpass: accepted` (2026-10-11, `docs/reviews/coach-measurement-sheet-bpass.md`): three fresh context-blind Sonnet reviewers on commit `c8bc98e8` (A: production code; B: the tests, with 32 proposed mutants; C: documents and claims), 34 findings (0 P0, 0 P1, 7 P2, 27 P3, 0 false alarms), every one fixed, accepted with its reason, or recorded as an equivalent. The record gate requires `bpass` only from `platform` up; A takes it as a deliberate extra. The flip is in the same commit that adds the review file, never before it. The review corrected one claim of the code commit: `c8bc98e8`'s message (not rewritten) says NaN and Infinity were storable through the chat path, but no in-repo producer exists (the proxy turns Infinity into `null` and rejects a bare `NaN`); the reachable defects are absurd finite values, a wrong-typed model field and a future-dated record, and the non-finite chain is a latent hazard with no producer in the tree (corrected in Landing B: the sheet's input field cannot produce a non-finite value either, because its input formatter keeps only a leading digit prefix; the guard is defence in depth).

## Rounds

- **Round 1** (v1, which bundled the bounds with the dark sheet, five entry points and the OI-304 deletion; three context-blind Sonnet lenses: ground truth, design and data, UX / flag / process): 0 P0, 7 P1, 23 P2, 22 P3 (52 findings). Seven P1 across the lenses (the second Weight-sheet call site, a first commit that would not compile, Gate 7, the auth-watch contract, the pin inventory, the dead-card deletion orphaning a detector) meant, by §4.12.1, that the unit was too large: it was **split** into Landing A (a separable defect fix) and Landing B (the dark feature), and the OI-304 deletion left the plan.
- **Round 2** (v2, the post-round-1 plan; three lenses: ground truth, design / data / safety, UX / flag / tests / process): 0 P0, 0 P1, 13 P2, 22 P3 (35 findings). Eight P2 asked whether a protection could fail a test, two were design gaps (a failed history read looking like "never measured", a rounding step that could throw), three were about the split rule (B still changed the live chat writer, A's "no lever" ruling was the author's own, B was still too large). v3 moved every live change into A, split E3 and E4 into Landing C, and turned A's §4.6 position into a founder question.
- **Round 3** (v3, scoped to Landing A's text; two lenses: ground truth and design, tests / mutants / gates / process): **CONVERGED** — 0 P0, 0 P1, 6 P2, 15 P3 (21 findings), all mechanical and adopted in v3.1: a missing fixed-point precondition on the bounds (A5's equivalence rested on it), an incomplete bug-history lookup (`4e8f1b`, `a3f6c9`, `f8c1a5`), a dead `isFinite` guard, an unmutatable registry-check mutant, a tie-break whose mutants one fixture could not kill, the B-pass commit and its three artefacts missing from the commit list, ledger labels, citations, and test-spec gaps. None reopened a design decision.

`review_rounds: 3` counts the rounds on this unit's lineage; review #2 ran on the post-review-#1 plan (§4.12.1) and round 3 on the post-review-#2 plan. Every finding of every round has a row in plan section 10.

## Ground truth verified

Reviewers, read-only; the coordinator independently re-verified every adopted claim against the code or by probe before editing the plan. The writers and readers of `measurement_<istDate>` (three writers, two Dart readers, one Edge Function reader; `logMeasurement` has one caller), the three `valueCm <= 0` guards, the default merge-safe push filtering non-finite sites, the old snapshot reader's unguarded casts and its place in the snapshot push chain (`pushSnapshotNow` → `compileDailySnapshot` → `buildAiContext`), the registry and gate mechanics (Gate 7, `check_sot_registry_parity` pins, Gate 40 requirements, the plan-review record gate's `bpass` rules, the tuning-history gate on any added `docs/reviews/*.md`), the L2a commit shape (`dec69fc8` ledger with `commit: PENDING`, B-pass commit `9208c495`, stamp commit `79e866a2`), and the sibling bug records. Probed on the pinned Dart 3.11.1 (standalone script, not committed): `double.parse(v.toStringAsFixed(1))` returns NaN and ±Infinity unchanged while `(v * 10).round()` throws `UnsupportedError`; all five bounds are fixed points of the rounding and 70.25 rounds to 70.3; `jsonDecode('1e999')` is Infinity; `DateTime.utc(2026, 13, 45)` and `DateTime.tryParse('2026-13-45')` both normalise instead of failing, and `tryParse` accepts `20261001` and timestamps; a small `List.sort` is stable. Not independently verifiable (stated in the plan): the live-database counts of G2 (reviewers had no database access), the out-of-repo Telegram writer, the Flutter internals cited by Landings B and C (outside this record).

## Reviewer process notes

Round 2 lens B made one stray `python3 -` call with an empty heredoc (no program text, no effect). Round 3 lens A made one such call, ran `which flutter`, used `cut` / `tr` / `fold`, shell loops and `printf` / `echo`, read Flutter SDK and pub-cache files by absolute path and listed `/home/ubuntu` and `/home/ubuntu/fvm` (all read-only), and made one tool call with a lowercase tool name that failed with "No such tool". Round 3 lens B made one `awk` line filter, one such empty `python3 -`, used `cut`, shell loops and `echo`, and read SDK and package sources outside the repository (read-only). Every reviewer reported these itself; none wrote a file, touched the network or a database, ran anything under `scripts/` or `.claude/`, changed git state, or read `~/.claude`.

## Founder decisions

Answered by the founder on 2026-10-11, all as recommended: **D6** (A ships with no kill switch), **D8** (the sync push is bounded in L2c, with the per-site pending set, not in A) and **D5** (the bounds table is confirmed as written; it is live from A). **D7** (E3 and E4 split into Landing C — recommended) concerns B and C, not A, and is asked once A has merged. D2, D3, D4 and OQ-L2a concern B and the flip. All are listed with recommendations in plan section 6.

## §4.6

A ships with no lever (D6, recommended): it only hides values no body produces, the golden fixture proves identical coach context on clean data, the old reader throws on corrupt records (and a throw there also stops every snapshot push, because the push compiles the same snapshot), and the rejection event (`measurement_value_rejected`, site and below / above / nonfinite, never the number) is the observation. An answer of "lever" sends A back to review before it is built. Landing B's new surfaces are dark behind `enable_body_measurements`, default OFF, with its own full ×2 required again at the flip.
