---
branch: coach-measurement-entry
date: 2026-10-11
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — L2a merge-safe measurement push and one site registry (`coach-measurement-entry`)

Plan: `docs/plans/coach-measurement-entry-l2a.md` (v3.1). Umbrella: `docs/superpowers/specs/2026-10-03-progress-review-design.md` (landing L2, OI-297 / OI-304; the spec and both OI entries exist only on branch `coach-progress-review`). L2 is split into L2a (this record) and L2b (its own plan and record, written after L2a lands).

`bpass: pending` — the B-pass runs on the code before the merge and this field becomes `accepted`, with a `bpass_review:` file, in that commit.

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

None needed for L2a to ship. OQ-L2a (a server-side guard against old clients sending nulls) is recorded in the plan with a recommendation (none for L2a) and is re-asked as the L2b entry criterion, before `enable_body_measurements` flips.

## §4.6

New behaviour sits behind `disable_measurement_merge_safe_push` (default ON, old payload byte-identical when set); it is a local `configBox` lever, not remote config, and the plan says so.
