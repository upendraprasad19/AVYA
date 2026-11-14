---
bug_id: c4f8d2
date: 2026-06-27
batch: sync-cost-debounce
status: fixed
blast_radius: platform
symptom: >
  Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) proved the client
  phones the cloud far too often. A FRESH SIGNUP fired ~90 cloud ops in 27 s —
  syncWorkoutData() (the SoT fan-out) fired ~18× (once per onboarding Hive write),
  each emitting 5 ops, plus a pushSnapshot storm — which collapsed the free-tier
  backend (a 9.5-minute telemetry blackout, statement timeout 57014 +
  WORKER_RESOURCE_LIMIT 546) and stranded the user on a stuck-Home skeleton. A
  RETURNING login made ~190 ops (96 scheduled_workouts re-upserts + 94 fan-out
  ops). Home itself renders fine on a healthy backend (confirmed live) — the
  skeleton was the backend-collapse SYMPTOM, not a Hive-first/data bug.
concept: fire_and_forget_sync_coalescing
sot_registry_entry: sync_fanout_workout_domain + sync_fanout_nutrition_domain (writer timing annotated — the per-write entry now coalesces and delegates the fan-out to syncWorkoutDataNow / syncNutritionDataNow)
writers: >
  lib/core/services/sync/sync_workout.dart (syncWorkoutData — now the COALESCED
  per-write entry; syncWorkoutDataNow — the non-coalesced fan-out);
  lib/core/services/sync/sync_nutrition.dart (syncNutritionData / syncNutritionDataNow);
  lib/core/services/sync_coalescer.dart (SyncCoalescer — in-flight + dirty do-while);
  lib/core/services/sync_service.dart (coalescer fields + disable_sync_debounce
  kill-switch + flushPendingSyncs on app-pause; pushSnapshot now routed through
  SupabaseService.callFunction, kill-switch disable_pushsnapshot_via_callfunction);
  lib/core/services/hive_service.dart (onAppPaused hook);
  lib/shared/mixins/hive_tab_scaffold.dart (initState clears the skeleton on the
  first Hive frame, kill-switch disable_skeleton_first_frame).
readers: >
  The ~14 WriteService / repository / provider call-sites that fire
  unawaited(syncWorkoutData()) / unawaited(syncNutritionData()) after a Hive
  mutation (unchanged — they keep the coalesced path). The 2 AWAITED callers
  (scheduled_workouts_resync_migrator.dart:88, simulation_service.dart:290/291)
  now call the non-coalesced *Now() variants so awaited completion stays durable.
  pushSnapshot's consumers (the coach_memory Hive mirror at sync_service.dart) are
  unchanged — callFunction returns the full FunctionResponse.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: ["SyncService.syncWorkoutData", "SyncService.syncWorkoutDataNow", "SyncService.syncNutritionData", "SyncService.syncNutritionDataNow", "SyncService.pushSnapshot", "SyncService.flushPendingSyncs"]
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/sync_coalescer_behavioral_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["sync_workout_data", "sync_nutrition_data", "push_snapshot"]
cross_account_guard: true
forbidden_patterns_checked:
  - "An un-debounced fire-and-forget sync fan-out — every Hive write fired unawaited(syncWorkoutData()) / unawaited(pushSnapshot()), so a burst of N writes became N full cloud passes (~18 on a fresh signup), flooding the free-tier backend. FIXED — coalesced at the single fan-out entry (SyncCoalescer): a burst collapses to 1-2 passes. The do-while trailing-pass drains writes that land mid-pass (no silent loss). Awaited callers carved out to the non-coalesced *Now() variants."
proposed_fix: >
  Three converged units (the ×2 + Opus-4.8 ×4-lens review rejected the data-lossy
  delta-sync/dirty-schedule ideas and split the returning-user 96-tax to a separate
  H1b unit). H1a — coalesce the fire-and-forget LOG syncs: syncWorkoutData() /
  syncNutritionData() become COALESCED entries (in-flight + dirty do-while via
  SyncCoalescer) that delegate the full fan-out to syncWorkoutDataNow() /
  syncNutritionDataNow(); the 3 awaited callers (2 migrators are actually
  unawaited — only scheduled_workouts_resync + the sim harness await) use *Now();
  the do-while loops until clean so a write during the trailing pass is never
  dropped; bookkeeping sits AFTER the pausedForSimulation guard; a best-effort
  flush fires on AppLifecycleState.paused (the next login's full sweep is the real
  backstop — Hive is SoT). H3 — route pushSnapshot through callFunction
  (retryColdStart 502/503/504), preserving the coach_memory mirror + token refresh.
  H5 — HiveTabScaffoldMixin clears the skeleton on the first Hive frame (never
  gated on initTab()'s async tail), preserving the isLoading||isSessionTearingDown
  OR. All behind kill-switches (disable_sync_debounce / disable_pushsnapshot_via_callfunction
  / disable_skeleton_first_frame) per §4.6.
regression_test_planned: >
  test/contracts/sync_coalescer_behavioral_test.dart — fakeAsync behavioral harness
  pinning the two semantics the review demanded: (1) a burst of 10 triggers during
  one in-flight pass collapses to ≤2 passes; (2) a trigger arriving DURING the
  trailing pass runs ANOTHER pass (the passes==3 assertion requires the do-while
  while-loop — a naive single-trailing-pass / clear-after impl gives 2 and silently
  drops the last write). Plus the updated source-grep contracts (sync_fanout,
  template-before-schedule, public-API-snapshot, guarded_box _ensureSessionOpen,
  sync_domain exhaustiveness) re-pointed at the *Now() variants. Full suite 3032
  green; flutter analyze clean (pre-existing infos only).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "SyncCoalescer + the coalesced/Now split in sync_workout.dart + sync_nutrition.dart; pushSnapshot via callFunction; HiveTabScaffoldMixin first-frame clear; HiveService.onAppPaused flush hook. flutter analyze clean on all touched files." }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "Hive remains the source of truth — coalescing only changes the TIMING of the cloud push, never the local write (WriteServices still write Hive synchronously before the unawaited sync). A coalesced/dropped push leaves Hive authoritative; the next login's full sweep (syncWorkoutDataNow re-pushes ALL local rows) reconciles. The cross-account guard resets both coalescers in _onUserChanged so an owed pass never crosses accounts." }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "pushSnapshot now invokes daily-snapshot via callFunction (same function name + body + auth header as the raw invoke; callFunction refreshes the token first, preserving BUG-C d3a1c7); the EF itself is unchanged/undeployed by this batch." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "the cloud rows still land — just coalesced into 1-2 passes per burst instead of one-per-write; the per-helper fan-out (templates-first FK-23503 ordering) is preserved inside syncWorkoutDataNow (pinned by sync_template_before_schedule_order_test). Full suite 3032 green. Live before/after call-count re-verify on :8082 is founder-gated." }
impact_analysis: >
  Platform blast radius (the sync fan-out fires on every workout/nutrition write).
  The bug class is "un-debounced fire-and-forget sync fan-out (per-write cloud
  push) → free-tier backend collapse": cloud cost scales with the NUMBER of calls,
  not users, so one signup ≈ 90 calls and one returning login ≈ 190. After H1a+H3
  a signup is a handful of calls — a ~20x reduction at ZERO infra spend, which keeps
  the free tier viable to thousands of users (revisit Supabase Pro only if real
  concurrent load later proves it). The RETURNING-user 96-upsert tax (one full
  sweep of N schedule rows) is NOT cut by debounce alone — it is a separate, careful
  H1b unit (per-schedule-row dirty-filter respecting the d9b2c5 stale-cloud re-push
  healer + a pushSnapshot debounce with eager-on-identity durability, NOT web
  paused-only). The data-lossy quick versions (delta-sync since→last_synced; a naive
  dirty-schedule gate) were REJECTED by the ×2 + Opus-4.8 review — they re-tread the
  pinned restore-window anti-pattern (feedback_mistake_restore_window) and break the
  d9b2c5 contract. related: a1f9c4 (the boot/onboarding Hive-first fix — same
  free-tier-collapse incident, the navigation half); docs/reviews/e2e-fullcharter-2026-06-21-evidence.md.
---

# Sync cost: un-debounced fire-and-forget fan-out → free-tier collapse (c4f8d2)

## What happened
Live telemetry for a fresh signup (`e34b04a9`) showed **~90 cloud ops in 27 s** —
`syncWorkoutData()` fired **~18×** (once per onboarding Hive write), each a full
5-op fan-out, plus a `pushSnapshot` storm. The free-tier backend collapsed (a
**9.5-minute telemetry blackout**, `statement timeout 57014` +
`WORKER_RESOURCE_LIMIT 546`), which stranded the user on a stuck-Home skeleton. A
returning login made **~190 ops** (96 `scheduled_workouts` re-upserts + 94 fan-out
ops). Home renders fine on a healthy backend — the skeleton was the collapse
*symptom*.

## Root cause (the class)
**An un-debounced fire-and-forget sync fan-out.** Every Hive write fires
`unawaited(syncWorkoutData())` / `unawaited(pushSnapshot())`, so a burst of N
writes becomes N full cloud passes. Cloud cost scales with the *number of calls*,
not users — one signup ≈ 90 calls.

## Fix (H1a + H3 + H5 — the converged scope after a ×2 + Opus-4.8 4-lens review)
- **H1a — coalesce** `syncWorkoutData()` / `syncNutritionData()` via `SyncCoalescer`
  (in-flight + dirty **do-while**): a burst collapses to 1–2 passes. The body moved
  to the non-coalesced `syncWorkoutDataNow()` / `syncNutritionDataNow()`; the 2
  awaited callers (resync migrator + sim) use `*Now()`. Do-while drains a
  mid-trailing-pass write (no silent loss); bookkeeping after the sim-pause guard;
  app-pause flush (next-sweep is the real backstop, Hive is SoT). Kill-switch
  `disable_sync_debounce`.
- **H3 — `pushSnapshot` → `callFunction`** (retryColdStart 502/503/504), preserving
  the `coach_memory` mirror + token refresh. Kill-switch `disable_pushsnapshot_via_callfunction`.
- **H5 — skeleton clears on the first Hive frame** (never gated on `initTab()`'s
  async tail); the `isLoading || isSessionTearingDown` OR is preserved. Kill-switch
  `disable_skeleton_first_frame`.

## Review (rejected, by direct-Read verification)
- **Delta-sync (since→last_synced)** — REJECTED: the Step-B pulls page on
  creation/event columns, not a mutation timestamp → drops late edits/completions;
  re-treads `feedback_mistake_restore_window`.
- **Dirty-schedule gate** — REJECTED: breaks the **d9b2c5** stale-cloud re-push
  healer (cross-device completion loss).
- **Skip-restore-on-signup** — REJECTED: already implemented (`restoring_screen.dart:110`);
  re-keying on `StartMissionBrief` widens the **e2a4f7** misclassification P0.
- The returning-user 96-upsert tax → split to **H1b** (its own review).

## Verification
- `test/contracts/sync_coalescer_behavioral_test.dart` (fakeAsync; burst→≤2, no-loss
  while-loop, no-wedge).
- Full suite **3032 green**, exit 0; `flutter analyze` clean (pre-existing infos only).
- Updated source-grep contracts re-pointed at the `*Now()` variants.
- Live before/after `client_errors` group-by-op_type on :8082 — founder-gated.

## See also
- `lib/core/services/sync_coalescer.dart`, `lib/core/services/sync/sync_workout.dart`,
  `lib/core/services/sync/sync_nutrition.dart`, `lib/core/services/sync_service.dart`.
- `a1f9c4` (boot/onboarding Hive-first — the navigation half of the same incident).
- `docs/reviews/e2e-fullcharter-2026-06-21-evidence.md` (the Unit G live-walk finding).
