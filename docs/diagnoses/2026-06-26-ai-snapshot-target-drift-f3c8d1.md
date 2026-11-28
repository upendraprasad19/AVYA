---
bug_id: f3c8d1
date: 2026-06-26
batch: fix-ai-snapshot-drift
status: fixed
blast_radius: account
symptom: >
  Founder-directed AI-chat investigation (2026-06-26) — the AI Coach sends
  `AiSnapshotBuilder.buildAiContext()` to Gemini on EVERY chat turn (and the same
  snapshot, pushed to `user_daily_snapshots`, is read by the morning-alert /
  protein-gap-alert / streak-guardian crons). A field-by-field audit found FIVE
  writer/reader drifts feeding the coach wrong values every turn:
  (1 · P0) `daily_calorie_target` read `profile['tdee']` (MAINTENANCE) instead of the
  goal-adjusted canonical `daily_calories` — a fat-loss user's coach advised calories
  off maintenance, hundreds of kcal too high (morning-alert read this too);
  (2 · P0) `daily_targets.protein` read phantom `protein_g_target`/`protein_target_g`
  (NO writer emits them) → always 0 — the coach saw a 0 g protein goal;
  (3 · P1) `current_streak_days` was `current_streak_weeks * 7` (wrong on any partial
  week) instead of the real, now-reliably-stamped `progress['current_streak_days']`;
  (4 · P2) `daily_targets` carried only protein — no calories/carbs/fat, so the coach
  couldn't compute remaining macros against `today_nutrition`;
  (5 · P2) `planned_this_week` DOUBLE-COUNTED travel days — swap_service marks
  status:'travel' but keeps type:'workout', inflating a traveling user's planned
  count. (The type=='workout' count itself is CORRECT — the plan writer stamps
  type:'workout' at workout_schedule_read_service.dart:160; an Opus-audit claim
  that "no writer emits it → always 0" was an ERROR the hive_key_contracts contract
  test + the reader-manifest gate caught before merge. See Notes.)
concept: ai_snapshot_building
sot_registry_entry: ai_snapshot_building
contract_test_path: test/contracts/ai_snapshot_builder_only_test.dart
writers: >
  `AiSnapshotBuilder.buildAiContext` (ai_snapshot_builder.dart) is the snapshot
  writer. The CANONICAL sources it now reads: `BmrCalculator.toMap`
  (bmr_calculator.dart:309 — `daily_calories`, `protein_grams`, `carb_grams` +
  `carbs_grams`, `fat_grams`) persisted to `userBox['profile']` by onboarding /
  recalculateTargets; `current_streak_days` (workout_repository reckon + train_provider
  :1452); `schedule_*` Hive rows (the plan) for planned_this_week.
readers: >
  `ai-proxy` Edge Function (Gemini chat) reads the snapshot each turn. The cron
  Edge Functions read the pushed snapshot: `morning-alert/index.ts:149,157`
  (`current_streak_days`, `daily_calorie_target`), `protein-gap-alert/index.ts:177`
  (`daily_targets.protein` — a DEFENSIVE fallback; its PRIMARY is cloud
  `user_profile.protein_grams:140`, so the cron was already correct). All benefit
  from the corrected snapshot; no Edge Function change is required.
hive_key_prefix: "schedule_ (read for planned_this_week)"
hive_key_formula: "schedule_<istDateStr> — the date lives in the key"
sync_methods:
  - "pushSnapshot → user_daily_snapshots.snapshot_json (the cron read surface; fire-and-forget on launch + after mutations)"
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: "snapshot_json (the buildAiContext map)"
ist_handling: "_getThisWeekWorkouts uses istNow/istDateStr for the week window + schedule date compare (unchanged)"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "buildAiContext reads user-scoped Hive boxes via HiveService (unchanged)"
forbidden_patterns_checked:
  - "daily_calorie_target reads canonical daily_calories (fallback tdee), NOT tdee-as-target."
  - "daily_targets.{protein,calories,carbs,fat} read the BmrCalculator.toMap canonical fields (carbs dual-name carb_grams ?? carbs_grams), NOT the phantom protein_g_target/protein_target_g keys."
  - "current_streak_days reads the real progress['current_streak_days'] (fallback weeks*7), NOT weeks*7 unconditionally."
  - "planned_this_week keeps the canonical type=='workout' count (workout_schedule_read_service.dart:160 writes it) and EXCLUDES travel days (status:'travel')."
proposed_fix: >
  Writer-side (client) edits in `buildAiContext` to read the canonical fields, plus
  the schedule-derived planned count. No Edge Function deploy — the next pushSnapshot
  propagates the corrected fields to the cron read surface. Account-tier; the morning
  alert is fixed by the same change.
regression_test_planned: >
  test/contracts/ai_snapshot_builder_only_test.dart (behavioral, Hive harness +
  buildAiContext): seeds tdee != daily_calories + canonical protein_grams + a real
  current_streak_days that differs from weeks*7, asserts the snapshot sends the
  goal-adjusted calories (1900 not 2400), protein_grams (165 not 0), all four
  daily_targets, and the real streak (4 not 21); + a planned_this_week case (3
  scheduled workout days + 1 rest → planned 3, not the hardcoded 4). All green.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "5 field reads corrected in buildAiContext; flutter analyze clean; snapshot-contract gate green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "behavioral test seeds the canonical Hive shapes + asserts the emitted snapshot fields" }
  - { tier: 6, layer: edge_function_code, status: verified, evidence: "morning-alert:149/157 + protein-gap-alert:140/177 read the corrected fields from the pushed snapshot; protein-gap PRIMARY already used cloud protein_grams; NO EF deploy needed" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "client builds snapshot → pushSnapshot → user_daily_snapshots → crons read corrected values" }
impact_analysis: >
  Account-tier (ai_coach), client-side only — NO Edge Function deploy (propagates via
  pushSnapshot). The two P0s mean the coach reasoned from a wrong calorie goal + a zero
  protein goal on every chat turn; both fixed. The morning-alert cron's calorie + streak
  copy is fixed by the same change. protein-gap-alert was already correct (cloud primary).
  No migration, no schema change. The 7faa3b alias block (which INTRODUCED the tdee +
  phantom-protein + weeks*7 reads as cron aliases) is corrected in place — the cron
  contract is preserved (same keys, right values).
---

# AI snapshot target/streak/plan field drift (f3c8d1)

## What happened
The 7faa3b "top-level alias block" (added 2026-05-17 to feed cron readers) wired the
aliases to the WRONG sources: `daily_calorie_target`→`tdee`, `daily_targets.protein`→
phantom keys, `current_streak_days`→`weeks*7`. Plus `planned_this_week` counted a
`type=='workout'` row no writer emits. So the AI coach (and the morning-alert cron)
reasoned from a wrong calorie goal, a 0 g protein goal, and an approximate streak —
on every turn. The founder directed a full AI-chat investigation ("investigate first,
then fix all, no defer, use discipline").

## Fix
Writer-side reads corrected to the canonical fields (BmrCalculator.toMap emit set +
the real `current_streak_days`), carbs/fat added to `daily_targets`, and
`planned_this_week` keeps its (correct) type=='workout' count but now EXCLUDES travel
days. Client-only; no EF deploy — the next `pushSnapshot` propagates the fix.

## Notes — an audit error the gates caught
The round-1 Opus field audit claimed `planned_this_week` "counted a type=='workout'
row no writer emits → always 0." That was WRONG: `workout_schedule_read_service.dart:160`
(via `upsertScheduled`) stamps `type:'workout'` on every scheduled workout day (the
PUSH/PULL split lives in `workout_name`). A first attempt rewrote the reader to scan
`schedule_*` keys by `type != rest/off` — which (a) deviated from the established
writer/reader contract (`hive_key_contracts_test`: writer + reader both use
`type=='workout'`) and (b) introduced a new `schedule_` prefix read that the
reader-manifest gate flagged as unregistered. Both gates failed the commit; the fix was
reverted to the canonical `type=='workout'` count + a `status!='travel'` exclusion.
Lesson (reinforces `feedback_audit_findings_require_live_verification`): verify a
subagent's STRUCTURAL "no writer emits X" claim against the writer before acting.

## See also
- lib/features/ai_coach/services/ai_snapshot_builder.dart (buildAiContext — the 5 reads)
- lib/core/utils/bmr_calculator.dart (toMap — the canonical target field names)
- supabase/functions/morning-alert/index.ts:149,157 (cron readers — fixed by the same change)
- docs/diagnoses/2026-05-17-orphan-reader-aliases-7faa3b.md (the alias block this corrects)
- test/contracts/ai_snapshot_builder_only_test.dart (behavioral pins)
