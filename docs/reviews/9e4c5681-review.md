---
reviewed_at: 2026-09-02T00:07:02+05:30
staged_against: 9e4c5681
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, same_class_in_the_fix]
findings_count: 5
verdict: accepted
---

# Code Review — 9e4c5681 (readiness + triggered_deload flip)

All 5 findings independently re-verified against source before acceptance, then
fixed in-batch. None rejected.

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** `lib/features/train/widgets/readiness_sheet.dart:90-99` → `lib/core/services/health_sync_service.dart` `_syncToHiveLocked`
- **claim:** The sheet's "Sync your sleep" nudge called `requestSleepPermission()` then
  `syncToHive()`. `_syncToHiveLocked` has no `health_sync_enabled` gate of its own — that lives
  only in the two OTHER call sites — so a user who has never opened Profile → Health Sync and
  taps only the sleep nudge gets the **full native STEPS+WEIGHT consent dialog**, unrelated to
  what they tapped, and on grant writes step/weight rows while `health_sync_enabled` stays false.
  The file's own comment promises "Sleep must fail soft, both ways"; the reverse mirror — a
  sleep-only action must not reach into steps/weight — had no guard at all.
- **verification:** `grep -n "syncToHive\|syncSleepOnly" lib/features/train/widgets/readiness_sheet.dart`
- **fix:** Added `HealthSyncService.syncSleepOnly()` — fetches + writes sleep without touching the
  steps/weight permission path. The nudge calls that instead.
- **status:** fixed

## Finding 2 — P2 — same_class_in_the_fix

- **file:line:** `docs/sot_registry.yaml` `sleep_logs` concept vs the new writer
- **claim:** The batch registered a THIRD writer under `sleep_logs`, whose
  `behavioral_test_path` (`sleep_logs_behavioral_test.dart`) knows nothing about it — Gate 42
  reads GREEN on a pre-existing test that never executes the new path. This is rule 21's own
  documented trap, reproduced by the commit that cites it.
- **verification:** `grep -n "HealthSyncService\|_syncToHiveLocked" test/contracts/sleep_logs_behavioral_test.dart` → no match
- **fix:** Extracted the write decision to a pure `HealthSyncService.shouldWriteSyncedSleep(hours,
  existingRow)` and added 4 tests in `readiness_sleep_axis_test.dart` covering it, including the
  manual-entry-wins case.
- **status:** fixed

## Finding 3 — P2 — writer_reader_drift (clock seam)

- **file:line:** `lib/core/services/health_sync_service.dart` sleep block
- **claim:** The guard read `hive.healthBox.get('sleep_log_$todayStr')` where `todayStr` comes
  from `istTodayStr()` (test-clock aware via `nowWall()`), but the write passed
  `logSleep(date: now)` with a raw `DateTime.now()`. Under dev-panel time travel the guard checks
  one date and the write lands on another. Inert in release, but it breaks precisely the
  dev-panel surface this feature is verified on.
- **verification:** `grep -n "String istTodayStr" -A1 lib/core/utils/ist_date.dart` → `istDateStr(_wallNow())`
- **fix:** `date: nowWall()`.
- **status:** fixed

## Finding 4 — P3 — asserted_fixture_value (self-inflicted stale citation)

- **file:line:** `volume_titration.dart:16`, `plan_engine/CLAUDE.md:122`, `sot_registry.yaml`
- **claim:** The new comment cites "short-circuits at volume_titration.dart:56"; the guard is at
  `:60` — the comment block being inserted shifted it. Third stale-citation instance in this batch.
- **verification:** `grep -n "volumeTitrationEnabled || phase" lib/shared/repositories/plan_engine/volume_titration.dart` → `60:`
- **fix:** `:56` → `:60` in all three copies.
- **status:** fixed

## Finding 5 — P3 — doc drift (retired flag names)

- **file:line:** `day_rollover_service.dart:174`, `deload_evaluator.dart:14`, `plateau_scan.dart:18`
- **claim:** Three comments still describe the gate as `enable_*` after the keys were retired.
- **verification:** `grep -n "enable_readiness\|enable_triggered_deload" <those three files>`
- **fix:** Updated to `disable_*` with the LIVE date.
- **status:** fixed

## Lenses that returned clean

- **writer_reader_drift (main chain):** traced `logSleep` → both `sleep_hours` AND `duration_hrs`
  on `sleep_log_<istDate>` → `sync_health` pushes `duration_hrs` → restore → `sleepHoursForDate`
  reads either. Round-trips through a reinstall. `git diff main..HEAD -- sync_health.dart
  sync_service.dart health_write_service.dart` → empty; the batch reused the pre-hardened writer
  rather than a raw put, as claimed.
- **blast_radius_mismatch:** platform `requires:` all met — regression tests present,
  `behavioral_test_path` present, B-pass done, both flags ship kill-switches.
- **secrets_in_tree:** credential-shaped grep over the diff → only a skill name, no credentials.
- **unawaited_no_error_sink:** 4 new `unawaited(` call sites, all `ErrorTelemetry.recordNonFatal`
  inside catch blocks.
- **missing_input:** `READ_SLEEP` confirmed in `AndroidManifest.xml`. `SLEEP_SESSION` confirmed in
  `dataTypeKeysAndroid` (absent from iOS, matching the code comment). SHAPE proven from
  `HealthDataReader.kt` `handleSleepData` — `SLEEP_SESSION` converts the whole record; every other
  sleep type iterates stages. Both existence and shape proven from source.
- **asserted_fixture_value:** recomputed every `sleepAxisFromHours` boundary by hand. The flag
  default test would fail under pre-flip code — not a vacuous carry-over.
- **modelled_on_is_a_checkable_claim:** diffed the new dev-panel toggles against
  `_toggleEquipmentExclusions` and the new getters against `equipmentExclusionsEnabled` — identical
  shape on every axis.
- **"SEVEN tests broke":** independently re-derived; `grep -rn "enable_readiness|enable_triggered_deload"
  test/ integration_test/` → empty. ~475 tests exercised across 17 additional files looking for an
  8th or a newly-vacuous test; none found.
- **mutation evidence reproduced:** the reviewer independently re-ran Mutation B (polarity flip)
  and measured **22 failures**, matching the commit's claim. Reverted and verified clean.

## Founder triage notes

All 5 accepted and fixed in-batch (§4.2). Findings 1 and 3 are real behavioural defects that
would have shipped; 2 is a test-coverage gap of the exact class rule 21 documents; 4 and 5 are
documentation accuracy.
