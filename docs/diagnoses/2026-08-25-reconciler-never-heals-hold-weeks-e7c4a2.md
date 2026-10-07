---
bug_id: e7c4a2
date: 2026-08-25
batch: oi60-client-blockers
status: fixed
blast_radius: platform
symptom: >
  A hold week whose exercises were dropped by the restore-skip bug is never healed. The
  PlanIntegrityReconciler builds its symptom set from getWeek(1..4) only, which is date-driven off
  plan_start, so hold weeks — which start at plan_start+28 — are invisible to it. needsHeal()
  returns false, the reconciler skips as 'healthy', no cloud fetch happens, and the user sees
  "REST DAY / No exercises scheduled" on the one week a free user is actually training. This is the
  exact failure the reconciler exists to cure, occurring on the week it matters most.
concept: >
  A trigger and a write sharing one predicate when they need two. The reconciler's WRITE half was
  never scoped to weeks 1-4 — it merges the whole cloud bundle['schedules'] — but its TRIGGER was,
  and the same predicate also authorises the plan_start / plan_end re-anchor. So the obvious repair
  (widen the 1..4 scan) buys no healing and only makes the window move more often; it was already
  REFUTED as P0-11 concern d7f3a9. The correct shape is two independent predicates over one fetch.
sot_registry_entry: >
  None added. The reconciler already appears in the restore_completeness and plan-integrity
  concepts as a reader of cloud plan_json and a writer of schedule_ rows; this change alters WHICH
  symptom wakes it, not what it reads or writes, so no new writer/reader pair exists to register.
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, method: "holdWeek() — materializes the hold week's schedule rows that can lose their exercises", line: 236 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "reconcile() — merges bundle['schedules'] (the heal), and separately writes plan_start_date / plan_end_date (the re-anchor)", line: 240 }
readers:
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "computeTriggers() — the single point deciding which of the two the current symptom authorises", line: 176 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method: "gatherHoldRows() — the hold-week symptom source, extracted to be testable", line: 147 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "activeHoldWeeks() — the flag-gated seam; returns const [] when enable_hold_weeks is OFF", line: 891 }
hive_key_prefix: "schedule_ — the per-date rows both the symptom scan and the merge operate on; plus plan_start_date / plan_end_date for the re-anchor."
hive_key_formula: "schedule_${formatDateKey(date)} via getScheduleForDate; hold dates walked as normalizeToMonday(HoldWeekInfo.weekStart) + 0..6."
sync_methods: >
  The reconciler is invoked from the boot heal path alongside restore; it pulls user_progress.plan_json
  directly rather than through a sync_* extension, so no sync method signature changed.
restore_methods: >
  _restoreWorkoutPlan (sync/sync_workout.dart) shares mergeScheduleEntry with this reconciler; that
  shared merge is unchanged by this fix. Only the trigger that wakes the reconciler changed.
cloud_table: user_progress
cloud_columns: plan_json
contract_test_path: test/contracts/reconciler_hold_heal_split_behavioral_test.dart
ist_handling: >
  not_applicable to the fix — no new date key is formed. Hold dates are walked from the existing
  normalizeToMonday helper and resolved through formatDateKey, both unchanged.
provider_invalidations: none — the reconciler runs at boot before the provider graph reads schedule rows.
telemetry_op_types: >
  None added. PlanReconcileOutcome already carries a reason string ('healthy' / 'no_plan_start' /
  'no_cloud_row' …) that the existing caller records; the new hold trigger flows through the same
  outcome, so an added op_type would duplicate a signal that already exists.
cross_account_guard: >
  not_applicable — the reconciler reads the current session's user id and the user-scoped boxes
  exactly as before; no new box or query scope is introduced.
forbidden_patterns_checked: >
  Checked and clean. The repo-specific pattern that applied is the one round 2 caught this batch
  committing: HoldWeekInfo.weekStart used as a week anchor. See below — it was already rejected BY
  NAME in oi60-streak-identity.closure.yaml:51 and scar-commented at train_provider.dart:577-579.
proposed_fix: >
  Split the trigger from the write. computeTriggers() returns a RECORD — (shouldFetch,
  mayReanchor) — not a bool: the entire fix IS that distinction, and a single bool would force the
  caller to re-derive the second decision, which is the guard-without-its-mirror class. EITHER
  symptom authorises the fetch + schedule merge; ONLY the original weeks-1-4 symptom authorises the
  plan_start / plan_end re-anchor. The two key sets are disjoint (schedule_ vs plan_*_date), so the
  merge cannot move the plan window by any path. Hold rows are gathered through the flag-gated
  activeHoldWeeks() seam, so with enable_hold_weeks OFF holdRows is empty and both predicates
  collapse to the pre-fix single gate — byte-identical.
regression_test_planned: >
  11 cases across two files, mutation-proven. reconciler_hold_heal_split_behavioral_test.dart (8):
  re-implementing the REFUTED widened design (one predicate for both) reddens exactly the test
  built to catch it — 'a hold-only symptom must NOT authorise the re-anchor'.
  reconciler_gather_hold_rows_behavioral_test.dart (3): restoring the rejected h.weekStart anchor
  reddens the missing-Monday case. ⚠ The FIRST version of that test was VACUOUS — it passed under
  the very mutation it existed to catch, because with one hold the spill target has no row and both
  walks read identically. Rebuilt with two holds so hold 2 supplies a real row at the spill target.
  Only the mutation run revealed this; neither review round did.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "plan_integrity_reconciler.dart: new computeTriggers + gatherHoldRows, re-anchor gated on mayReanchor; flutter analyze clean; 11/11 behavioral tests green." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "gatherHoldRows exercised against real Hive rows materialized by the real holdWeek() writer, including the missing-Monday state produced by deleting a hold row." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; user_progress.plan_json is read as-is." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Read-only consumer of an existing column; no data written server-side." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration; backups/applied_migrations.json untouched." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved; the reconciler queries PostgREST directly." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "Boot-path only, no cron." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "The select is .eq('user_id', currentUser.id) under the existing own-rows policy — unchanged by this fix, and the fix adds no new query." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The plan_json read is unchanged in shape and columns; only the local predicate deciding whether to issue it changed." }
impact_analysis: >
  Severity: P2. Affects free users who took a hold AND lost hold-week exercises to the restore-skip
  path (a7d3f1's class). For them the reconciler — the thing built to self-heal exactly this — was
  structurally unable to fire. Cost of the fix: one additional Supabase select per boot for a user
  who genuinely has a broken hold week, and zero for everyone else (the predicate is empty when the
  flag is off, and false when the hold weeks are healthy). Flip-on blocker for OI-60 (FOB-7b).
---

# The reconciler never heals a hold week (FOB-7(b) / OI-60)

## Why widening the scan is the wrong fix

`oi60-streak-identity.closure.yaml`, P0-11 concern `d7f3a9`: the `1..4` scan **is** the re-anchor
trigger. Widening it buys no healing — the merge was never scoped to weeks 1-4 — and only makes
`plan_start` / `plan_end` move more often. Recorded here and in the code comment so it is not
re-proposed a third time.

## The bug this batch introduced, and why its first test was vacuous

Round 2 caught the hold-row gathering loop anchoring on `HoldWeekInfo.weekStart`. That value is
`byOrdinal[ordinal]!.first` (`workout_schedule_read_service.dart:870`) — the first **surviving**
hold date — so a hold week missing its Monday row yields a **Tuesday**, and a 0..6 walk reads
`[Tue..Sun, next Monday]`.

Three pieces of prior art all predate this batch and all say so:

- `train_provider.dart:577-579` — *"Never `HoldWeekInfo.weekStart` either — that is the first
  SURVIVING hold date, so a missing Monday row makes it a Tuesday, which is wrong for a row key."*
- `oi60-streak-identity.closure.yaml:51` — lists it among the **rejected** designs for FOB-2.
- `hold_week_streak_identity_behavioral_test.dart` — carries the reproduction.

**A grep for `HoldWeekInfo` or `weekStart` across `docs/` and `test/` would have surfaced all
three.** That is a §4.1.5 bug-history miss, the second in this batch.

It survived two review rounds' test suites because the loop was **inline in `reconcile()`**, which
needs a live Supabase client — no test could reach it. Extracting it as `gatherHoldRows()` is the
durable fix; the Monday anchoring is merely the bug.

⚠ **And the first regression test for it proved nothing.** It passed with the rejected pattern
restored, because with a single hold the spill target (`hold1Monday + 7`) has no row, so
`getScheduleForDate` returns null for the correct walk and the rejected one alike — byte-identical
results. The test's input set could not contain the symptom. Rebuilt with two holds so hold 2
supplies a real row at the spill target; the rejected pattern then gathers that Monday twice and
the test reddens. Caught by the mutation run, not by either reviewer.
