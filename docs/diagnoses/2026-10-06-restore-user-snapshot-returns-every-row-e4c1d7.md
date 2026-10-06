---
bug_id: e4c1d7
date: 2026-10-06
batch: streak-freeze-restore-ownership (addendum A, Slice B1: the restore-user-snapshot Edge Function returns EVERY row and is scoped on every read)
status: fixed
blast_radius: platform
symptom: |
  The single-call restore (Edge Function restore-user-snapshot) silently returned at most 1000 rows per table. PostgREST clamps every response to db-max-rows (1000 on this project) with HTTP 200 and error === null, and the function read eleven tables with one .range(0, 49999) or with no limit, plus two bare selects (user_custom_exercises, user_custom_foods); ai_coach_interactions kept the OLDEST 1000. A long-history account therefore restored an incomplete bundle that the client accepted as complete, and the streak-decay reckon then ran against incomplete schedule and completion rows. Found while reading the function in full for the streak-restore batch; no account is affected today (largest per-user count measured 513, workout_log_sets). Separately the function runs as service_role (RLS bypassed) and its scheduled_workouts.template embed was scoped only by a caller-writable foreign key (Hermes C13, open since 2026-07-30).
concept: restore_user_snapshot_paged_reads
sot_registry_entry: restore_user_snapshot_paged_reads
writers:
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "readPaged (pages every table until an EMPTY page through _shared/paged_fetch.ts fetchAllPages; applies .eq(user_id, vUid) itself, first, on every page; charges a per-request page budget)", line: 264 }
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "PAGED_READS (the thirteen manifest entries: legacy select string, window filter, primary sort, plus created_at/id tie keys, each order term with an explicit direction)", line: 100 }
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "readCoachNewest (newest 1000 coach rows, ascending in the bundle; scoped; throws on error)", line: 321 }
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "scopeEmbed (a template embed owned by another user, or any non-plain-object embed, becomes null; owned embed loses user_id)", line: 235 }
  - { file: supabase/functions/restore-user-snapshot/index.ts, method_or_widget: "serve handler (one createPageBudget per request, thirteen readPaged calls, readCoachNewest, per-request row-count log line)", line: 102 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_attemptSingleCallRestore (validates the bundle fail-closed and applies each table through the same _restoreX loops; a 500 from this function makes it return null and the verbatim legacy fan-out runs)", line: 2215 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts (reads only deleted_at, name, workout_type and template_exercises of the embed; a null embed is already handled)", line: 2310 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs (keeps the FIRST row per natural key: the tie order matters here)", line: 861 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_restoreCoachInteractions (keys each row coach_<created_at ms>; order-independent)", line: 278 }
  - { file: lib/core/services/sync/sync_community.dart, method_or_widget: "_restoreCustomExercises / _restoreCustomFoods (first row per lower-cased name wins)", line: 319 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods:
  - _attemptSingleCallRestore
  - _restoreWorkoutLogs
  - _restoreExerciseLogs
  - _restoreScheduledWorkouts
  - _restoreCoachInteractions
  - _restoreCustomExercises
  - _restoreCustomFoods
cloud_table: null
cloud_columns: null
contract_test_path: supabase/functions/restore-user-snapshot/paged_reads_test.ts
ist_handling:
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, line: 40, fn: "SINCE / SINCE_DATE: the restore window bound, UTC, unchanged from the legacy client; no IST date key is derived or compared in this slice" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "true: service_role bypasses RLS, so the function body is the only guard. readPaged and readCoachNewest apply .eq(user_id, vUid) themselves (never manifest data), first, on every page; vUid is re-validated with the ONE exported UUID_RE; an unknown table name or a spent/missing page budget throws before any query; the scheduled_workouts template embed is owner-scoped; every tables[...] assignment in index.ts is pinned to mention vUid"
forbidden_patterns_checked:
  - { pattern: "a bare .range(0, N) with N >= 1000, or a read with no limit, in restore-user-snapshot/index.ts", absent: true }
  - { pattern: "a table read that does not carry vUid (service_role bypasses RLS)", absent: true }
  - { pattern: "a second UUID_RE definition in index.ts", absent: true }
  - { pattern: "a readPaged call without the per-request budget, or a second createPageBudget() in the handler", absent: true }
  - { pattern: "an .order() term without an explicit direction (supabase-js defaults ascending, the Dart client descending)", absent: true }
  - { pattern: "a Promise.all over the paged reads (they are sequential on purpose: one budget, bounded memory)", absent: true }
proposed_fix: |
  1. New supabase/functions/restore-user-snapshot/paged_reads.ts: a PAGED_READS manifest (thirteen tables) and readPaged(db, vUid, name, budget). Each read keeps its exact legacy select string (embeds included), window filter and primary sort; the only additions are created_at / id tie keys so two page requests can never skip or duplicate a row that shares the sort key. user_custom_exercises / user_custom_foods (no order before) are ordered [created_at, id].
  2. readPaged goes through fetchAllPages (offset advances by rows received, stops only on an EMPTY page, maxPages guard), so a server cap below the page size still returns every row. It applies the user_id scope itself on every page, throws on an unknown name, an unvalidated user id, a failed page, beyond 51 pages for one table (the legacy client's 50,000-row ceiling plus the confirming page) and when the request's shared page budget (TOTAL_PAGE_BUDGET = 120) is spent. Any throw becomes the function's existing 500, which the client answers with its verbatim legacy per-user-JWT restore (fail-closed; a partial restore is not reachable).
  3. readCoachNewest keeps the NEWEST 1000 coach rows (created_at desc, id desc, reversed to the bundle's ascending shape); it used to keep the oldest 1000.
  4. scopeEmbed closes Hermes C13: the template embed selects the template's user_id; a foreign, array, primitive or owner-less embed becomes null (the client already tolerates a null embed), an owned one loses user_id so the bundle shape is the legacy one. The owner compare is case-insensitive.
  5. One exported UUID_RE shared by index.ts and the readers; a per-request row-count log line (table names and counts only) so the live behaviour can be read from the function logs.
  6. Non-paged reads are unchanged and recorded clean with their natural bounds (limit 1 / maybeSingle / 20 / 50 / 52 / 200 / 500; referral_redemptions max 3 rows per user live against a cap of 50).
regression_test_planned:
  - supabase/functions/restore-user-snapshot/paged_reads_test.ts
  - test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart
mutation_proof: |
  Rule 21, scratch-copy protocol (copy, mutate, confirm the mutation applied, run, restore by hash, confirm the hash). 32 mutations of paged_reads.ts against the 104-test Deno suite, ALL red: user_id scope dropped (52 red), scope by a wrong value (77), scope no longer first (44), window filter dropped (33), select string replaced (7), SINCE swapped for SINCE_DATE, a tie key dropped from workout_logs / workout_log_sets / custom exercises / water_logs, a sort direction flipped, per-table ceiling removed, budget ignored, budget never charged, budget raised to 100000 or lowered below the floor, failed page swallowed (16), coach scope dropped / wrong value / order flipped / error swallowed, unknown name and unvalidated id no longer throwing, UUID_RE end anchor removed, scopeEmbed passing a foreign / array embed through or comparing case-sensitively, budget trip worded as a sort-key problem, log line leaking a row. 17 mutations of index.ts / paged_reads.ts against the Dart wiring test (nine tests), all red, plus a comment-only control that stays green: a key reading the wrong table, a bare .range read back, a literal instead of vUid, the coach read back to q(), the import removed, an extra bundle key, a key dropped, a read without vUid, a call without the budget, a local UUID_RE, a second budget, the budget hoisted above serve(). Two mutations first SURVIVED and were fixed: an uppercase-uuid test built on an all-digit uuid (toUpperCase() was a no-op), and a wiring test that let the budget be hoisted above the handler. A third was caught by the reviewers, not by a mutation: a Deno case that never put a row older than the window in the fake, so removing the gte filter stayed green.
impact_analysis: |
  Nobody loses data today: the largest per-user row count measured live on 2026-10-06 is 513 (workout_log_sets), the clamp bites at 1000, and live exposure of the template embed is 0 of 22 scheduled rows pointing at another user's template. The defect is for a long-history account (a daily logger passes 1000 rows in workout_log_sets within months) and the cross-user path exists in code. A single-call restore with a clamped table fed the streak-decay reckon incomplete rows, which is why this slice belongs to the streak batch. Measured on 2026-10-06 (read-only): PostgREST clamps a single .range(0,49999) read to 1000 rows with error null; the real fetchAllPages through supabase-js 2.39.3 with the compound order [category, id] returned all 1431 food_database rows exactly once (13 categories, up to 182 rows each, which straddles the 1000-row page seam); referral_redemptions holds at most 3 rows per user. TIE ORDER IS NOT A PRESERVATION CLAIM: for the founder's 44 multi-row workout_log_exercises groups the new order [completed_at, created_at, id] picks the same first row as the physical order (completed_at, ctid) in 28 of 44 and the same as [completed_at, id] in 24 of 44, so a first-wins reader can pick a different summary row than today's undefined order did; the two restore paths already pick opposite rows (the legacy client reads descending, the function ascending), which belongs to OI-307 (reserved on branch coach-progress-review, not on this tree's board). COST: one extra confirming request per paged table (13 for an empty account) and, past 120 page requests in one request (about 100,000 rows in total), the function answers 500 and the client runs its legacy restore; the budget bounds requests, not bytes (the function's memory limit was not verified; a killed worker also answers non-200, the same fallback).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "No Dart production file changed. The consumers were read: _attemptSingleCallRestore returns null before the first Hive write on any non-200 and the legacy fan-out runs; _restoreScheduledWorkouts handles a null template embed; _restoreCoachInteractions is order-independent; the custom-item readers keep the first row per lower-cased name. The wiring test is Dart (test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive key is written or read by this slice; the apply loops are unchanged." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "backups/live_schema_columns.json: all 13 paged tables have id and user_id; the window and order columns exist per table (the Deno test paged_reads_test.ts reads the snapshot and asserts it); created_at exists on user_custom_exercises, user_custom_foods and the two workout tables; referral_redemptions has no user_id (kept on its dual-FK .or scope); workout_templates.user_id is NOT NULL (migration 002)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only on 2026-10-06: referral_redemptions max 3 rows per user; the founder's workout_log_exercises tie groups (44 multi-row groups; first-row agreement 28/44 vs ctid, 24/44 vs id-only); food_database 1431 rows, 13 categories, max 182 per category; per-user maxima from the earlier measurement (513 workout_log_sets). No write." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "Repo code changed (index.ts + new paged_reads.ts). The LIVE function is NOT redeployed by this commit: the deploy needs the founder's per-action go (CLAUDE.md 4.3) and, before it, the checks in the Deploy protocol of the addendum plan section 3 (committed tree only, live multipart fetch hashed against the parent blob, git fetch origin main + a diff of supabase/functions, deno check --node-modules-dir=none, host-shell deploy, anon-key boot check, the expected Smoke FAIL 401 for a verify_jwt=true function, then the per-request rows line compared with a live count). Rollback: deploy_via_api.js --rollback restore-user-snapshot <parent sha>." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not cron-dispatched." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "service_role bypasses RLS, so scoping is code-owned: every read in index.ts and paged_reads.ts was listed and each carries the caller's id (users by id, referral_redemptions by the dual-FK .or, the rest by user_id); scheduled_workouts.template_id is the only child key a caller controls (insert check is auth.uid() = user_id with no check on the FK, migration 002) and is closed by scopeEmbed. The Hermes-style cross-user seat found no P0 or P1." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "paged_reads.ts reads no environment variable and imports only ../_shared/paged_fetch.ts (no import map ships with the deploy payload; the Dart wiring test pins the import list). The live paging proof used the public anon key against a table anon may read; no secret was read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Supabase only." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The bundle shape is unchanged for an account under 1000 rows per table (select strings byte-identical to the old source, checked three ways: extracted fixture, the reviewers' hand comparison, and the Deno oracle test); 29 bundle keys equal SyncService.singleCallBundleKeys (pinned by the wiring test); a 500 sends the client down its legacy path, never a partial write." }
recurrence: "Same class as OI-79 (PostgREST db-max-rows clamp: paged_fetch.ts exists because of it) and Hermes C13 (cross-user read under service_role). First time this Edge Function was covered; the legacy client already paged. Not a recurrence of a fixed instance in this function."
related_bugs: [e6b9c4, c9d2f6, b4e7a1]
---

# e4c1d7 — the single-call restore returned at most 1000 rows per table

## What happened

`restore-user-snapshot` assembles a user's whole restore bundle in one service_role call. Eleven of its reads used one `.range(0, 49999)` or no limit, two were bare selects, and the coach read took `.order("created_at").limit(1000)`. PostgREST answers every one of them with at most 1000 rows, status 200 and `error: null`, so a truncated table was indistinguishable from a small one. The legacy client loop pages; this function never did.

## Writer / reader map

Writers: `paged_reads.ts` (manifest, `readPaged`, `readCoachNewest`, `scopeEmbed`) and the handler in `index.ts`. Readers: the client's `_attemptSingleCallRestore` and the `_restoreX` apply loops listed above; the tie-order-sensitive ones are `_restoreExerciseLogs` and the custom-item restores (first row wins).

## Fix and what it deliberately does not do

See `proposed_fix`. It does not change the response shape, does not touch the non-paged reads, does not deploy, and does not claim to keep today's winner among tied rows (see the impact analysis). A hostile case was considered: a user can write unbounded rows of their own, so one request could have fanned out to 13 tables x 51 pages; the shared page budget bounds that at 120 requests, and the cost is that an account above about 100,000 rows in total restores through the slower legacy path.

## Verification

104 Deno tests (a fake database that clamps every response to 1000 rows, reshuffles tied rows on every request unless the order ends in the unique id, holds a second user's rows and a foreign template, and can fail any page; every case runs over all thirteen tables), a Dart wiring test over the comment-stripped `index.ts`, the live paging proof, and the mutation table above. Review: three context-blind Sonnet seats over two rounds (correctness, cross-user security, delta re-review); no P0 or P1; fourteen findings (one P2 in each seat of round one, one P2 in round two, the rest P3), all fixed. The review record is `docs/reviews/restore-user-snapshot-paged-reads-bpass.md`.

## Limits

The function's memory limit and the live nullability of `workout_templates.user_id` were not verified from here (migration text only); the CI Deno job runs the new test with `--allow-all` over `supabase/functions/` and reads `backups/live_schema_columns.json` relative to the test file. The live function is unchanged until the deploy go.
