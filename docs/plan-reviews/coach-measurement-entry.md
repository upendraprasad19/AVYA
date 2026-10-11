---
branch: coach-measurement-entry
date: 2026-10-11
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-measurement-entry-bpass.md
---

# Plan-review record — L2a merge-safe measurement push and one site registry (`coach-measurement-entry`)

Plan: `docs/plans/coach-measurement-entry-l2a.md` (v3.1). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L2, OI-297 / OI-304; the spec and both OI entries exist only on branch `coach-progress-review`). L2 is split into L2a (this record) and L2b (its own plan and record, written after L2a lands).

`bpass: accepted` (2026-10-11, `docs/reviews/coach-measurement-entry-bpass.md`): two fresh context-blind reviewers on commit dec69fc8, 13 findings (0 P0, 0 P1, 1 P2, 12 P3, 0 false alarms), all fixed or triaged. The flip is in the same commit that adds the review file, never before it.

## Rounds

- **Round 1** (v1; lens A ground truth, lens B design / data-sync safety / test adequacy): 0 P0, 0 P1, 15 P2. Reshaped the scope: the provider, the multi-site writer, `snapshotManual` feeding and the bounds had no consumer in L2a and moved to L2b; the mechanism claim was corrected (a Map upsert body sends no `columns=`; the omit-key outcome is PostgREST's documented behaviour, asserted by repo precedent, not observed); both stale-overwrite and old-client residuals were stated.
- **Round 2** (v2; same two lenses, the second adversarial): lens A 1 P1 (the new constants file is reached by the sync engine and fails `blast_radius_sync_engine_platform_test` unless declined), 2 P2, 11 P3; lens B 0 P1, 7 P2. Reshaped U1: one payload builder, a fingerprint over the legacy-shape content (so upgrade and kill-switch toggles re-push nothing), the HEAD wire bodies and fingerprints captured from the unmodified tree and pinned as literals, the pull rule extracted into a pure function because the pull is unreachable by any test.
- **Round 3** (v3; scoped to the deltas): CONVERGED, 0 P0/P1, 2 P2 + 4 P3, all mechanical and applied in v3.1 (suppress `logMeasurement`'s background pass in the flow test with `pausedForSimulation`; seed an index entry so the `liveKeys.add` mutant is observable; the fingerprint-identity claim narrowed to records the in-repo writers can produce; the cloud-model closure returns `null`; a single `kTestUserId` source for the pins; the rules file imports only the constants file).

`review_rounds: 3` counts the rounds on this unit's lineage; review #2 ran on the post-review-#1 plan (§4.12.1) and round 3 on the post-review-#2 plan.

## Ground truth verified (reviewers, read-only; coordinator re-verified the cited gate, pub-cache and kill-switch claims)

HEAD's push payload and skip index (`sync_health.dart:254-305`, `sync_skip_index.dart:103-113`), the three writers and readers of `measurement_<date>`, the five Dart site lists and the two Edge Function prose lists, `postgrest-2.9.1` `upsert` (no `columns=` for a Map), the stub-server seams (`writeResponders`, `pagedTables`), the blast-radius engine test mechanics, the kill-switch pattern and its debug-only reach (OI-95, ADR-0020), `SYNC_EPOCH_RESYNC.md:54`, and the HEAD body and fingerprint literals (captured by a throwaway test on the unmodified tree, then deleted).

## Reviewer process notes

Round 1 lens B ran two read-only `git ls-remote --heads origin` calls (a network call outside its allow-list); nothing was written. Round 2 reviewers used a few read-only `grep` / `cat` / `sed` and one `python3` JSON read outside the exact list. All were reported by the reviewers.

## Founder decisions

None needed for L2a to ship. The standing rule "Last sync or write wins" (L1a, 2026-10-06; recorded in `docs/plan-reviews/coach-history-correctness-client.md` under Founder decisions, item 1) is what the stale-overwrite residual rests on; the B-pass added the cross-channel pull fill to its trigger list and pinned it with a test. OQ-L2a (a server-side guard against old clients sending nulls) is recorded in the plan with a recommendation (none for L2a) and is re-asked as the L2b entry criterion, before `enable_body_measurements` flips.

## B-pass fixes (after round 3)

Product code: none changed except one `@visibleForTesting` seam, `SyncService.pullMeasurementsForTest` (the cross-channel pull is unreachable without a signed-in user; precedent `restoreWorkoutPlanForTest`). Tests: the pull tests, the kill-switch all-null record, the empty-row fixture moved first, a deterministic NaN-test observable, the rules boundary and identity tests, a lib-wide derivation scan with scanner negative controls, and a behavioral test of the two chat whitelist call sites. Docs: the registry-coupling claims qualified, the residual trigger list completed, the closure ledger rebuilt in the order the L1a-3 ledger used, the SoT behavioral path repointed, and OI-332 filed for the weight and sleep sibling pushes (latent: live 2026-10-11 `sleep_logs` 0 rows, `weight_logs` 69 rows with 0 notes).

## §4.6

New behaviour sits behind `disable_measurement_merge_safe_push` (default ON, old payload byte-identical when set); it is a local `configBox` lever, not remote config, and the plan says so.
