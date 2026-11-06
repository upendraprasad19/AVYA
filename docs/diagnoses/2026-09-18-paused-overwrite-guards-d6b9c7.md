---
bug_id: d6b9c7
date: 2026-09-18
batch: Task 3 (C3) — ai-coach-ux-tool-integrity spec 2026-09-18
status: fixed
blast_radius: account
symptom: |
  Tool-integrity audit (2026-09-18, spec
  docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md, item C3)
  found that all three AI-coach overwrite tools guard only against 'completed'
  and therefore silently un-pause a PAUSED day: a pause is a deliberate user
  state (C1, diagnose c1a9d4 — 'paused' is invisible to the streak walk), and
  overwriting its schedule row with a fresh status:'planned' entry destroys
  the pause without telling the user.
    1. generateHotelWorkout — the planner queues paused days for write
       (hotel_workout_planner.dart filters only 'completed'); the dispatcher's
       concurrent-edit guard (tool_dispatcher.dart, _executeGenerateHotelWorkout)
       skipped only 'completed'.
    2. regeneratePlanBlock — same planner shape
       (RegeneratePlanPlanner filters only 'completed'); the dispatcher guard
       (_executeRegeneratePlanBlock) skipped only 'completed'.
    3. scheduleTemplate — TemplateService.assignTemplateToDate rejected
       'completed' only; a paused day was overwritten with a status:'planned'
       custom_template entry. The dispatcher's _executeScheduleTemplate also
       DISCARDED the AssignTemplateResult, so even a rejected assign was
       counted as scheduled.
concept: schedule_terminal_rows
sot_registry_entry: streaks (paused/moved/dropped terminal-row family)
writers:
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeGenerateHotelWorkout concurrent-edit guard, line: 839 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeRegeneratePlanBlock concurrent-edit guard, line: 971 }
  - { file: lib/core/services/template_service.dart, method_or_widget: assignTemplateToDate paused branch, line: 113 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeScheduleTemplate alreadyPaused rejection mapping, line: 1428 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository._calculateStreak (C1 skip arm — the paused row must keep reading as invisible, i.e. the row must SURVIVE), line: 372 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: getScheduleForDate display read (returns null for invisible statuses — the pause must persist in the raw row), line: 900 }
hive_key_prefix: schedule_
hive_key_formula: schedule_${istDateStr(date)} keeps status 'paused' + paused_via/paused_at/pause_reason — untouched by all three commit paths post-fix
sync_methods: []
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: []
contract_test_path: test/contracts/coach_regen_phase_stamp_behavioral_test.dart
ist_handling:
  - "No new date arithmetic — the guards compare an existing row's status field; test date keys use the harness's existing istDateStr/dateKey helpers."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - template_assign_rejected_paused
cross_account_guard: "No new writes — every fix is a SKIP (guard) or a rejection return; the existing upsertScheduled/WriteService routing of the surviving paths is unchanged and keeps its wrapUserScopedBox guard."
forbidden_patterns_checked:
  - { pattern: "over-protection: 'moved'/'dropped' terminal rows are NOT skipped by these guards — a hotel/regen/template overwrite landing on a moved/dropped date writes a deliberate fresh planned row (user asked for new workouts there); skipping only paused+completed is the scoped fix", absent: false }
  - { pattern: "silent skip without user feedback in scheduleTemplate: the dispatcher maps the service's alreadyPaused rejection to an explicit user-facing error instead of counting the day as scheduled", absent: false }
proposed_fix: |
  1. Hotel + regen concurrent-edit guards (tool_dispatcher.dart): extend both
     guards from `st == 'completed'` to
     `st == 'completed' || st == 'paused'` with a `// C3 —` note (symmetric
     with completed: the paused row must survive).
  2. template_service.dart: add `alreadyPaused` to
     AssignTemplateRejectionReason; after the alreadyCompleted branch add an
     alreadyPaused branch — ErrorTelemetry.logEvent('template_assign_rejected_paused', ...)
     + return AssignTemplateRejected(AssignTemplateRejectionReason.alreadyPaused).
  3. tool_dispatcher.dart _executeScheduleTemplate: capture the
     AssignTemplateResult from assignTemplateToDate and map alreadyPaused to a
     user-facing failure ('That day is paused — lift the pause first or pick
     another day.') instead of counting the day as scheduled.
regression_test_planned:
  - test/contracts/coach_regen_phase_stamp_behavioral_test.dart
  - test/contracts/oi189_plan_end_bound_behavioral_test.dart
  - test/contracts/template_scheduling_behavioral_test.dart
impact_analysis: |
  Skip-path change only — no write shape changes, no new writers. The paused
  row survives all three commit paths, so every existing paused-row reader
  (streak walk C1 skip arm, Train screen pause banner, calendar) keeps seeing
  the same row it saw before the tool fired. The dispatcher's
  _executeScheduleTemplate now consumes the AssignTemplateResult it previously
  discarded; non-paused rejections (alreadyCompleted, templateMissing) keep
  their pre-fix behavior (counted as scheduled — the dispatcher's own
  completed guard makes alreadyCompleted near-unreachable there; the
  templateMissing under-count is a pre-existing, out-of-scope defect noted for
  a future batch). The displaced-backup branch in assignTemplateToDate sits
  AFTER the new paused return, so a rejected paused assign writes no
  displaced_ shadow either (pinned by the template test).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "tool_dispatcher.dart (hotel guard, regen guard, _executeScheduleTemplate mapping) + template_service.dart (enum value + paused branch + telemetry); flutter analyze on the touched files: zero warnings." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "All three behavioral tests seed real schedule_<date> rows in the real workoutBox and assert the paused row survives (status/workout_name/paused_via unchanged) while the tool reports the date skipped; pre-fix all three reddened with the overwrite reported as success." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No schema change — schedule status is a free-form Hive field; no migration." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "No cloud-path change: the surviving writes keep routing through WorkoutWriteService.upsertScheduled exactly as before; the paused row itself is untouched by all three paths post-fix (its pre-existing cloud fan-out is unaffected). pause_range_routes_through_write_service_test.dart stays green." }
mutation_proven:
  mutated: "Removed ONLY the `|| existing['status'] == 'paused'` arm from the hotel guard (verified applied: grep count of 'paused' in tool_dispatcher.dart dropped 11 -> 10) — compiles clean, semantically wrong (the exact pre-fix defect)"
  result: "hotel: a paused day survives the commit overwrite (C3) reddened — the paused date appeared in the tool's schedules results (reported as scheduled) where the test asserts empty. The regen guard and template branch are symmetric one-line extensions of the same predicate; the hotel mutation demonstrates the shared mechanism. Reverted, all green (+3)."
  confirmed_applied: "failure observed in the run output (00:01 +2 -1 ... [E], an assertion failure — not a compile error, not a zero-red run)"
---

## Summary

The 2026-09-18 tool-integrity audit (spec item C3) found that all three
AI-coach overwrite tools — generateHotelWorkout, regeneratePlanBlock, and
scheduleTemplate — protected only against overwriting a COMPLETED day. A
PAUSED day (a deliberate user state since the pause feature; C1/diagnose
`c1a9d4` established that paused rows are invisible to the streak walk) was
silently overwritten with a fresh `status:'planned'` row: the pause vanished
with no user feedback, and the day re-appeared in the streak walk as a live
planned day.

## Root cause

Guard asymmetry, not writer/reader drift: the overwrite paths knew about
'completed' (history is sacred) but not 'paused'. The pause feature writes
`status:'paused'` via `WorkoutScheduleWriteService.pauseRange`
(workout_schedule_write_service.dart:140) but the three commit tools never
consulted that status. Additionally, the dispatcher's `_executeScheduleTemplate`
discarded the `AssignTemplateResult` entirely, so even the service-level
rejection could not reach the user.

## Fix

- **Hotel guard** (`_executeGenerateHotelWorkout`): concurrent-edit guard
  extended to `completed || paused`. The planner only filters 'completed',
  so the dispatcher guard is the last line of defense between preview and
  confirm.
- **Regen guard** (`_executeRegeneratePlanBlock`): same one-line extension,
  symmetric.
- **Template service**: `assignTemplateToDate` gains an `alreadyPaused`
  rejection (new `AssignTemplateRejectionReason.alreadyPaused` value +
  `template_assign_rejected_paused` telemetry) BEFORE the displaced-backup
  branch, so a rejected paused day is neither overwritten nor backed up.
- **Dispatcher mapping**: `_executeScheduleTemplate` now captures the
  assign result and maps `alreadyPaused` to a user-facing error —
  "That day is paused — lift the pause first or pick another day." — instead
  of counting the day as scheduled.

## 'moved'/'dropped' rows are deliberately NOT skipped (scope note)

The overwrite paths can land on a date whose row is 'moved' or 'dropped'
(both terminal per C2, diagnose `e8f4a3`). That overwrite is CORRECT, not a
bug: the user explicitly asked for new workouts on those dates, and a fresh
planned row replacing a terminal placeholder is the requested semantic — a
hotel trip or a regen laying out a block does not need to preserve an
audit placeholder. The streak walk (C1) reads 'moved'/'dropped' as invisible,
so a terminal row replaced by a planned row changes streak semantics only in
the direction the user asked for. Scope stays paused-only per spec; if the
founder wants terminal-row confirmation prompts on those paths, that is a
new decision, not part of C3.

## Verification

- Pre-fix: all three new tests RED (hotel + regen: paused date reported as
  scheduled and row overwritten; template: compile error on the missing
  `alreadyPaused` enum — the not-yet-implemented branch).
- Post-fix: all three files green (39 tests across the three files +
  pause_range_routes_through_write_service_test.dart green).
- Mutation (rule 21): removing only the hotel guard's paused arm reddened the
  hotel test and nothing else; reverted, green. Recorded above.
