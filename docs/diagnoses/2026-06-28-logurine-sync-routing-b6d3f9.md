---
bug_id: b6d3f9
date: 2026-06-28
batch: client-wins-hardening
status: fixed
blast_radius: account
symptom: >
  HealthWriteService.logUrine writes urine_color_<date> into healthBox, then fires
  SyncService.syncNutritionData(). But syncNutritionData's fan-out is
  _syncNutritionLogs + _syncWaterLogs + _syncSavedMeals, and _syncWaterLogs reads
  ONLY water_ml_ keys (sync_nutrition.dart:289). Nothing in that fan-out reads
  urine_color_ keys, so a per-mutation urine log never pushed to cloud — the urine
  row reached water_logs (urine_color / urine_status columns) only on the next
  FULL sync (_syncUrineColorLogs at sync_service.dart). Sibling health writes
  (logSleep/logWeight/logMeasurement) each correctly fire their dedicated
  syncSleepNow / syncWeightNow / syncMeasurementsNow; only urine used the wrong
  (nutrition) route. Offline-first so no data loss — the row is durable in Hive
  and eventually consistent — but the cloud sync was delayed to the next full sync.
concept: urine_color_logs
sot_registry_entry: >
  urine_color_logs — writer HealthWriteService.logUrine (healthBox
  urine_color_<date>) now fires the dedicated SyncService.pushUrineColorLogsForSyncDomain
  (→ _syncUrineColorLogs upsert into water_logs) per-mutation, replacing the
  no-op syncNutritionData route.
writers: >
  HIVE urine_color_<date>: HealthWriteService.logUrine (healthBox). CLOUD
  water_logs.urine_color / urine_status: SyncService._syncUrineColorLogs (via the
  public forwarder pushUrineColorLogsForSyncDomain), invoked per-mutation by
  logUrine (NEW) and in the full restore/sync pass (sync_service.dart ~:950) and
  the HealthSyncDomain.push() (flag-gated, not yet wired).
readers: >
  water_logs.urine_color / urine_status — restored into healthBox urine_color_
  keys by sync_nutrition.dart restore path (~:494-502); rendered by the hydration
  / urine UI in the nutrition feature.
hive_key_prefix: urine_color_
hive_key_formula: "'urine_color_' + istDateStr(date)"
sync_methods: ["pushUrineColorLogsForSyncDomain", "_syncUrineColorLogs"]
restore_methods: ["restore via sync_nutrition.dart urine reconstruction (~:494)"]
cloud_table: water_logs
cloud_columns: ["urine_color", "urine_status"]
contract_test_path: test/contracts/log_urine_sync_routing_test.dart
ist_handling: >
  The urine Hive key uses istDateStr(date) (urine_color_<istDate>) and the cloud
  upsert keys on user_id,date — unchanged by this fix. No timestamp semantics
  changed; this is purely a sync-trigger routing correction.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["upsert_urine_color_log"]
cross_account_guard: false
forbidden_patterns_checked:
  - "A per-mutation write whose fire-and-forget sync trigger targets a DIFFERENT domain than the row it wrote, so the row's own sync method is never invoked on that write (it lands in cloud only on the next full sync). logUrine wrote healthBox urine_color_ but fired syncNutritionData (nutrition/water/saved-meal fan-out), whose _syncWaterLogs reads only water_ml_ keys. FIXED: logUrine now fires pushUrineColorLogsForSyncDomain, the dedicated urine push."
proposed_fix: >
  Replace the unawaited(syncNutritionData()) call in logUrine with
  unawaited(pushUrineColorLogsForSyncDomain()) so the healthBox urine_color_<date>
  row reaches cloud (water_logs.urine_color/urine_status) per-mutation, matching
  the dedicated-push pattern the other health writes already use. pushSnapshot()
  is unchanged. setWaterMl (writes water_ml_) and logHydration (writes a separate
  local hydration_ snapshot) correctly keep syncNutritionData / their existing
  routes — water_ml_ IS in the nutrition fan-out, and hydration_ is a local-only
  derived snapshot whose component data (urine + water) syncs via its own keys.
regression_test_planned: >
  test/contracts/log_urine_sync_routing_test.dart — comment-stripped source
  contract scoped to the logUrine method body: asserts it fires
  pushUrineColorLogsForSyncDomain and does NOT contain syncNutritionData. Fails on
  the pre-fix tree. Behavioral coverage of the push itself (urine_color_ →
  water_logs upsert) lives in the existing sync-layer urine tests.
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — 1 edit: health_write_service.dart logUrine fires pushUrineColorLogsForSyncDomain instead of syncNutritionData."
  - "client_to_server_contract — status: verified — _syncWaterLogs (the nutrition route) reads only water_ml_ keys; _syncUrineColorLogs (the dedicated route, now invoked) upserts urine_color/urine_status into water_logs onConflict user_id,date — confirmed by reading sync_nutrition.dart:286-311 + sync_health.dart:256-281."
impact_analysis: >
  Affects any user logging urine color between full syncs — the value was durable
  locally (Hive) but its cloud projection lagged until the next full sync (next
  app open / daily). No data loss (offline-first; eventually consistent). Fix makes
  urine sync promptly per-mutation like the other health writes. Behavior-preserving
  for water (setWaterMl) and the local hydration_ snapshot. Low blast radius — a
  single sync-trigger routing correction in one write method.
---

# b6d3f9 — `logUrine` fired the nutrition sync, which never pushes the urine row

See YAML frontmatter for the full diagnosis. Surfaced during the
client-wins-hardening batch (Unit C re-verification) while confirming the plan's
"urine prompt-sync delayed" claim by file:line.

## Root cause (one line)
`logUrine` wrote `urine_color_<date>` to **healthBox** but fired
`syncNutritionData()`, whose `_syncWaterLogs` reads **only** `water_ml_` keys — so
the urine row's own push (`_syncUrineColorLogs`) was never triggered per-mutation
and the row reached cloud only on the next full sync.

## Fix
`logUrine` now fires the dedicated `pushUrineColorLogsForSyncDomain()` (→
`_syncUrineColorLogs`), matching the per-mutation pattern `logSleep` / `logWeight`
/ `logMeasurement` already use. One line; `setWaterMl` + `logHydration` unchanged.
