---
reviewed_at: 2026-06-03T02:30:00+05:30
staged_against: f7e3a1 (nutrition sync-ID sweep, folded into apk-obs-2026-06-02)
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, natural_key_correctness, deploy_ordering, function_exception_swallow, secrets_in_tree]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — nutrition sync-ID sweep (f7e3a1)

Scope: `sync_nutrition.dart` (`_syncNutritionLogs` items loop + `_syncSavedMeals`),
migration 083, contract test extension. A fresh context-blind Sonnet reviewer was
told the live schema facts and asked to break the natural-key design.

## Finding 1 — P2 — writer/restore Hive-key drift on saved meals — SURFACED (distinct, pre-existing)
- **file:line:** `lib/core/services/nutrition_write_service.dart:557` (writer) vs `lib/core/services/sync/sync_nutrition.dart:481` (restore)
- **claim:** `saveMealPreset` keys Hive by `saved_meal_<millisecondsSinceEpoch>`; `_restoreSavedMeals` derives `saved_meal_<nameHash>`. They don't collide → a restore writes a SECOND local copy of each saved meal (local duplication on reinstall/device-switch).
- **verified by me:** TRUE — read `nutrition_write_service.dart:557` (`'saved_meal_${now.millisecondsSinceEpoch}'`). Contradicts the SoT registry's stated `key_formula` (name-hash) and my own (now-corrected) code comment. This is the rogue-key-formula / writer-contract-drift class (debugging §2.12), **distinct from the cross-user collision this batch fixes** and NOT worsened by it (the cloud `(user_id,name)` key dedups server-side regardless).
- **disposition:** **FIXED (b8d5c2)** — founder chose "fold it in too". Writer → canonical `savedMealKey` (UUID v5: stable + collision-free) + `SavedMealKeyMigrator` re-keys legacy rows + a canonical-key gate (`check_saved_meal_key_canonical.dart`). Its own B-pass found 5 (F1/F3/F4/F5/F6 — 4 fixed incl. the v5 swap; 1 surfaced). Also caught + fixed **2 stale `_syncSavedMeals coerces id via _deterministicId` contract tests** that f7e3a1 had left asserting the reversed (pre-omit-id) contract — they false-passed on f7e3a1's own explanatory comment.

## Finding 2 — P1 (→ cosmetic) — item_index backfill tie-break may not match emit order — FIXED/CLOSED
- **file:line:** `migration 083` backfill `ORDER BY created_at, id` vs client `i`
- **claim:** when two items share `created_at`, the id-tiebreak may not match the client's emit order → an existing item could land one position off.
- **analysis:** worst case is a one-time cosmetic position SWAP on first re-sync — **never data loss** (row_number gives distinct indices → both rows survive; verified live: 0 dup `(log_id,item_index)`). New logs are always exact.
- **disposition:** **CLOSED** — `_restoreNutritionLogs` now sorts restored items by `item_index` (content returns in emit position → swap invisible to every reader); migration comment corrected to not overstate the ordering guarantee.

## Finding 3 — P3 — `'Unnamed Meal'` fallback merges distinct nameless meals — FIXED
- **file:line:** `sync_nutrition.dart` `_syncSavedMeals` (the `meal['name'] ?? 'Unnamed Meal'` fallback I introduced)
- **claim:** with `UNIQUE(user_id,name)`, two nameless meals collapse to one row.
- **disposition:** **FIXED** — replaced the fallback with a null/empty-name guard that skips + emits `sync_skipped_null_natural_key` (mirrors the `nutrition_logs` null-natural-key guard). `saveMealPreset` already rejects empty names, so this only fires on corrupted/legacy rows.

## Finding 4 — P3 — deploy-ordering 23502 for an old client — ACCEPTED
- **claim:** once `item_index` is NOT NULL, an old client (no `item_index`) 23502s on item inserts.
- **disposition:** **ACCEPTED** — explicitly documented in the migration header (ships WITH the APK, same posture as 082); the failure is caught + telemetered, not silent.

## Lenses clean
- writer_reader_drift: restore paths don't depend on the omitted `id`; `item_index` consumed only as the sort key. `_restoreSavedMeals` still reads `id` only as an empty-name Hive-key fallback (column still exists).
- function_exception_swallow / unawaited_no_error_sink: every upsert keeps its try/catch + `recordNonFatal` + `_reportSyncFailure`; the new guard adds an `unawaited(logEvent)` sink.
- secrets_in_tree: none.

## Verdict: accepted
2 findings fixed in-batch (F2 closed via restore-sort + comment fix; F3 guard added), F4 accepted-as-documented, F1 surfaced as a distinct pre-existing follow-up. Re-verified: analyze clean, contract test 8/8.
