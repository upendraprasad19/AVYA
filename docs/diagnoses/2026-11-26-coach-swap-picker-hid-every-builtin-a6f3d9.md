---
bug_id: a6f3d9
date: 2026-11-26
batch: oi348-walk-rest (found while checking which pickers can show a community exercise)
status: fixed
tier: m_fix
blast_radius: account
symptom: |
  AI coach, Swap quick action: the "REPLACE WITH" list offers only the user's own custom
  exercises. Every built-in exercise is missing for every user who has a profile, whatever their
  equipment; with no customs it reads "No substitutes available with your current equipment."
  It also listed an own custom whose equipment the user does not have, which the swap itself then
  refuses. `_substitutesFor` passed `equipment_needed?.toString()` to the equipment rule: the
  library stores a LIST, so the rule received the text "[dumbbells]", could not read it, and
  failed closed. Found by reading the code and reproduced in a test before the fix. No user
  report. In the code since the sheet was added (commit 5900b467, 2026-09-18).
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - { file: assets/data/exercise_library.json, method_or_widget: "equipment_needed, a List<String> on all 870 rows (SeedService puts it into exerciseBox as it is)", line: 1 }
readers:
  - { file: lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart, method_or_widget: "_substitutesFor", line: 134 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay: the same rule on the raw value (the reader the sheet's comment says it mirrors)", line: 738 }
hive_key_prefix: none
hive_key_formula: "not applicable: a read-side filter"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/coach_swap_picker_equipment_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: no write."
forbidden_patterns_checked:
  - { pattern: "an equipment_needed value turned into text before the equipment rule (lib/)", absent: true }
proposed_fix: |
  Pass `m['equipment_needed']` as it is. The old `equipment != null` guard goes too, so a row
  with no equipment field is judged like everywhere else: a built-in row is hidden (the swap
  refuses it), an own custom is offered.
regression_test_planned: |
  test/contracts/coach_swap_picker_equipment_behavioral_test.dart: the real sheet over real Hive
  with a profile and the library's list shape. Full gym: the built-in bodyweight, dumbbell and
  barbell rows are offered, a row with an empty list and a row with no field are not. Bodyweight:
  only the bodyweight row and the own custom with no listed equipment; the barbell rows, built-in
  and own, are not. Both failed on the old line.
mutation_proof: |
  See "Mutation results" below.
impact_analysis: |
  One widget's list. The swap writer already applied the rule to the raw value, so nothing newly
  offered is refused by it. Without a profile the rule is off and the list is unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "_substitutesFor; both new tests red before the fix and green after it." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The test seeds exerciseBox, customBox and the profile and reads the sheet; nothing is written by the filter." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function reads this list." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The swap_exercise intent the sheet submits is unchanged." }
recurrence: "Same field-shape class as e9d1c7 (equipment_needed read with the wrong type, there a crash) and same filter as e7b2d4 (a fail-closed equipment check hiding rows from a picker). Not a repeat of either line of code."
related_bugs: [e9d1c7, e7b2d4]
---

# a6f3d9 - The coach's Swap list hid every built-in exercise

## What happened
The list of substitutes turned each exercise's equipment list into one piece of text before asking
whether the user can do it. The rule cannot read that text and says no when it cannot read. The
two earlier tests of this sheet did not see it: one seeded the equipment as plain text with no
profile, the other seeded no profile, and with no profile the rule is off.

## Fix
Give the rule the list as the library stores it.

## Mutation results
Rule 21, mutate/run/restore from a saved byte copy (restore verified by bytes). Each of these
turned both tests red: the value turned into text again; built-in rows treated as the user's own
(`isCustom: true`); the old "skip a missing field" guard put back.

## Code review (B-pass, 2026-11-27): the full list needs a search

With the built-in rows back, a full-gym user is offered several hundred exercises, and the sheet
had no search. It now has one, folding text like the other exercise searches (`exerciseDuplicateKey`,
name and older names). Typing clears the selection, so SWAP never acts on a hidden row; BACK clears
the search. Mutations, 1 RED each: the selection kept while typing; older names not searched; BACK
keeping the search.
