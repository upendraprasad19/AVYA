---
bug_id: 47de4f
date: 2026-10-07
batch: streak-freeze-restore-ownership (addendum A, Slice C1: last_workout_date latest-wins on restore, GREATEST for current_streak_weeks and last_workout_date on the server)
status: fixed
blast_radius: catastrophic
symptom: |
  A stale value could overwrite a newer one in two places. (1) CLIENT: the whole-row restore (`UserRepository.mergeCloudProgress`) copied the cloud `last_workout_date` over the local one (cloud-non-null-wins), so a phone holding a newer, not yet pushed date was regressed by an older cloud row, and the regressed value was then pushed back. (2) SERVER: `update_user_progress_snapshot` (migration 115) set `current_streak_weeks` and `last_workout_date` with a bare COALESCE, so any non-null resend won, while its three siblings (`total_workouts_done`, `deployments_complete`, `longest_gap_days`) already used GREATEST. A device with a clock set ahead could also store a future date that nothing could lower. The only reader of the date is the rank-promotion gap gate, so the visible risk is a wrong gap read and a re-counted streak week after a reinstall.
concept: progress_last_workout_date
sot_registry_entry: progress_last_workout_date
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout (the runtime writer of progress['last_workout_date'], every completion)", line: 1989 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "mergeCloudProgress (post-fix: the date branch calls laterIsoDate; pre-fix: cloud-non-null-wins)", line: 613 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "laterIsoDate (the ONE date rule)", line: 125 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress (passes istToday; the push builder _buildUserProgressRpcParams sends p_last_workout_date)", line: 926 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "hydrateFromCloud (the sign-in hydrate; passes istToday)", line: 759 }
  - { file: supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql, method_or_widget: "update_user_progress_snapshot (pre-fix bare COALESCE; the C1 migration replaces the body, same 13-argument signature)", line: 1 }
readers:
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method_or_widget: "the rank-promotion gap gate (reads progressRow.last_workout_date)", line: 236 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress (reads the cloud row it merges)", line: 926 }
hive_key_prefix: progress
hive_key_formula: "userBox['progress']['last_workout_date' | 'current_streak_weeks']"
sync_methods:
  - syncProgressNow
  - pushOnboardingProgressSnapshot
restore_methods:
  - _restoreUserProgress
  - hydrateFromCloud
cloud_table: user_progress
cloud_columns:
  - last_workout_date
  - current_streak_weeks
contract_test_path: test/contracts/last_workout_date_latest_wins_behavioral_test.dart
ist_handling:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "laterIsoDate ceiling = istToday + 1 (callers pass istDateStr(nowWall())); the migration clamps to (now() AT TIME ZONE 'Asia/Kolkata')::date + 1", line: 125 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - progress_restore_demotion_declined
cross_account_guard: "unchanged: _restoreUserProgress keeps its owner guard before the put; the RPC keeps its auth.uid() cross-account raise (proved again by Case 31 of the SQL harness)."
forbidden_patterns_checked:
  - { pattern: "a second comparison of last_workout_date strings next to laterIsoDate", absent: true }
  - { pattern: "an unguarded LEAST(p_last_workout_date, ...) in the migration (LEAST(NULL, x) is x, so a NULL date would be stored as IST-tomorrow)", absent: true }
  - { pattern: "an overload or DROP of update_user_progress_snapshot (resets the ACL, bug class 2.36)", absent: true }
proposed_fix: |
  1. CLIENT: `laterIsoDate(local, cloud, istToday:)` is the pure rule. Well-formed means `^\d{4}-\d{2}-\d{2}$`, a real calendar date (round trip), not later than istToday + 1. The later date wins. Local absent + cloud date takes the cloud (a reinstall is not malformed). Local malformed + cloud good: the cloud repairs it, reported. Cloud malformed: keep local, reported. An unparsable istToday disables the ceiling only. `mergeCloudProgress` takes a required `istToday` and runs the rule on `last_workout_date`; both whole-row callers pass `istDateStr(nowWall())`. Declined dates ride `ProgressMergeResult.declinedDateFields` (`DateDecline`) and the existing `progress_restore_demotion_declined` event. Kill switch `disable_progress_date_merge`; `disable_progress_restore_monotonic_merge` is the wider rollback.
  2. SERVER (migration, body-only): `CREATE OR REPLACE` of `update_user_progress_snapshot` with the SAME 13-argument signature (grants and the function comment are preserved). `current_streak_weeks = GREATEST(COALESCE(p, col), col)`; `last_workout_date = GREATEST(v_date, last_workout_date)` where `v_date` is declared with an explicit NULL branch and the IST-today + 1 clamp, and the fresh INSERT stores `v_date`. A closing DO block asserts one function, the EXACT grantee set {authenticated, postgres, service_role}, `search_path=public`, SECURITY DEFINER and 13 arguments. The reverse block is the literal migration-115 body.
regression_test_planned: |
  test/contracts/last_workout_date_latest_wins_behavioral_test.dart (25 tests: the pure table, merge rows, key-order independence, both switches, the emitter); the two existing merge test files carry the new `istToday` argument and two caller tests drive the real restore with a pinned clock; test/contracts/progress_last_workout_date_writer_to_reader_test.dart pins the migration text and the call sites; test/sql/cross_device_progress_optimistic_lock_verify.sql Cases 22-31 prove the server rules on live Postgres inside a rolled-back transaction (owed at the A1 dry-run, before the apply).
mutation_proof: |
  Rule 21, scratch-copy protocol with backups cmp-verified after the run. Client: 20 mutants (D01-D20: never write, never report, >= for equal dates, no decline, local-null not taking cloud, ceiling removed, ceiling off by one, no calendar round trip, each switch dropped, a hard-coded istToday in the merge and in both callers, hasDeclined and the emitter and the result field dropped, malformed flags dropped, a loose shape test) against the three test files (baseline 118 passed): all 20 RED, none a compile error, all files byte-identical to the pre-run backups. Migration text: 5 mutants on the draft (COALESCE instead of GREATEST, a non-NULL branch, a UTC clamp, the raw parameter on the INSERT, a wrong arity in the closing assertion) each reddened the text test. The SQL harness cases are mutation-proven at the A1 dry-run (old body restored in BEGIN...ROLLBACK, new cases re-run), recorded below when done.
impact_analysis: |
  Every signed-in user hits the restore merge and the push RPC. The change only ever refuses to LOWER a value, plus clamps an impossible future date, so a correct device sees no difference; the visible effect is that a stale cloud row or stale resend can no longer take a streak week or a date backwards. Client rollback is one Hive switch; server rollback is a new minted migration with the literal 115 body (the applied file is immutable). Shipped clients keep working untouched (signature unchanged). Not applied yet at the time of writing: the live apply is a separate go.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "user_repository.dart (laterIsoDate, DateDecline, IsoDateMerge, mergeCloudProgress), sync_profile.dart and auth_session_bootstrapper.dart pass istToday; flutter analyze clean; 118 + 25 tests green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The caller tests drive the real restore over a real Hive userBox and read userBox['progress'] back." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "No schema change: user_progress.last_workout_date is a date, current_streak_weeks an integer; the function signature is unchanged." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data is rewritten; existing rows are untouched." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Owed at apply: mint number, backups/applied_migrations.json entry with the ledger hash, live_schema_columns.json regenerated." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed; evaluate-rank-promotions only reads the date." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not cron-dispatched." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "SECURITY DEFINER with the auth.uid() cross-account raise kept; the closing assertion pins the grantee set; anon probe owed post-apply (A7)." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Both RPC writers pass p_last_workout_date and p_current_streak_weeks (pinned by the writer-to-reader test); the owed runtime check is a real restore plus a push against the applied function." }
recurrence: "Same class as e9b4a2 and a2d8f4 (a stale value overwriting a newer one through a non-monotonic write) and 41507e (the restore merge); the fix applies the known-good pattern (GREATEST on the server, local-wins-when-newer on the client). Not a new class."
related_bugs: [e9b4a2, a2d8f4, 41507e, c9d2f6, d1f6b3]
---

# 47de4f - a stale value could take the last workout date or the streak-week counter backwards

## What happened

Two writers treated `last_workout_date` and `current_streak_weeks` as "last write wins". The restore copied the cloud date over the local one, and the push RPC accepted any non-null resend. Siblings in the same UPDATE already used GREATEST.

## The fix

The client rule is one pure function (`laterIsoDate`) and the server rule is GREATEST over a clamped value. The explicit NULL branch matters: `LEAST(NULL, x)` is `x`, so an unguarded clamp would turn the onboarding replay's NULL date into IST-tomorrow and GREATEST would then pin it there. The closing assertion block proves a `CREATE OR REPLACE` moved nothing it should not (one function, exact grantees, search_path, arity).

## Still owed (gated)

B-pass and Hermes pass, the migration number (A2), the dry-run (A1) with the mutation of the SQL cases, the founder-authorised apply, the ledger entry, the anon probe (A7) and the plan-review record update. Nothing live has been touched.

## B-pass (two Sonnet seats, 2026-10-07)

Seat A (client): no P0/P1/P2 defect, no input where a newer local date is lost or a bad one written. Two P3 test gaps FIXED in this batch: a malformed cloud date is now asserted to emit `progress_restore_field_malformed` (names only; mutation: emptying the malformed loop in `reportProgressDemotionsDeclined` reddens it), and a caller-supplied `istToday` is asserted to reach the ceiling through `mergeCloudProgress` (same rows, two different `istToday`). Noted, by design: the client ceiling cannot stop a device whose OWN clock runs ahead (the same `nowWall()` feeds both); the server clamp is the defence for that.
Seat B (migration): no P0/P1. The harness copy matches the draft body; GREATEST/LEAST NULL semantics, the IST clamp, ACL preservation and the later-migration check (only 115 defines the function; 149 mentions it in a comment) hold; Cases 22, 25, 28 and 30 go red against the old body, the rest are positive controls. P2 (a future date ALREADY stored cannot be lowered by GREATEST): live read-only check 2026-10-07 on `user_progress`: 32 rows, 0 with `last_workout_date` later than IST-today + 1, max 2026-10-07, so no repair is owed. P3 (weeks can no longer be lowered through the RPC): intended, it matches the restore's max-merge; the only resets are onboarding and the debug simulation, both on a fresh or dev row. P3 (the harness does not exercise the closing assertion): the assertion runs live inside the migration's own transaction at apply.
