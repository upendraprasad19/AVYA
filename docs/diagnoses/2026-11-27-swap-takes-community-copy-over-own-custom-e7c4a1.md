---
bug_id: e7c4a1
date: 2026-11-27
batch: oi348-walk-rest (found by the B-pass on PR 349)
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  Swapping to your own custom exercise can be refused with "needs equipment you have not told us
  you have" when an approved community copy of it is on the phone. The community pull stores an
  approved row under its cloud id, which for its author is the id of the author's own custom.
  `swapExerciseInDay` looked in the exercise box by id first, so it took the community copy and
  judged it by the library rule (an empty or unreadable equipment list is refused), while the
  pickers offered the user's own custom. On main before this batch. Found by reading the code;
  the batch's earlier live count (2026-11-26) showed no approved community row, so no user is
  known to have hit it.
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - { file: lib/core/services/sync/sync_community.dart, method_or_widget: "the community pull into exerciseBox (rows marked source: community)", line: 524 }
readers:
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay: which row the target id resolves to", line: 683 }
  - { file: lib/features/ai_coach/services/injury_swap_planner.dart, method_or_widget: "_resolveLibraryEntry: whose muscles are judged", line: 206 }
hive_key_prefix: none
hive_key_formula: "unchanged: exerciseBox[<id>] and customBox['custom_exercise_<n>'] with field id"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/exercise_name_unique_in_day_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: both boxes are read as before."
forbidden_patterns_checked:
  - { pattern: "a community exerciseBox row chosen while the user's own custom has the same id (swap_service.dart)", absent: true }
proposed_fix: |
  When the exercise-box hit is not a library row (isLibraryRow is false), also look in the user's
  own customs; a custom with that id or name wins. A library row is never replaced.
regression_test_planned: |
  test/contracts/exercise_name_unique_in_day_behavioral_test.dart, the group about an own custom
  beside its approved community copy: the swap succeeds; with no own custom the community row is
  still refused; an own custom naming equipment the user lacks is still refused; a library row
  wins over a custom with the same id.
mutation_proof: |
  Mutate/run/restore, restore verified by hash. The lookup limited to a missing row again: 1 RED.
  The lookup run for library rows too: 1 RED.
impact_analysis: |
  One resolution step of one writer. A target that is a library row, or that exists in only one
  box, resolves as before.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "swapExerciseInDay target resolution; the four tests above." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The tests read the written schedule row back from real Hive." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "A local write only changes which local row is copied into the plan." }
recurrence: "Same family as a5d29c (a picker and a writer resolving customs differently)."
related_bugs: [a6f3d9, a5d29c]
---

# e7c4a1 - The swap took the community copy over the user's own exercise

## What happened
One id can name two local rows: the community copy and the author's own exercise. The pickers show
the author's own one; the swap read the community one and applied the stricter library rule to it.

## Fix
Prefer the user's own exercise over a community copy, never over a library exercise.

## Second review (2026-11-28): the injury planner had the same order

`InjurySwapPlanner._resolveLibraryEntry` reads the planned exercise's muscles, and it also took
the community row first. The author can edit a custom's muscles, and the pull never updates an
existing community row, so the planner could judge old muscles. It now applies the same rule.
The other id lookups that take the exercise box first (the confirm card, the swap preview,
`log_set` name resolution and the coach's duplicate check) read only the name, and a custom's
name cannot be edited, so they give the same answer either way.

Tests: the planner group about an own custom beside its community copy (own muscles judged; a
stale community muscle forces no swap; with no own custom the community muscles are judged).
Mutations: the community row preferred again, 2 RED; the community row lost with no own custom,
1 RED.

## Third review (2026-11-28): the substitute half of the planner

The second pass changed only how the planner reads the exercise being replaced.
`_findSubstitute` still judged each candidate from the exercise box, so a stale community copy
could offer the author's own custom into an injury plan, judged on old muscles, and the swap
then wrote the own row. The same code is on main. A community candidate is now resolved through
`_resolveLibraryEntry` before its category, muscles and name are read; a library row is read as
it is.

Tests: the planner group about a substitute that is a copy of an own custom (a now-injuring own
custom is not offered; a safe one still is; with no own custom the community muscles decide; the
own category is matched). Mutation: the candidate judged from the exercise box again, 3 RED.

