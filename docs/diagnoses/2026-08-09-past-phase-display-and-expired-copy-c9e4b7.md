---
bug_id: c9e4b7
date: 2026-08-09
batch: train-signout-notif-bugs
status: fixed
blast_radius: feature
symptom: |
  Founder, live web 2026-08-05, account upendraprasad19@gmail.com: the Train
  screen's week selector showed NO past-phase history despite the account being
  on Phase 2 with a completed Phase 1 on record. Scrolling left revealed
  nothing — the strip began at the current phase.

  Second, separate symptom on the same screen: the plan-expired card was
  hardcoded to Phase-1 language ("Phase 1 — secured, Recruit.", "Phase 2: new
  drills…") regardless of which phase the user had actually finished, so a user
  completing Phase 3 was congratulated on Phase 1 and offered Phase 2.

  ROOT CAUSE (display): `pastPhaseBlocks()` filters schedule_* rows to those
  STRICTLY BEFORE `plan_start`. That filter is correct for the reconciler, which
  must never over-count. But when a phase advance re-anchors `plan_start` to the
  NEW phase's start, every row of the just-completed phase is still before it —
  UNLESS the advance path leaves plan_start un-advanced, in which case the whole
  history sits at-or-after the cutoff and the strict filter returns empty. The
  founder's account was in exactly that state, so the reader was correct about
  its own contract and the RENDER was still wrong.

  This is writer/reader drift with a twist: one reader (the reconciler) needs the
  strict set and the other (the selector) needs a recoverable one. Feeding both
  from one method meant the safe choice for one was the wrong choice for the
  other.
concept: past_phase_display_recovery
sot_registry_entry: past_phase_display_recovery
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_scheduleRowsBefore — the SHARED schedule_* row walk; both paths parse a row identically and differ ONLY in the cutoff passed", line: 1216 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "pastPhaseBlocks — the STRICT set, cutoff = plan_start. Unchanged semantics; now delegates to the shared walk", line: 1209 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "pastPhaseBlocksForDisplay — DISPLAY-ONLY recovery wrapper; falls back to the un-cutoff set minus the current phase when strict is empty and currentPhase > 1", line: 1261 }
readers:
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "past-phase strip — the ONLY caller of the display wrapper", line: 137 }
  - { file: lib/core/services/phase_progress_reconciler.dart, method_or_widget: "reconciler — reads the STRICT pastPhaseBlocks() and must never read the wrapper (monotonic over-advance is unrecoverable)", line: 131 }
  - { file: lib/features/train/widgets/plan_expired_card.dart, method_or_widget: "currentPhase read from UserRepository — drives the interpolated copy", line: 123 }
  - { file: lib/features/train/widgets/plan_expired_card.dart, method_or_widget: "nextPhase = currentPhase + 1 — drives the CTA and the 'new drills' line", line: 125 }
hive_key_prefix: schedule_
hive_key_formula: "schedule_<yyyy-MM-dd> in workoutBox; each value carries a `date` string parsed back out by _scheduleRowsBefore"
sync_methods: []
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: [date, status, user_id]
contract_test_path: test/contracts/past_phase_display_recovery_behavioral_test.dart
ist_handling:
  - "Date keys are the existing IST-stamped `schedule_<yyyy-MM-dd>` keys; this fix changes only WHICH rows are selected, never how a date is formed or compared. No new date key, no counter reset, no cloud `date` write."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Inherited, not re-implemented. Both paths read `_hive.workoutBox`, which is a
  user-scoped box reached through `wrapUserScopedBox`; a cross-account read
  throws there rather than here. The display wrapper adds no new box access — it
  calls the same `_scheduleRowsBefore` walk with a different cutoff.
forbidden_patterns_checked:
  - "No `Container(color:+decoration:)` introduced (gate check_container_color_decoration.dart)."
  - "No raw `Hive.box(` — reads go through the existing service's `_hive` handle."
  - "No new `.from().select()` column reference, so check_schema_column_refs.dart is unaffected."
  - "Reconciler does NOT reference pastPhaseBlocksForDisplay — pinned by an explicit isFalse assertion in week_selector_past_phases_test.dart."
proposed_fix: |
  Split the two readers' needs instead of loosening the shared filter.

  1. Extract the row walk into `_scheduleRowsBefore(DateTime? cutoff)` so the
     strict path and the recovery path parse a row IDENTICALLY and differ only
     in the cutoff. This removes the possibility of the two diverging in how
     they read `date`, which is the drift class that caused the bug.
  2. `pastPhaseBlocks()` keeps its exact prior semantics (cutoff = plan_start)
     and remains the reconciler's only input.
  3. Add `pastPhaseBlocksForDisplay(currentPhase)`: returns the strict set when
     non-empty; otherwise, only when `currentPhase > 1`, buckets the un-cutoff
     set and drops the LAST block (the phase in progress). Returns empty when
     fewer than 2 blocks exist, so a single in-progress phase never renders as
     history.
  4. Expired-card copy interpolates `currentPhase` / `nextPhase` from
     UserRepository instead of hardcoding 1 and 2.

  Deliberately NOT done: relaxing `pastPhaseBlocks()` itself. The reconciler
  advances `current_phase` MONOTONICALLY and its own comment calls an
  over-advance "unrecoverable" — a wider set there could promote a user on
  evidence the strict filter deliberately rejected, with no way back. Display
  is recoverable; a monotonic promotion is not. The asymmetry is the reason for
  two methods rather than one.

  Also deliberately left: the flag-OFF fallback string 'Run Week 4 again' in the
  expired card. It is reached only when `enable_hold_weeks` is OFF, where it is
  accurate.
regression_test_planned: |
  test/contracts/past_phase_display_recovery_behavioral_test.dart — 6 tests over
  a REAL Hive round-trip (open box → write schedule_* rows → read back through
  the service), seeded with the founder's exact live numbers.

  Mutation-proven: group B fails when the recovery branch is removed from
  pastPhaseBlocksForDisplay.

  test/contracts/week_selector_past_phases_test.dart additionally pins that
  phase_progress_reconciler.dart does NOT reference pastPhaseBlocksForDisplay —
  a source-grep isFalse assertion guarding the load-bearing separation above.
  10/10 green.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on the changed set; 58/58 across the six contract files." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "past_phase_display_recovery_behavioral_test.dart drives a real Hive box open/write/read, not a mock." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; scheduled_workouts is unchanged." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Read-path-only fix; no cloud write, no backfill." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched by c9e4b7." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes these Hive rows." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table access changed." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service in this path." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The full chain is client-local: workoutBox schedule_* → _scheduleRowsBefore → bucketPastRows → week_selector strip. Both readers named by file:line above and both are covered by tests." }
impact_analysis: |
  USER-VISIBLE: an account whose plan_start did not advance now sees its
  completed phases in the week selector again, and the expired card names the
  phase the user actually finished.

  BLAST RADIUS feature — Train screen rendering only. No write path, no sync, no
  cloud contract.

  RISK OF THE FIX: the recovery path can only ADD blocks to a render that was
  empty; it cannot remove or reorder an existing one (it returns `strict`
  untouched whenever strict is non-empty). Its two guards — `currentPhase <= 1`
  and `all.length < 2` — mean a genuinely-new user can never see fabricated
  history.

  THE ONE REAL HAZARD is the reconciler accidentally consuming the wider set
  later; that would be a monotonic, unrecoverable over-promotion. It is pinned
  by an explicit source-grep assertion, and the wrapper's own doc comment says
  so in the imperative. If that test ever fails, the correct fix is to give the
  reconciler its own strict call — NOT to relax the assertion.

  NOT FIXED HERE, and deliberately: whatever leaves `plan_start` un-advanced on
  some accounts. This fix makes the display resilient to that state; it does not
  diagnose it. The strict filter is still the reconciler's contract and is still
  correct.

  §4.1 requires naming the WRITER, so the candidate set is enumerated rather
  than left implicit (B-pass finding 2). Every non-test writer of
  `current_phase`: `phase_progress_reconciler.dart:138`,
  `sync_service.dart:1102` (restore), `pro_phase_advance.dart:343`,
  `onboarding_provider.dart:481,794` and `user_repository.dart:437` (both
  seed 1). Only two can raise it above 1 without also re-anchoring plan_start.

  **The reconciler is REFUTED as the writer, by its own gate.** It advances only
  when `reconciledPhase(currentPhase, completedBlocks)` returns non-null, and
  `completedBlocks` comes from the STRICT `pastPhaseBlocks()`. For the strict
  set to be EMPTY (the founder's symptom) `plan_start` must sit at or before the
  earliest schedule row, which makes `completedBlocks == 0`, which makes the
  target null and the write a no-op. So the reconciler cannot produce
  "current_phase > 1 AND strict set empty" — it is structurally incapable of it.
  Worth stating explicitly because the reconciler's own header says it advances
  the counter "WITHOUT touching the in-progress plan", which reads like the
  culprit until you check the gate.

  **The leading candidate is the RESTORE path**, `sync_service.dart:1102`, which
  writes `'current_phase': pr['current_phase'] ?? 1` from the cloud row while
  `plan_start_date` is restored on a different path from `plan_json`. That fits
  the report exactly: the founder was on a fresh WEB session, i.e. a
  restore-from-cloud, where cloud `current_phase` is 2 and the restored plan
  carries the original start date. NOT confirmed against that account's live
  rows, so it is recorded as the leading candidate rather than the cause — the
  honest state. Confirming it needs the account's `phase_progress_reconciled`
  telemetry plus its cloud `user_progress`/`plan_json` pair, which is a separate
  investigation with its own writers to name.
related_bugs: [a3f8c1, b9d2a8, c8f3d1]
recurrence: |
  Writer/reader drift, the recurring class (≥15 instances since APK Test #6).
  The NEW wrinkle worth recording: this is the first instance where two readers
  of the SAME method legitimately needed DIFFERENT strictness. The prior
  instances were all "reader reads the wrong field name" or "writer stopped
  writing what the reader reads". Here both sides were internally correct and
  the defect was that one method served two contracts. The fix pattern —
  extract the shared parse, keep the strict method untouched, add a
  named-for-its-audience wrapper, and pin the separation with a test — is the
  reusable part.
---

# Past-phase history invisible + expired-card copy hardcoded to Phase 1

See the YAML above for the full writer/reader map, the 12-tier check, and the
reasoning behind splitting `pastPhaseBlocks()` rather than relaxing it.

## Why two methods and not one flag

A `bool strict = true` parameter would have worked mechanically and been worse:
the reconciler's call site would then be one boolean away from an unrecoverable
monotonic over-advance, and that boolean would be invisible at the call site's
line. Two names make the dangerous path impossible to select by accident, and
make the source-grep assertion in the contract test expressible at all.

## The founder's numbers

The behavioral test seeds the exact live state from 2026-08-05 rather than a
synthetic fixture, so the regression it pins is the one that actually shipped.
