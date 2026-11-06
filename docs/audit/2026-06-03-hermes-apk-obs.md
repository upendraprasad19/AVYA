# Hermes deep-pass — APK obs batch (2026-06-02) — 2026-06-03

Batch: 4 founder APK observations + a catastrophic-tier cross-user sync-ID sweep.
Blast radius: **catastrophic** (sync identity for all per-user tables).
Reviewers: B-pass (fresh Sonnet, 9 lenses) + Hermes deep pass (Opus, 6 deep lenses, live-schema verified).

## Verdict: ACCEPT-WITH-FOLLOWUPS
The catastrophic cross-user collision fix (d4b8e2) is **correctly designed and restore-safe** — independently proven against live schema + data. The fixes ship as code; the one release gate is the deploy-ordering (migration 082 applies WITH the APK).

## B-pass (docs/reviews/68592c4ca73c-review.md) — 2 findings, BOTH FIXED
- **P1** migration 082 missing the 4-tag header → added Intent/Destructive?/Rollback/Linked.
- **P2** DROP+CREATE arbiter-less window → reordered CREATE-before-DROP (no window; avoids nested-txn).

## Hermes deep pass — proven clean (load-bearing claims)
- **No re-key holds** — 0 duplicate-groups on every new key; 0 existing cross-user collisions; NOT NULL non-partial arbiters → CREATE UNIQUE succeeds, existing rows MERGE (not dup) via their unchanged natural key. (live aggregate SELECTs)
- **FK integrity** — no FK references `workout_logs.id` or `workout_log_id`; only `user_id` FKs → omitting the random id orphans nothing. (pg_constraint)
- **Restore round-trip** — every restore reader (`_restoreWeightLogs/_restoreSleepLogs/_restoreMeasurements/_restoreWorkoutLogs/_restoreExerciseLogs/_restoreNutritionLogs`) derives the Hive key from row DATA, never from the cloud id → id-omission is invisible to restore.

## Findings + disposition
| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P0 (deploy gate) | Staged client onConflict 42P10s until migration 082 is live | **Plan** — apply 082 WITH the APK (deploy-ordering); 082 verified safe to apply. Resolved at commit/build. |
| 2 | P2 | Reconciler over-advances PERMANENTLY if `pastPhaseBlocks()` ever over-counts (>28-day spanning corrupted data) | **FIXED in-batch** — `reconciledPhase` refuses a >12-phase jump (corrupted-data guard) + test. |
| 3 | P2 | omit-id sweep MISSED `nutrition_log_items` + `user_saved_meals` (content-hash id + onConflict:'id', no user) — same class, lower probability | **FIXED in-batch (f7e3a1)** — founder chose "fold in now, carefully". omit-id + `(user_id,name)` / `(log_id,item_index)` (POSITION key, never food_name — 12 live legit dup-food groups would merge) + migration 083 (backfill proven live, 0 dup index). f7e3a1 B-pass accepted (empty-name guard + restore-sort); a distinct `saved_meal_<ms>` restore-dup drift surfaced as a new follow-up. |
| 4 | P2 | amar `current_phase=1` + `deployments_complete=11` (sim residue; reconciler doesn't heal — keys off past blocks, amar has 0) | **Note** — test account; real users consistent. Not this batch. |
| 5 | P2 | weekly-report EF ±1-day window edge (IST date-string + UTC time bounds) | **Note** — pre-existing; the Obs-3 macro-target fix is separate + correct. |
| 6 | P2 | `wls/wle_set_number_realistic <= 10` would silently reject an 11+-set summary | **Note** — pre-existing; live max set_number = 8. |

## Follow-ups (post-batch)
1. **Sync-id sweep onto `nutrition_log_items` + `user_saved_meals`** (omit-id + a new user/parent-inclusive UNIQUE index, with item dup-food-name handling) — finding #3.
2. **Harden `pastPhaseBlocks` bucketing** against >28-day spanning blocks (the reconciler clamp covers the worst case; a span-sanity check at the source is the deeper fix) — finding #2.
3. Fix the stale `migration_header_contract_test.dart` reference in `supabase/migrations/CLAUDE.md` (the test does not exist).
