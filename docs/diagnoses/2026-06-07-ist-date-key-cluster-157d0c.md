---
bug_id: 157d0c
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 2, IST cluster)
status: fixed
blast_radius: account
symptom: >
  Across home / train / nutrition / AI-coach / profile, many READERS built a
  device-local 'YYYY-MM-DD' date key
  ('${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day...}') while their
  WRITERS key by IST (istDateStr). On any device whose local date != IST
  (NRI / traveller / emulator-on-UTC), the reader looked up the wrong day:
  just-logged meals vanished from the calorie ring, "today's workout" / the
  weekly calendar showed the wrong day, superset grouping was silently lost on
  restart, the proactive greeting mis-fired, and several sync writes stamped a
  naive-local timestamp into a timestamptz column (parsed as UTC → 5.5h future).
concept: ist_date_key_consistency
sot_registry_entry: "enforced by scripts/check_local_date_key_drift.dart (gate) — spans every date-keyed reader, not a single storage concept"
writers:
  - "{ file: lib/core/utils/ist_date.dart, method: istDateStr, line: 88 } — the canonical IST date-key producer every writer keys with"
readers:
  - "{ file: lib/features/train/providers/train_provider.dart, method: _persistSupersetGroups, line: 1183 } — superset schedule lookup (P1 data loss)"
  - "{ file: lib/core/services/nutrition_read_service.dart, method: totalMacrosForDate, line: 96 } — calorie ring sum"
  - "{ file: lib/features/home/providers/home_provider.dart, method: CalendarWeekNotifier.build, line: 78 } — weekly calendar / streak-warning math"
hive_key_prefix: "schedule_ / nlog_ / weight_ / step_ / exlog_ (all IST-keyed)"
hive_key_formula: "<prefix>${istDateStr(date)}"
sync_methods: n/a (read-side fixes + sync push-timestamp UTC fixes)
restore_methods: n/a
cloud_table: "workout_schedule_completions / daily_steps / water_logs / sleep_logs (the F36 timestamp writes)"
cloud_columns: "completed_at, synced_at, updated_at, created_at (timestamptz — naive-local → .toUtc())"
contract_test_path: scripts/check_local_date_key_drift.dart
ist_handling: >
  The entire fix IS IST handling. Readers now derive keys via istDateStr(date) /
  istTodayStr() / istMidnight() / mondayOfIst() (lib/core/utils/ist_date.dart),
  matching the IST-keyed writers. Sync push timestamps use
  DateTime.now().toUtc().toIso8601String(). Already-IST values (mondayOfIst /
  istNow loop vars / a duplicate istDateStr impl) and DOB strings are allowlisted
  in the gate (calling istDateStr on an already-IST value would double-shift — the
  Test #11.1 bug).
provider_invalidations: n/a (read paths)
telemetry_op_types: n/a
cross_account_guard: user-scoped — the date-keyed boxes are accessed via wrapUserScopedBox
forbidden_patterns_checked: >
  device-local '${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day...}'
  construction in lib/ — banned by scripts/check_local_date_key_drift.dart
  (hard-fail, LEGIT allowlist only).
proposed_fix: >
  Swap every device-local date-key reader for the matching IST helper; swap naive
  sync timestamps for .toUtc(); add scripts/check_local_date_key_drift.dart to
  stop the class recurring.
regression_test_planned: scripts/check_local_date_key_drift.dart (gate, hard-fail) — GREEN; existing writer/reader round-trip tests cover the per-key behaviour (device==IST in CI so they pass on both old + new code)
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: 25 reader/writer date-key sites swapped to IST helpers across home/train/nutrition/ai_coach/profile/sync; flutter analyze clean; gate green }"
  - "{ layer: postgres_data, status: fixed_in_this_batch, evidence: sync push timestamps (completed_at/synced_at/updated_at/created_at) now .toUtc() — values written going forward are correct UTC; historical skew is read-tolerant }"
  - "{ layer: postgres_schema, status: not_applicable, evidence: no schema change — columns already timestamptz / IST-string dates }"
  - "{ layer: client_to_server_contract, status: verified, evidence: writers already keyed IST; readers now agree — round-trip consistent on every timezone }"
impact_analysis: >
  Visible only on devices whose local date differs from IST (NRI / traveller /
  misconfigured / emulator-on-UTC). India-IST devices (the launch audience + CI
  with TZ=Asia/Kolkata) were unaffected, which is why these survived. Highest
  impact: F27 (meals vanish from the calorie ring) and F23 (superset grouping
  lost on restart, P1). 25 sites fixed; 7 legit sites allowlisted; the gate makes
  the IST-sweep-gap class non-recurring.
closes-diagnose: 157d0c
---

# IST date-key drift cluster (F4 / F6 / F7 / F8 / F9 / F23 / F24 / F27 / F36 + sweep)

## Class
The recurring **IST-sweep-gap** (`feedback_use_ist_throughout` / `feedback_ist_sweep_gap`):
a reader hand-rolls a device-local `'${x.year}-${x.month..}-${x.day..}'` date key
instead of `istDateStr(x)`, so it drifts vs the IST-keyed writer on any non-IST device.
The audit flagged 9 sites; the new gate surfaced the full class — **25 sites**.

## Fixed (25 reader/writer sites)
- **Audit-flagged (9):** daily_completion (F4), calendarWeek + TodaySteps + health_sync step-writer (F6/F7), ai_snapshot today_nutrition + trend (F8), coach_memory greeting + notes (F9), superset persist (F23, P1) + todayWorkout (F24), nutrition_read_service + nutrition_repository + nutrition_provider (F27), sync_workout + sync_health timestamps → `.toUtc()` (F36).
- **Sweep-surfaced (16):** day_rollover_service, reschedule/injury/hotel/pause/regenerate planners (`_fmt`), week_rows + expanded_exercises + hero_cards (train widgets), weekly_report_data_provider, tool_dispatcher `_todayDateString`, pattern_detector `_formatDate`.

## Allowlisted (LEGIT — 7 files)
`ist_date.dart` + `date_utils.dart` (the helpers), `workout_write_service` (its own istDateStr impl), `streak_progress_service` (builds from `mondayOfIst` — already IST), `workout_repository` (already-IST loop var), `nlog_key_migrator` (already-IST `istDate`), `edit_profile_screen` (DOB — fixed calendar date). Calling `istDateStr` on an already-IST value double-shifts (Test #11.1) — these correctly format inline.

## Gate
`scripts/check_local_date_key_drift.dart` (hard-fail) bans the device-local construction in `lib/` outside the LEGIT allowlist. Auto-wired via the dynamic `scripts/check_*.dart` glob.
