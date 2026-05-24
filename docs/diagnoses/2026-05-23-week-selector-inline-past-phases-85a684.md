---
bug_id: 85a684
date: 2026-05-23
batch: APK Test #16.2 +30 obs 5-12 batch — post-mockup additions (commit 15 / Theme K)
status: shipped
symptom: |
  Founder reviewed the Theme H-followup mockup 2026-05-23 and clarified
  the original "scroll back to see completed phases" wish: the desired
  surface is INLINE in the train screen's existing week-selector chip
  strip, NOT a standalone PhaseHistoryScreen (which was reverted in
  commit 7fd602b / Theme L).

  Pre-fix the week-selector at `lib/features/train/widgets/week_selector.dart`
  rendered ONLY the current phase's 4 weeks + 2 PRO-locked future
  phases (PHASE II W5-8, PHASE III W9-12). After Theme H protected
  past `schedule_*` entries from planGenerator overwrite, the past
  data EXISTS in Hive but no UI surface revealed it. Users couldn't
  scroll the chip strip back to PHASE I W1-W4 to review what they
  completed.
concept: week_selector_past_phase_scroll
sot_registry_entry: scheduled_workouts_mutations
writers: []
readers:
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: _loadPastPhases — walks workoutBox toMap() for keys starting `schedule_`, filters date < planStart, buckets by 28-day phases, materialises _PastPhase records, line: 113 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: _PastPhaseGroup + _PastWeekChip render past chips visually distinct (textDim border + ✓ glyph on weeks with ≥1 completed day), line: 223 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: _PastWeekSheet modal bottom sheet — renders 7-day breakdown of past phase week with completed/not-completed/rest day rows, line: 343 }
hive_key_prefix: "schedule_"
hive_key_formula: "schedule_${istDateStr(date)}"
sync_methods: []
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: [date, week, status, completed_at, workout_name, type]
contract_test_path: test/contracts/week_selector_past_phases_test.dart
ist_handling:
  - { file: lib/features/train/widgets/week_selector.dart, line: 130, source: "reads `date` field directly from schedule_* entries (already in IST date-key format per WorkoutWriteService.upsertScheduled at workout_write_service.dart:415). No date math on the read side; comparison + bucketing only." }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: WeekSelector reads via HiveService.instance.workoutBox which wraps via wrapUserScopedBox.
forbidden_patterns_checked:
  - "Reading currentPlanProvider for past weeks (provider only knows current phase; past data lives in schedule_* Hive entries)."
  - "Tapping a past chip mutating selectedWeek (would route current-week renderer to a week with no plan data)."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "week_selector.dart rewritten (167 → 524 lines) with past-phase loader + _PastPhaseGroup + _PastWeekChip + _PastWeekSheet" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "schedule_* key format unchanged; reads existing data protected by Theme H's upsertScheduled completed-day guard (b0baa5)" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/week_selector_past_phases_test.dart — 11 assertions covering HiveService import, schedule_* walk, planStart filter, 28-day bucketing, render order (past LEFT of PHASE I), textDim styling, ✓ glyph, modal sheet, entriesForWeek read, forward-phase preservation, public signature stability" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/train/screen.dart line 235-264 (WeekSelector instantiation — unchanged because public signature preserved)
  callers_updated_in_this_batch:
    - lib/features/train/widgets/week_selector.dart (extended in place)
    - lib/features/train/CLAUDE.md (new pitfall row)
  callers_unchanged:
    - lib/features/train/screens/train/screen.dart (call-site)
    - lib/features/train/screens/train/week_rows.dart (current-week renderer)
    - lib/features/train/providers/preview_plan_provider.dart (forward preview path)
proposed_fix: |
  Single file: `lib/features/train/widgets/week_selector.dart` extended.

  1. Add `import 'package:icanbefitter/core/services/hive_service.dart'`.
  2. New top-level `_loadPastPhases(DateTime? planStart)` helper:
     - Walk `workoutBox.toMap().entries`.
     - Filter keys starting with `schedule_`.
     - Parse each entry's `date` field via `DateTime.tryParse`.
     - Skip entries where `date >= planStart` (those are the active
       phase, not history).
     - Build `_ScheduleEntry` records (key, date, week, type,
       workoutName, status, completedAt).
     - Sort ascending by date.
     - Bucket by phase index = `daysSinceEarliest ~/ 28`.
     - Return sorted list of `_PastPhase` records (phaseNumber=idx+1,
       startDate, endDate, entries).

  3. New `_PastPhaseGroup` widget — header label `PHASE <roman> (DONE)`
     + 4 `_PastWeekChip` chips per phase. Tap callback opens modal
     sheet.

  4. New `_PastWeekChip` widget — visually distinct (textDim border
     instead of accent; smaller header color; ✓ check_circle glyph
     top-right when `past.hasCompletedDayInWeek(w)` is true). 48x58
     dimensions match the existing _WeekChip shape with date sub-line.

  5. New `_PastWeekSheet` modal bottom sheet — header eyebrow `PHASE
     <roman> · WEEK N`, title "Completed history", then 7 _PastDayRow
     entries showing each day's weekday badge + workout name +
     completed/not-completed status + check_circle glyph on
     completed.

  6. _WeekSelectorState.build() — render `pastPhases` LEFT of PHASE I
     in the Row children. Forward phases (PHASE I/II/III) unchanged.

  7. `_phaseRoman(int)` helper for phase 1-12 roman numerals
     (matches the existing PHASE I/II/III label convention).

  8. Public widget signature unchanged — `totalWeeks`, `selectedWeek`,
     `onSelect` all preserved. train/screen.dart call-site at line
     235-264 compiles without change.
regression_test_planned:
  - test/contracts/week_selector_past_phases_test.dart — 11 assertions: HiveService import, schedule_ key walk, date>=planStart skip, 28-day bucketing, past renders LEFT of PHASE I, textDim styling, hasCompletedDayInWeek + check_circle glyph, showModalBottomSheet + _PastWeekSheet, entriesForWeek + status=completed render, PHASE I/II/III preserved, public signature (totalWeeks/selectedWeek/onSelect) stable.
related_bugs:
  - b0baa5  # Theme H — completed-day overwrite guard; without it past schedule_* would be clobbered
  - 7fd602b  # Theme L — revert of the wrong-surface PhaseHistoryScreen; this commit is the correct surface
recurrence: |
  The "build the screen but the user wanted a different surface"
  anti-pattern recurred this batch — first Theme H-followup (commit
  1aa9ed2) shipped a standalone PhaseHistoryScreen at /train/history
  before the founder reviewed the mockup. Reverted in commit 7fd602b
  / Theme L when the founder clarified the desired surface. Mitigation:
  the `/ui-mockup` skill now runs BEFORE the build whenever a new
  surface is introduced; Theme K's design was confirmed via the
  earlier mockup feedback loop.
---
# Body

## Why a modal sheet (not navigate to a new full-screen)

The founder's mental model is "scroll the chip strip, tap a past
chip, see the past week without leaving the train tab". A full-
screen route would break that flow — the user loses context. The
modal bottom sheet:
- Preserves the train tab below.
- Auto-dismisses on swipe-down or back-button.
- Shows enough detail (7 days + completed flags + timestamps) for
  the founder's "scroll and check" wish.

If a future iteration wants per-day exercise lists (the exlog_*
entries that backed each completed day), it lands as an additive
nested route or sheet from inside _PastWeekSheet.

## Why bucket by 28 days (not by phase_number stored on entry)

The plan generator writes `week` field 1-4 PER PHASE — not
cumulatively. So `schedule_*.week` doesn't tell you which phase the
entry belongs to. Only the `date` differentiates. Bucketing by
calendar 28-day chunks starting from the earliest past date is the
canonical way to recover phase boundaries from the persisted data.

This works because phases are ALWAYS 4 weeks (per the plan engine
contract). If a future phase length becomes variable, the loader
would need a different boundary signal (e.g., a `phase_number`
field added to schedule_* writes, defaulting to derivation for
back-compat).

## Why visually distinct chips (not identical to current)

The chip strip's left edge is now "history" surface, right edge is
"current/future" surface. Visual differentiation tells the user at
a glance:
- Current/future chips: accent border, possible PRO lock, taps
  drive the train tab's weekly renderer.
- Past chips: textDim border, ✓ glyph, taps open the modal sheet.

Same shape (48x58 with sub-text), different colors + glyph — the
user's chip-strip muscle memory stays intact while the semantic
difference is clear.

## Mockup loop

This commit's design was implicitly informed by the Theme H-followup
mockup feedback ("inline scroll-back" vs "standalone screen"). No
new mockup was generated for Theme K specifically because the
founder's wording in the v1 mockup review ("scroll the chip strip,
see PHASE I W1-W4 with completed checkmarks") directly mapped to
this implementation. If the v2 mockup loop surfaces a different
preferred layout (e.g. timeline view, calendar grid), this commit
gets revised — the data layer (_loadPastPhases helper) is
surface-agnostic.
