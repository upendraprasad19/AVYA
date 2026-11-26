---
bug_id: a3c8f1
date: 2026-10-08
batch: streak-freeze-restore-ownership (addendum A, Slice C2: the weekly-streak marker goes to the cloud)
status: fixed
blast_radius: catastrophic
symptom: |
  The weekly-streak marker `last_counted_week_key` (the calendar week last counted, Slice D) lived only in the local Hive progress map. A reinstall or a second device restored the counter (`current_streak_weeks`, max-wins on restore, GREATEST on push since migration 156) but not the marker, so the first qualifying session of the CURRENT week after a restore counted that week a second time if it had already been counted. Bounded to one week per restore; no data is lost.
concept: weekly_streak_counter
sot_registry_entry: weekly_streak_counter
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout (the only production writer of progress['last_counted_week_key'], via weeklyStreakAfterCompletion)", line: 2055 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_pushStreakWeekMarker (the cloud writer, via raise_streak_week_marker; called after a successful snapshot push and after a successful conflict retry)", line: 634 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "mergeCloudProgress (restore: last_counted_week_key is the fifth monotonicProgressFields entry, local-max-wins, a cloud double normalised with toInt)", line: 616 }
  - { file: supabase/migrations/157_raise_streak_week_marker.sql, method_or_widget: "raise_streak_week_marker(uuid, integer) (new SECURITY DEFINER function; the only writer of user_progress.last_counted_week_key)", line: 33 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout (reads progress['last_counted_week_key'] as the already-counted guard; now tolerant of a numeric double)", line: 2040 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress (selects the whole row, so the new column arrives without a query change)", line: 976 }
hive_key_prefix: progress
hive_key_formula: "userBox['progress']['last_counted_week_key']; configBox['streak_week_marker_pushed'] = '<userId>:<marker>:<IST day>'; configBox['disable_streak_week_marker_push']"
sync_methods:
  - syncProgressNow
restore_methods:
  - _restoreUserProgress
  - hydrateFromCloud
cloud_table: user_progress
cloud_columns:
  - last_counted_week_key
contract_test_path: test/contracts/streak_week_marker_push_behavioral_test.dart
ist_handling:
  - { file: supabase/migrations/157_raise_streak_week_marker.sql, method_or_widget: "raise_streak_week_marker clamps the key to THIS IST week's Monday: (now() AT TIME ZONE 'Asia/Kolkata')::date, ISODOW arithmetic, minus DATE '1970-01-01'", line: 74 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - streak_week_marker_push_failed
    - progress_restore_demotion_declined
cross_account_guard: "Three layers. (1) The function raises on auth.uid() <> p_user_id (the C1 guard). (2) The client reads the marker from the PRE-await progress map and checks HiveUserSession.currentOwnerFullId == userId before the call. (3) The pushed-marker memory in the SHARED configBox carries the user id and is written only after a second owner re-check, so account A's memory can never be read as 'already pushed' by account B."
forbidden_patterns_checked:
  - { pattern: "a bare marker value in the shared configBox (the next account would read it as already pushed)", absent: true }
  - { pattern: "re-reading userBox['progress'] after the snapshot await to get the marker", absent: true }
  - { pattern: "LEAST(...) applied before the NULL/negative early RETURN (LEAST(NULL, x) is x, so a NULL or -1 would be stored as the Monday)", absent: true }
  - { pattern: "SET LOCAL lock_timeout in the migration (whether apply_migration wraps a transaction is unverified; migration 152)", absent: true }
  - { pattern: "a 14th parameter or DROP on update_user_progress_snapshot (the v4 design, dropped)", absent: true }
proposed_fix: |
  1. SERVER (additive migration, minted at apply): `ALTER TABLE user_progress ADD COLUMN IF NOT EXISTS last_counted_week_key integer` (nullable, metadata only) and a NEW function `raise_streak_week_marker(p_user_id uuid, p_week_key integer) returns integer`, SECURITY DEFINER, `search_path=public`. A NULL or negative key RETURNs the stored value before anything else; otherwise the key is clamped to this IST week's Monday and written by a conditional UPDATE (`IS NULL OR < v_key`, so an unchanged marker issues no write). It does not touch `updated_at` or `streak_progress_version`. REVOKE from PUBLIC, anon, authenticated; GRANT to authenticated and service_role; a closing assertion pins one function, 2 arguments, no defaults, integer result, SECURITY DEFINER, search_path, the exact grantee set and no anon EXECUTE. The file is idempotent (CREATE OR REPLACE, IF NOT EXISTS); plain `SET lock_timeout` with a closing `RESET`.
  2. CLIENT push: `_pushStreakWeekMarker(userId, marker)` in sync_profile.dart, called from exactly two places (after the first snapshot attempt returned a version; after a successful conflict retry, via a new `streakWeekMarker` parameter on the retry helper). Best effort: its own try, `ErrorTelemetry.logEvent('streak_week_marker_push_failed')`, never fails the sync, never enqueues. Skips an absent/negative marker, the kill switch `disable_streak_week_marker_push`, an owner mismatch, and a marker equal to the memory `streak_week_marker_pushed` (`'<userId>:<marker>:<IST day>'`), which is written only after a successful call and a second owner check.
  3. CLIENT restore: `last_counted_week_key` joins `UserRepository.monotonicProgressFields` (local-max-wins); a cloud double is normalised with `toInt()` in the local-absent and local-malformed branches, and `train_provider.dart` reads the key as `(raw as num?)?.toInt()`.
regression_test_planned: |
  test/contracts/streak_week_marker_push_behavioral_test.dart (13 tests, real SyncService against the stub server with per-function rpc responders: pushed after a first-attempt version and after a conflict + retry, not after two conflicts, not for an absent/negative/non-numeric marker, once per unchanged marker, kill switch, owner mismatch, pre-await marker, PGRST202 / transport error / 500 swallowed and retried next sync, owner swap during the await writes no memory); test/contracts/progress_restore_monotonic_behavioral_test.dart (fifth field, exact list pinned, double normalised); test/contracts/streak_week_marker_migration_text_test.dart (12 PRESENCE pins incl. the early RETURN before LEAST, the Monday clamp, the REVOKE naming anon, the closing assertion, the literal reverse block, harness body equality); test/sql/raise_streak_week_marker_verify.sql (14 live cases in a rolled-back transaction, owed at the A1 dry-run before the apply); test/sql/security_definer_anon_revoke.sql (3 new rows).
mutation_proof: |
  Rule 21, scratch-copy protocol (backup, mutate, confirm the mutation applied, run, restore, sha256 identical). 26 mutants, all APPLIED, all RED on a real test failure (none a compile error), every file byte-identical afterwards. Client (15 + 3 added by the B-pass fixes): drop the pre-put owner re-check; memory value without the user id; first push re-reads the box after the await; drop the retry-path push; drop the memory skip; drop the kill switch; drop the pre-call owner guard; write the memory before the call; push a negative marker; rethrow from the helper; remove the first-attempt push; marker not in the monotonic list; no toInt when local is absent; no toInt over a non-numeric local; memory without the IST day; the tolerant marker read ignoring doubles; the call site bypassing the helper; the helper enqueueing on failure. Migration text (8, on the draft): early RETURN removed; clamp back to +7; REVOKE forgets anon; unconditional UPDATE; SET LOCAL; bumps the version; closing assertion drops the arity check; guard removed. The SQL harness cases are mutation-proven by the A1 dry-run (see 'Live apply record' below): four single-edit variants of the function body, each red on the intended cases.
impact_analysis: |
  Every signed-in user passes through `_syncUserProgress`; the added call runs only when the marker changed (about once a week) and can never fail the sync. The server function is own-account only and cannot lower a value. Old clients never call it and ignore the extra column. Rollback is a new minted migration (DROP FUNCTION; the column drop is destructive and flagged) plus the client kill switch. Accepted residuals: (1) a device ahead of IST on an IST Sunday evening holds K+7 which the clamp stores as K, so one reinstall can re-count that week; (2) RLS lets a user PATCH their own row, so stored values are not an integrity boundary (self-harm only); (3) the upgrade edge from Slice D (a week counted before D's update can count once more); (4) a client built before the apply gets PGRST202 and swallows it. The merge to main waits for the apply.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync_profile.dart (_pushStreakWeekMarker, retry-helper parameter, syncUserProgressForTest seam), user_repository.dart (monotonic list, toInt), train_provider.dart (tolerant read); flutter analyze clean; 12 + merge + 12 tests green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The push tests read configBox['streak_week_marker_pushed'] back; the merge tests read the merged progress map." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "New nullable column user_progress.last_counted_week_key integer and a new function; backups/live_schema_columns.json regenerated at apply." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "ADD COLUMN with no default: no existing row is rewritten; the marker fills in as clients push." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Owed at apply: mint number (A2), dry-run (A1), apply, backups/applied_migrations.json entry with the ledger hash." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "restore-user-snapshot selects * for user_progress, so the new column rides along; no Edge Function change." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not cron-dispatched; weekly-recalc upserts named fields only." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "user_progress_update_own lets a user PATCH their own column (documented residual); the function is SECURITY DEFINER with the auth.uid() raise; anon probe owed post-apply." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The client calls rpc raise_streak_week_marker with p_user_id and p_week_key; the stub-server tests pin the body; the live round trip is owed at the A1 dry-run and after the apply." }
recurrence: "Same class as 47de4f (a value that restore/push can move the wrong way) and b7d3e5 (the marker semantics). The monotonic-GREATEST pattern is the known-good fix; the new element is the shared-configBox memory trap, handled by keying the memory by user id."
related_bugs: [47de4f, b7d3e5, c9d2f6, d1f6b3, e9b4a2]
---

# a3c8f1 - the weekly-streak marker was local-only, so a reinstall could count a week twice

## What happened

Slice D redefined the marker as the calendar week last counted. It stayed in Hive only, so a restore brought back the counter but not the marker.

## Why this design

A calendar-week key never repeats and only moves forward, so the right server rule is plain GREATEST. That let the earlier 14-parameter / lexicographic design (v4) be dropped for a tiny separate function; the hot snapshot RPC is untouched.

## Plan review

Two rounds, six context-blind seats, all findings folded into plan section 8 (v7): round 1 (21 findings: the owner guard the plan named did not exist, the +7 clamp could block a legitimate week, a negative key was stored, the retry path never pushed, the stub could not model per-function rpc) and round 2 (0 P0, 3 P1, 8 P2, 12 P3: `LEAST(NULL, x)` ordering, the shared configBox memory, the retry-helper plumbing, transaction semantics of apply_migration). None changed the design.

## Live apply record (2026-10-08, project dedsavbjuwgarrhphgnl, founder's explicit 'ok' to mint, dry-run and apply)

1. **Mint (A2):** `mint_migration.sh --live ... --stub raise_streak_week_marker` reserved 157 (live top was 156; an unrelated unfiled reservation exists for 155). The draft was copied byte for byte over the stub and deleted.
2. **A1 dry-run, run 1:** one `execute_sql` holding an always-aborting `DO` that EXECUTEs the exact file bytes under a distinct dollar tag, then the 15 cases. Run as `postgres`. 14 ok; 1 fail that was a HARNESS bug (case 13b compared a `name[]` to a `text[]`; the migration's own closing assertion, which casts on assignment, passed). Harness fixed (`g::text`).
3. **A1 dry-run, run 2:** all 15 cases ok on the exact bytes (stored 20717 then 20724; lower/equal key = 0 row writes; NULL and -1 stored nothing; far-future clamped to 20731 = this IST Monday; cross-account raised; grantees exactly {authenticated, postgres, service_role}). Over four single-edit variants of the body, red exactly where intended: early RETURN removed (negative_key_stores_nothing, null_key_noop, null_key_null_stored, body_has_pinned_clamp), clamp +7 (future_clamped_to_this_monday), unconditional UPDATE (equal_no_write, lower_ignored_no_write), version bump (version_and_updated_at_untouched).
4. **Nothing persisted:** a read-only query after each dry-run found no column, no function, no seed users or progress rows, no trigger, `lock_timeout` 0.
5. **Apply:** `apply_migration` name `157_raise_streak_week_marker`, the exact file bytes, success; cloud_version 20261008164155.
6. **Post-apply reads:** `user_progress.last_counted_week_key` integer (0 of 32 rows set); 1 function, pronargs 2, pronargdefaults 0, SECURITY DEFINER, `search_path=public`, returns integer; EXECUTE grantees exactly {authenticated, postgres, service_role}; `has_function_privilege('anon')` false; no leftovers; `lock_timeout` 0.
7. **Anon probe:** anon-key POST to `/rest/v1/rpc/raise_streak_week_marker` answered HTTP 401 `42501 permission denied for function raise_streak_week_marker` on the first try (not PGRST202: no schema-cache lag).
8. **Records:** `backups/applied_migrations.json` entry 157 (hash from `migration_ledger_hash.dart`), `backups/live_schema_columns.json` regenerated with the new column, Gates 14 and 39 pass.

## Still owed

The runtime check on a device (the founder's phone: a second progress sync pushes the marker; `user_progress.last_counted_week_key` becomes the current Monday key, 20731 for the week of 2026-10-05). Commit on the founder's word; one push and one pull request for C1 + D + C2.

## B-pass (two Sonnet seats, 2026-10-08)

Database seat: no P0/P1. P2 FIXED: harness Case 10 compared a comment-stripped copy while `pg_get_functiondef` returns the body verbatim with comments (one comment mentions `LEAST(`), so the "RETURN precedes LEAST" check would have been a false red against the deployed text; Case 10 now strips `--` comments from the live definition first). P3: `lock_timeout` can leak only on a non-transactional apply that fails before the closing RESET (safe direction; the failure procedure starts with `RESET lock_timeout;`); the owner role is assumed to be `postgres` (new harness case 13b asserts the exact aclexplode set and prints `current_user`, and the A1 dry-run exercises exactly this creation path); `security_definer_anon_revoke.sql` only runs after the apply; the schema snapshot is regenerated at the apply commit.

Client seat: no P0/P1. P2 (deploy order: a client carrying this code calls a missing function until the apply, one swallowed PGRST202 plus one low-priority event per progress sync) is handled by the plan's rule that the merge waits for the apply. P2 FIXED: the tolerant marker read had no test; it is now the pure `lastCountedWeekKeyFrom` helper with a unit test and a call-site pin (mutants N1, N2 RED). P3 FIXED: the transport-error test now asserts no `sync_user_progress` marker was enqueued (mutant N3 RED); the doc comment on `SyncServiceProfile` is back above the extension; the pushed-marker memory could outlive an out-of-band cloud reset, so it now carries the IST day and re-pushes at most once a day (test + mutant M15). Accepted: no timeout on the marker rpc (the same exposure as the snapshot rpc beside it).

## Hermes pass (three Sonnet seats, 2026-10-08)

Report: docs/audit/2026-10-08-hermes-streak-freeze-c2.md (0 P0, 1 P1, 5 P2, 8 P3, every finding terminal). The P1 (an older client copies the new column into its Hive map) is `verified_clean`: no client on origin/main reads the key `last_counted_week_key` (shipped clients use `last_streak_week`), so a copy is never read, and Slice D, the only reader, ships in the same pull request as C2 after the apply. Ledger entries `OLD-APK-MARKER-COPY`, `C2-STALE-PUSHED-MEMORY`, `C2-DIRECT-WRITE-NOT-AN-INTEGRITY-BOUNDARY`.
