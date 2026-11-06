---
bug_id: d7f3a9
date: 2026-07-21
batch: hold-mechanic
blast_radius: platform
status: fixed
symptom: >
  The free-tier "Hold the Line" mechanic (`redoWeek4`) was broken three ways and
  its extension was not durable. `redoWeek4` (workout_schedule_write_service.dart:172)
  (a) started the new week on a NON-Monday `rollStart` (:181, `today` or `plan_end+1`),
  breaking the "every boundary is a whole number of weeks from a Monday plan_start"
  invariant; (b) sourced the TRAILING week (`plan_end-6` = the deload week) instead of
  the phase's canonical Peak week, every time; (c) used raw `DateTime.now()`, ignoring
  the clock seam. Separately, a hold extends `plan_end` LOCALLY, but the two restore
  writers (`_restoreWorkoutPlan` sync_workout.dart:1114-1119 + `PlanIntegrityReconciler`
  :148-149) re-anchored `plan_end` UNCONDITIONALLY from a possibly-stale cloud snapshot
  → the extension collapsed → hold rows fell outside `[plan_start, plan_end]` → invisible
  → phantom expiry (P0-1). And `_restoreScheduledWorkouts` capped the status merge at
  `.range(0, 999)` (:1807), ascending → a >1000-row (~2.7-yr) holder's CURRENT phase was
  dropped. Surfaced while designing the free-tier week model; validated by a ×2
  context-blind review (docs/plan-reviews/hold-mechanic.md).
concept: scheduled_workouts_mutations
sot_registry_entry: scheduled_workouts_mutations
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 232, source: "holdWeek() — NEW ship-dark replacement for redoWeek4: Monday-aligned rollStart via normalizeToMonday(nowWall()); sources plan_start+14 (Peak) or plan_start+21 (deload every 4th hold); FLAT verbatim copy; stamps 'week'=4+N / is_hold / hold_ordinal=N; extends plan_end; awaits pushWorkoutPlanForSyncDomain() for reinstall durability" }
  - { file: lib/core/services/plan_window_reanchor.dart, line: 39, source: "PlanWindowReanchor.resolve — pure monotonic phase-gated re-anchor shared by both restore writers (#1)" }
  - { file: lib/core/services/sync/sync_workout.dart, line: 1120, source: "_restoreWorkoutPlan — now re-anchors plan_end via PlanWindowReanchor (was unconditional cloud-verbatim)" }
  - { file: lib/core/services/plan_integrity_reconciler.dart, line: 150, source: "reconcile — same PlanWindowReanchor re-anchor in the boot heal" }
readers:
  - { file: lib/features/train/widgets/plan_expired_card.dart, line: 60, source: "_handleRedoWeek4 → PlanEngineFlags.holdWeeksEnabled ? holdWeek() : redoWeek4()" }
  - { file: lib/features/train/screens/graduation_screen.dart, line: 136, source: "KEEP TRAINING PHASE 1 → flag ? holdWeek() : redoWeek4(); now surfaces failure instead of blind-navigating to /train (H5 dead-end guard)" }
  - { file: lib/core/services/sync/sync_workout.dart, line: 1810, source: "_restoreScheduledWorkouts — reads the paginated (paginateAll) scheduled_workouts rows (#4)" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + formatDateKey(date)"
sync_methods: [syncWorkoutData, _syncWorkoutPlan (via pushWorkoutPlanForSyncDomain), _syncScheduledWorkouts]
restore_methods: [_restoreWorkoutPlan, _restoreScheduledWorkouts]
cloud_table: scheduled_workouts + user_progress.plan_json
cloud_columns: [user_id, scheduled_date, week_number, day_of_week, status, completed_at, template_id]
contract_test_path: test/contracts/hold_week_mechanic_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 245, fn: "rollStart = normalizeToMonday(nowWall()) — seam-aware today, RAW-weekday Monday (matches how plan_start was set), NOT mondayOfIst; keeps (rollStart-plan_start) % 7 == 0" }
  - { file: lib/core/utils/ist_date.dart, line: 65, fn: nowWall }
provider_invalidations: [currentPlanProvider, todayWorkoutProvider, calendarWeekProvider]
telemetry_op_types:
  success: [sync_workout_plan, restore_workout_plan, sync_scheduled_workouts]
  failure: [sync_service_if_16, sync_service_if_17]
cross_account_guard: >
  Unchanged — holdWeek writes through WorkoutWriteService.upsertScheduled (wraps
  wrapUserScopedBox) and MigratedKey (user-scoped userBox); the durability push routes
  through _ensureSessionOpen → HiveUserSession. No new cross-account surface.
forbidden_patterns_checked: >
  redoWeek4 is KEPT verbatim and reachable when enable_hold_weeks is OFF (ship-dark
  §4.6), so every rename-breakage the prior review listed (banner test, split-invariant
  test:46, sot_registry forbidden regex) is sidestepped. Verified holdWeek stamps
  is_hold/hold_ordinal ONLY on the Hive map + plan_json — the scheduled_workouts push
  hand-picks its column set (sync_workout.dart:1604-1612), so those keys never reach the
  (column-less) cloud table → no 400. Verified `week_number` is nullable int with NO
  CHECK and ZERO EF/cron readers (live schema + grep supabase/functions), so week=5+ is
  safe. Verified holdWeek NEVER writes plan_start (pinned by the behavioral test) so
  future-dated hold rows stay excluded from pastPhaseBlocks → current_phase can't
  over-advance (#6, safe by the read_service.dart:1038 date filter, not a stamp).
proposed_fix: >
  Replace redoWeek4 with holdWeek behind `enable_hold_weeks` (default OFF). Sources the
  canonical Peak/deload week BY DATE (never plan_end-derived), Monday-aligns, keeps loads
  FLAT (free maintains / PRO progresses), stamps a gap-proof row-local hold_ordinal
  (max over rows dated < rollStart, +1 — crash-idempotent), extends plan_end, and awaits
  a plan_json push for reinstall durability. Durability guards (NOT flag-gated, live for
  all users): a shared monotonic phase-gated PlanWindowReanchor (same phase → keep the
  later plan_end so a hold survives a stale snapshot; fresh install / phase advance →
  cloud verbatim, preserving the a7d3f1 stale-plan_start heal); and a pure `paginateAll`
  loop replacing the .range(0,999) truncation.
regression_test_planned: >
  test/contracts/hold_week_mechanic_behavioral_test.dart (7 cases: Peak source + stamps +
  flat + plan_end extension; Monday + %7 alignment; deload every 4th; gap-proof ordinal;
  crash-idempotent ordinal; plan_start never written; concurrent double-call → one hold),
  test/contracts/plan_window_reanchor_test.dart (5 cases: fresh/same-phase-later/
  phase-advance/monotonic-up/date-only), test/contracts/paginate_all_test.dart (4 cases).
  16/16 green; each fails without its fix (e.g. reverting the Peak source → src_week 4).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on all 7 touched lib files; 16/16 behavioral tests green" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "hold rows (schedule_<date> with is_hold/hold_ordinal/week) + plan_end via MigratedKey, pinned by the mechanic behavioral test" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "live information_schema: scheduled_workouts.week_number is nullable int, no CHECK; no hold_ordinal/is_hold column (kept plan_json-only) — no migration" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "no data mutation; existing rows unaffected. plan_json growth ~25 KB/hold measured acceptable (#5)" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no EF change; no EF reads week_number" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron reads scheduled_workouts.week_number" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "reinstall durability closed (holdWeek awaits pushWorkoutPlanForSyncDomain → plan_json carries the extension); restore re-anchor monotonic; pagination un-truncated — all covered by behavioral tests / ×2 review" }
impact_analysis: >
  Ship-dark: the mechanic (holdWeek) is inert until enable_hold_weeks flips (a later
  batch, after the display slices) — flag OFF runs the verbatim redoWeek4 FUNCTION
  (byte-identical). NOTE the trigger HANDLERS are NOT fully byte-identical: the H5 guard
  (graduation_screen no longer blind-navigates to /train on a materialize failure) is a
  live UX change for ALL users regardless of the flag. The durability fixes (#1 re-anchor,
  #4 pagination) are also live: #1 additionally fixes a latent collapse of today's
  redoWeek4 extension (a no-op for a non-holding, non-redo user — max(local,cloud)==cloud
  when equal); #4 is a no-op under 1000 rows. KNOWN VERIFIED residual (pre-existing —
  redoWeek4 is identical, NOT introduced here): a crash mid-materialize (after some of the
  7 upserts, before the plan_end write) leaves a truncated hold week; it is recoverable
  (the next hold re-materializes a full week and the row-local ordinal advances correctly)
  and cosmetic (a past week shows fewer days). Widening the PlanIntegrityReconciler 1..4
  scan to heal it is deliberately NOT done — that makes the reconciler fire more (the
  P0-11 concern the #1 re-anchor addresses; see closure finding D2). Blast radius measured
  as `platform` (sync/restore path) via scripts/blast_radius_from_diff.dart. Reviewed ×2
  context-blind (converged, no P0/P1) + self-triggered B-pass (4 P2s fixed/documented
  in-batch; see docs/plan-reviews/hold-mechanic.md + docs/reviews/hold-mechanic-bpass.md).
---

# Free-tier "Hold the Line" — a correct, durable hold mechanic (holdWeek)

## Root cause

The free-tier Phase-1 wall let a user "Run Week 4 again" via `redoWeek4`
(`workout_schedule_write_service.dart:172`), which had three defects and one
durability gap:

1. **Non-Monday `rollStart`** (`:181`): `todayMidnight.isAfter(planEnd) ? todayMidnight :
   planEnd + 1d` — the `today` branch starts the week on whatever weekday the user
   returned, breaking week alignment.
2. **Wrong source week** (`:178`): `week4Start = planEnd - 6` copies the *trailing*
   (deload) week every time — the "copied the deload, not the Peak" bug.
3. **Raw `DateTime.now()`** (`:179`): ignores the dev/test clock seam.
4. **Not durable**: `redoWeek4` extends `plan_end` and materializes rows via
   `upsertScheduled` (→ coalesced `syncWorkoutData`), but that fan-out does NOT push
   `plan_json` (verified: `syncWorkoutData` fan-out has no `_syncWorkoutPlan`). So the
   extension + exercise-rich rows only reach cloud on the next `weeklyFullSync` (≤24h) —
   and a stale-snapshot restore re-anchored `plan_end` back down (P0-1), collapsing the
   phase.

## Fix

`holdWeek()` (ship-dark, `enable_hold_weeks` default OFF; OFF → verbatim `redoWeek4`):

- **Backdate to this week's Monday** — `rollStart = normalizeToMonday(nowWall())` (the
  same raw-weekday normalizer `plan_start` was set with, NOT `mondayOfIst`), so today is
  always inside the fresh hold week and `(rollStart − plan_start) % 7 == 0`. A defensive
  guard bumps past `plan_end` if a stray caller runs it un-expired.
- **Source by date**: `plan_start + 14` (Peak, wk3) — or `plan_start + 21` (deload, wk4)
  on every 4th hold (`N % 4 == 0`). Loads are copied **FLAT** (verbatim — no decay: free
  maintains, PRO progresses).
- **Gap-proof ordinal**: `N = max(hold_ordinal among rows dated < rollStart) + 1`.
  Excluding rows AT `rollStart` makes a crash-partial retry idempotent (same N,
  overwrite). `hold_ordinal` / `is_hold` live on the Hive map + `plan_json` only (no
  cloud column); the row stamps `'week' = 4 + N` (the field the push maps to
  `week_number`).
- **Durability**: awaits `SyncService.pushWorkoutPlanForSyncDomain()` (→ `_syncWorkoutPlan`,
  non-coalesced, self-catching) after the `plan_end` write so the extended window + hold
  rows reach `plan_json` before any reinstall.
- **Re-entrancy**: a module-level `_holdInFlight` mutex (the `pro_phase_advance
  ._advanceInFlight` pattern) around the local writes.

Durability guards (live for all users, NOT flag-gated):

- **#1 monotonic phase-gated re-anchor** (`PlanWindowReanchor`, shared by both restore
  writers): same phase (cloud `plan_start` == local) → keep the LATER `plan_end`; fresh
  install / phase advance → cloud verbatim (preserving the a7d3f1 stale-`plan_start`
  heal). A blind `max()` would be wrong across an advance; unconditional cloud-verbatim is
  the P0-1 collapse.
- **#4 pagination**: the pure `paginateAll` loop replaces `_restoreScheduledWorkouts`'s
  `.range(0, 999)`, so a >1000-row holder's current phase survives the status merge.

## Deliberately out of scope (verified, not deferred bugs)

- **Display** (un-clamp / chip strip / reconciled header / roadmap / entry card) — later
  slices; with the flag OFF nothing is user-visible.
- **#5 plan_json growth** — verified-acceptable (measured ~25 KB/hold; 2.5 MB total across
  11 users); not a correctness bug (durability is #1 + #4). Revisit threshold: a user's
  plan_json > ~1 MB or user count > a few hundred.
- **#6 phantom-phase** — safe by construction (future-dated hold rows excluded by the
  `pastPhaseBlocks` date filter; holdWeek never writes `plan_start`), pinned by a test —
  no bucketer change needed.
