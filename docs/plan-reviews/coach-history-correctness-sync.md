---
branch: coach-history-correctness-sync
date: 2026-10-06
blast_radius: platform
review_rounds: 9
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-history-correctness-sync-bpass.md
---

# Plan-review record — L1a-1 exercise-log cloud rows: one live summary, deletes that land (`coach-history-correctness-sync`)

Plan: `docs/plans/coach-history-correctness-sync.md` (v10). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L1). Fixes OI-312 (deletes never reach the cloud) and the writer half of OI-307 (superseded summary rows stay live).

`bpass: accepted` — two B-pass rounds on the code (2026-10-06, `docs/reviews/coach-history-correctness-sync-bpass.md`): round 1 found a second-apply defect (fixed: ALREADY_APPLIED guard) and unpinned key predicates; round 2 found no migration defect and seven test/recipe gaps; all fixed. 57 mutants, 55 red, 2 equivalent.

## Lineage and rounds

Every round used fresh context-blind reviewers with an exhaustive read-only tool allow-list (no scripts, no database statements); every load-bearing claim a reviewer made was re-checked by the coordinator against the code or with read-only live SQL before it was acted on.

- **R1–R3** reviewed "L1a" as one unit (server migration + restore + push + deletes + pass serialisation). Each round found new P1s; after R3 the unit was split (§4.12.1): this plan keeps only the server migration whose core mechanics R3 verified; client work went to L1a-2 (`coach-history-correctness-client.md`) and later L1a-3.
- **R4** (v4): Supabase-branch dry-run impossible here (precedent `oi-182-202-subscription-state.md:92`) → prod rolled-back `DO`-block dry-run; uuid/text cast; per-key advisory lock; `age(xmin)`; precondition form.
- **R5** (v5): pair repair across the whole duplicate group; harness cases; mint without `--stub`; apply-step protections; R4 residual cost restated.
- **R6** (v6, P2 only): exception-clause subtransactions for ordered xids; name-based live migration check (`version` is a timestamp); before-phase-only repair cases.
- **R7** (v7, P2 only): `LOCK TABLE … ACCESS EXCLUSIVE` first; end-state assertions; per-phase expected outcomes; precondition (b) narrowed, (c) dropped.
- **R8** (v8): end-state check restricted to baseline OI-312 pairs; replacement mutation; per-set snapshot + rollback re-insert.
- **R9** (v9, P2 text only, design confirmed sound): post-apply check reads the pair ids from the snapshot; mutation prediction corrected. **Converged** — R9 is mechanical-only (`mechanical_only: true`).

`review_rounds: 9` counts every round on this lineage (R1–R3 on the combined unit, R4–R9 on this plan).

## Ground truth verified (coordinator, read-only, 2026-10-06)

V1 44 duplicate groups / 99 rows / 1 account; V4 0 tombstones; V10 rolled-back probe reproducing OI-312; V11 youngest-`xmin` = highest `set_number` in 44/44; V12 0 per-set rows above the kept count; V13 `workout_log_sets.workout_log_id` is `uuid`; V14 45 orphan per-set rows, unreachable; V15 0 rows in the missing-date bucket; V16 0 count-0 summaries.

## Founder decisions (2026-10-06)

1. "Last sync or write wins" — cleanup keeps each group's last push; the latest push supersedes.
2. Prod rolled-back `DO`-block dry-run approved in place of a Supabase branch; the dry-run and the apply each still need their own go.
3. R5 (same-second cross-device per-set interleave) accepted.
4. (L1a-2, corrected 2026-10-06) "Newest action wins": a delete removes only versions written before it; a later re-log on another device survives everywhere (L1a-2 §10).

## §4.6

No flag: a switch cannot restore tombstoned rows. Protection = preconditions, snapshot, dry-run with per-phase expected outcomes, rollback recipe, founder go per live step.
