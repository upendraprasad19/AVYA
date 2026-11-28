---
bug_id: 81a2dd
date: 2026-11-28
batch: hand-pick-any-exercise (founder rule change)
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  Founder, 2026-11-28: "A user should be able to add any exercise as he feels fit. As he is adding
  it so he must be able to do it." The app did the opposite in five places: the swap sheet, the
  mid-workout "+ Add Exercise" list, the template builder search and the coach's swap list hid every
  exercise the user's listed equipment could not do, and the swap write refused it
  (equipment_unavailable). A second gap came with removing that refusal: the injury planner, the one
  caller where the APP picks the replacement, had no equipment check of its own and relied on the
  write to refuse. And it dropped an affected exercise with no substitute without saying so, so the
  preview could read "No exercises in the next 7 days hit this body part".
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay: writes the schedule row, equipment refusal removed", line: 723 }
  - { file: lib/features/ai_coach/services/injury_swap_planner.dart, method_or_widget: "_findSubstitute: now filters by equipment; plan() returns InjuryPlan with unplaced", line: 260 }
readers:
  - { file: lib/shared/repositories/picker_rows.dart, method_or_widget: "PickerRows.arrange: the four hand-pick lists, ordered, nothing hidden", line: 56 }
  - { file: lib/features/ai_coach/widgets/diff_preview/injury_modify_diff.dart, method_or_widget: "the preview names every unplaced exercise", line: 96 }
  - { file: lib/features/ai_coach/widgets/tool_confirm_card.dart, method_or_widget: "executedMessageFor: No workouts changed for an empty swap list", line: 487 }
hive_key_prefix: none
hive_key_formula: "unchanged: schedule_<date>, exerciseBox[<id>], customBox['custom_exercise_<n>']"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/picker_rows_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: the same user-scoped boxes are read and written as before."
forbidden_patterns_checked:
  - { pattern: "canPerform( or canOfferInPicker( in any of the four hand-pick list files", absent: true }
  - { pattern: "equipment_unavailable anywhere under lib/", absent: true }
proposed_fix: |
  Hand-pick lists are ORDERED by equipment, never filtered: one pure helper, PickerRows.arrange,
  puts the rows the equipment covers first and lists a name once (the user's own row wins, then a
  built-in, then a community row). The swap write loses its equipment refusal. The injury planner
  filters its own candidates with the same predicate on the row the write would use
  (SwapService.ownCustomRow) and returns what it could not place; the preview names it, and a
  confirm that changed no workout says "No workouts changed".
  Plans the app builds still filter by equipment. Duplicate names stay refused.
regression_test_planned: |
  test/contracts/picker_rows_behavioral_test.dart (the arrangement);
  test/contracts/coach_swap_picker_equipment_behavioral_test.dart,
  test/widgets/swap_sheet_any_equipment_test.dart,
  test/features/train/template_builder_unique_names_test.dart and
  test/features/train/exercise_name_unique_screen_test.dart (one widget proof per list);
  test/contracts/exercise_name_unique_in_day_behavioral_test.dart (the write, and the planner);
  test/ai_coach/injury_modify_diff_adds_line_test.dart and
  test/ai_coach/tool_confirm_sheet_injury_line_test.dart (what the user is told).
mutation_proof: |
  Mutate, run, restore; every file restored byte for byte. PickerRows: 7 mutations, 7 RED. The four
  lists: 11 mutations, 11 RED (each list with its non-matching rows dropped and with unarranged
  rows; the picker chip ignoring a replaced row's category; the swap sheet chip applied to own
  exercises; the template search capped at 30 again). Swap write and injury planner: 9 mutations,
  9 RED (the planner's equipment skip; its own-row lookup; the old refusal restored; each unplaced
  entry dropped; "Workouts updated" for no swap; the sheet's no-swap announcement; the preview
  block hidden; "nothing hits" said with exercises unplaced). The name guard: the old community
  skip restored, 3 RED.
impact_analysis: |
  A user can now pick any exercise by hand, in four lists and through the coach after APPLY. With
  the equipment rule off or no profile the order is the old one. App-made paths (generator, repeat
  pins, warm-up, finisher, injury planner) still filter. When the app repeats a phase it still
  re-checks equipment, so a hand-added exercise outside the listed equipment can drop out of that
  app-made repeat (founder told 2026-11-28). If a user narrows their equipment between the injury
  preview and Confirm, the cached swaps run unchecked; reopening the preview recomputes them.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Four list readers, the swap write, the injury planner, the preview and the confirm message; the tests above." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Planner and swap tests read the written schedule row back from real Hive." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The coach swap tool and its payload are unchanged; the client now accepts a swap it used to refuse, after the same confirm card." }
recurrence: |
  Not a recurrence of a defect: a founder rule change that reverses the hand-pick half of b6f4d1,
  plus one older planner gap (noted on OI-403 on 2026-11-28).
related_bugs: [b6f4d1, e7b2d4, a6f3d9, f2a6c8, e7c4a1]
---

# 81a2dd - A user could not hand-pick an exercise their listed equipment did not cover

## What changed

`b6f4d1` (OI-89) added the block after a bodyweight user was offered Barbell Back Squat. The harm it
named is now answered by ORDER (the user's equipment first), not by hiding: the founder's rule is
that whoever adds an exercise themselves is able to do it.

## The two halves

- A user picks by hand (four lists, and a coach swap once they tap APPLY): any exercise.
- The app picks (plan generator, repeat pins, warm-up, finisher, injury planner): equipment still
  filters. The injury planner had no filter of its own, so it got one here.

## The planner's silent drop

`plan()` returned only the swaps, so an affected exercise with no substitute vanished and the
preview could say nothing hit the body part. The new filter makes that likely (a bodyweight
shoulder plan has very few `push` substitutes), so `plan()` now returns the unplaced ones too.
