---
bug_id: 4c1e7a
date: 2026-09-02
batch: readiness-flip
blast_radius: platform
status: fixed
symptom: >
  Tapping "Sync your sleep for a sharper read." in the pre-workout readiness sheet
  showed the user the full native Health Connect STEPS + WEIGHT consent dialog --
  data they did not ask to share -- and, on grant, wrote step_<date> and
  weight_<date> rows to Hive and the cloud while the user's own Profile health-sync
  toggle (health_sync_enabled) remained false. Caught by the batch's own B-pass
  before merge; never shipped.
concept: readiness_daily
sot_registry_entry: readiness_daily
writers:
  - file: lib/core/services/health_sync_service.dart
    method: syncSleepOnly
    line: 231
  - file: lib/core/services/health_write_service.dart
    method: logSleep
    line: 67
readers:
  - file: lib/features/train/widgets/readiness_sheet.dart
    method_or_widget: _onTapSyncSleep
    line: 91
  - file: lib/core/services/health_read_service.dart
    method_or_widget: sleepHoursForDate
    line: 60
hive_key_prefix: sleep_log_
hive_key_formula: "'sleep_log_${istDateStr(date)}'"
sync_methods: [syncSleepOnly, syncToHive, syncSleepNow]
restore_methods: [_restoreSleepLogs]
cloud_table: sleep_logs
cloud_columns: [user_id, date, duration_hrs, quality, created_at]
contract_test_path: test/contracts/readiness_sheet_states_test.dart
ist_handling:
  - file: lib/core/services/health_sync_service.dart
    line: 240
    fn: istTodayStr
  - file: lib/core/services/health_sync_service.dart
    line: 246
    fn: nowWall
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [health_sync_sleep_only, health_sync_request_sleep_permission]
cross_account_guard: false
forbidden_patterns_checked:
  - pattern: "syncToHive"
    absent: true
proposed_fix: >
  Add HealthSyncService.syncSleepOnly(), which fetches sleep and writes it via
  HealthWriteService.logSleep without entering the steps/weight permission branch,
  and point the sheet's nudge at it instead of the shared syncToHive().
regression_test_planned:
  - test/contracts/readiness_sheet_states_test.dart
  - test/contracts/readiness_sleep_axis_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on health_sync_service.dart + readiness_sheet.dart; syncSleepOnly() added and the nudge repointed at it" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "shouldWriteSyncedSleep(hours, existingRow) extracted pure and covered by 4 tests in readiness_sleep_axis_test.dart, including manual-entry-always-wins (an existing sleep_log_ row blocks the sync write)" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change; sleep_logs already exists" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "never shipped, so no rows were produced by the defect" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched; grep -rniE readiness supabase/functions/ returns 0" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret referenced" }
  - { tier: 11, name: external_services, status: verified, evidence: "Health Connect treats sleep as a permission SEPARATE from steps/weight. READ_SLEEP is declared in AndroidManifest.xml; _sleepTypes/_sleepPermissions are tracked separately from _types so neither track can disable the other. The remaining unprovable-in-suite half (does the device return a session?) is the on-device logcat check." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the write routes through HealthWriteService.logSleep, which stamps duration_hrs alongside sleep_hours -- sync_health.dart pushes duration_hrs with NO fallback, so a raw healthBox.put would have upserted NULL over a good cloud row and _restoreSleepLogs would have written that back" }
impact_analysis: >
  Never shipped -- caught by the B-pass on 9e4c5681 before the merge to main, in
  the same batch that introduced it. Had it shipped, the blast radius would have
  been every user who tapped the sleep nudge without having enabled health sync:
  they would see a consent dialog for steps and weight, and granting it would have
  produced step/weight rows that the app then stopped collecting (because
  health_sync_enabled stayed false) -- a one-off, unrequested write with no
  follow-through. No production data was affected.
---

# Sleep nudge opened the steps/weight permission dialog

## What happened

The readiness sheet's State B (no measured sleep) renders a tappable nudge whose entire
purpose is to obtain the Health Connect **sleep** grant. It did:

```dart
final granted = await HealthSyncService.instance.requestSleepPermission();
if (granted) await HealthSyncService.instance.syncToHive();   // <-- the defect
```

`syncToHive()` → `_syncToHiveLocked()` carries its own steps/weight permission block:

```dart
if (_health == null || !_permissionsGranted) {
  final quietOk = await _checkPermissionsQuietly();
  if (!quietOk) {
    final granted = await requestPermissions();   // full STEPS+WEIGHT dialog
```

`_permissionsGranted` is an in-memory field on a singleton, so it is false on every cold
start. The two OTHER callers of `syncToHive()` (`splash_screen.dart`, `profile_provider.dart`)
both wrap it in `if (HealthSyncService.isEnabled())` — the sheet's nudge inherited the shared
function without inheriting that guard.

## Root cause — a guard written in one direction only

`health_sync_service.dart` had just been given a comment promising the exact invariant it
violated:

> *"Sleep must fail soft, both ways."*

The batch guarded **"a steps/weight denial must not kill sleep"** — verified, correct, and the
reason the sleep block sits above the permission gate. It did not guard the mirror:
**"a sleep-only user action must not reach into steps/weight."** The sentence claiming both
directions was written while only one was true.

## Fix

`HealthSyncService.syncSleepOnly()` — fetch sleep, apply the same
`shouldWriteSyncedSleep` guard, write through `HealthWriteService.logSleep`, and never touch
`_checkPermissionsQuietly` / `requestPermissions`. The nudge calls that.

## Recurrence

`guard_without_its_mirror` — the repo's most recurrent class (20+ instances across 9 sessions
per `feedback_mistake_guard_without_its_mirror.md`). The specific sub-shape here is new and
worth naming: **a shared entry point inherits the union of every caller's side effects.** A
narrow, well-scoped user action ("grant me sleep") routed through a broad shared function
("sync everything") silently acquires that function's whole permission surface. The tell is a
guard living at the *call sites* rather than inside the function — two callers had it, the
third did not, and nothing made that visible from inside.

Related: the same batch's `enable_readiness` / `enable_triggered_deload` kill-switches
initially had no writer anywhere in the app (§4.6 — a gate nothing can close), which is the
same family one level out.
