---
branch: target-history-cloud
scope: Cloud backup of the nutrition target history (Nutrition History Landing B): column user_profile.target_history, merge function merge_target_history (migration 190), client push after the profile upsert, restore merge, profile-map strip
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — Target history cloud backup (Nutrition History, Landing B)

Plan: `docs/plans/target-history-cloud.md` (section 9 = revision 2, section 10 = revision 3;
each overrides what precedes it). Two context-blind rounds, one Sonnet reviewer each, read-only,
round 2 on the plan as revised after round 1. Every claim the coordinator acted on was re-read
in the code first; the live `user_profile` policies and its one trigger were read from
`pg_policies` / `pg_trigger` on 2026-11-25 (read-only).

## Round 1 — needs-changes (5 P1, 6 P2, 4 P3), folded as plan section 9
- P1 order: a migration file cannot be committed before its apply (Gate 14, ledger pairing), so
  the SQL is reviewed and rehearsed as `test/sql/target_history_merge_draft.sql` and becomes
  migration 190 only in the commit of the apply.
- P1 a second cloud-to-profile merge (`mergeCloudProfileWithTargets`, the bootstrapper) would
  copy the list into the profile map: one strip helper on both paths.
- P1 push gating: the reliability branch returns normally on a FAILED upsert; the function
  returns a boolean so "no row" never writes the pushed-memory.
- P1 op type `merge_target_history` would not be swept: `upsert_target_history`.
- P1 `adoptFromCloud` had no owner check.
- P2 the two existing cases U1 reverses; the PRO-unknown restore write (stated limit, exact);
  day-bound memory; concrete non-raising SQL validation; flag rationale; missing tests.
- P3 ties now converge (one total order on both sides); local wipes; wording of the lag.

## Round 2 — converged (0 P0/P1; 6 P2, 5 P3), folded as plan section 10
`COLLATE "C"` on the strategy tie-break; the precedent's owner-changed / sign-out failure branch;
a best-effort push at sign-out; the exact structure of the push call in `_syncUserProfile`; U1
wording in three rule files; a strip at the onboarding upsert; a short hash in the memory;
two stated limits; the ledger shape of the apply commit.

## Deviations from the plan while building
- The strip helper is `TargetHistoryService.stripFromProfile` (core) instead of a function in
  `profile_cloud_merge.dart`: `sync_profile.dart` (core) must not import a feature for it.
