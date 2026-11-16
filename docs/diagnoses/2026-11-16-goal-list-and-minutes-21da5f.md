---
bug_id: 21da5f
date: 2026-11-16
batch: generator-step3b
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 3, Unit 3B (OI-487 rest, OI-488; founder d4 2026-11-08, d69-d73 2026-11-16).
  - Strength (and the hidden Recomposition) could still be chosen as a goal: Edit Profile listed 'Build Strength', the
    coach's switchGoal / regeneratePlanBlock enums listed both, the coach compass form offered every token, the legacy
    chat onboarding offered Strength. Edit Profile showed a stored recompose as "Build Muscle" and saved recompose back.
  - 4 test accounts held strength, 5 held recompose (live read 2026-11-16); nothing moved them to the goals that
    replaced them.
  - 90-minute sessions were offered to every level, though under the 5 / 6 exercise limit a beginner or intermediate
    gets about 52 / 59 minutes from them (OI-488); 8 test accounts below advanced held 90.
concept: legacy_goal_heal
sot_registry_entry: legacy_goal_heal
contract_test_path: test/contracts/legacy_goal_heal_behavioral_test.dart
related_bugs: [a4f7e1, f19a7c, 675d02]
recurrence: |
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses/INDEX.md grepped for "strength", "recompose", "goal token",
  "session_duration" (class fitness_goal_resolution). a4f7e1 (a server goal enum missing recompose) and f19a7c (the
  recomp key mapping to a token no calculator knew) are the same class one step over: a goal list that differs between
  the client SoT and a server enum or a picker. Not a recurrence of either; their guards (gate Check 4, the parity test,
  the dispatcher guard) are what this unit moves to the selectable list, so the class stays covered.
writers:
  - { file: lib/core/services/legacy_goal_healer.dart, method_or_widget: "LegacyGoalHealer.run / legacyGoalHealPatch / legacyGoalPatch", line: 75 }
  - { file: lib/features/profile/services/profile_write_service.dart, method_or_widget: "patchProfileWith (owner re-check, re-read, decide and write under the profile lock)", line: 116 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreFromCloudForUser: the heal on result.succeeded", line: 2031 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "goalFormSeed / _goals / the minutes chips (sessionDurationOptions, sessionDurationForExperience)", line: 55 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "the chat onboarding primary_goal options", line: 90 }
  - { file: supabase/functions/_shared/tools/plan/switchGoal.ts, method_or_widget: "newGoal z.enum (three goals) and its description", line: 5 }
  - { file: supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts, method_or_widget: "goal z.enum (three goals)", line: 8 }
readers:
  - { file: lib/core/constants/fitness_goals.dart, method_or_widget: "selectableTokens / isSelectable / legacyTargets / notOfferedMessage / labels Build, Cut, Maintain", line: 124 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwitchGoal / _executeRegeneratePlanBlock: isSelectable before the cached-plan check", line: 1041 }
  - { file: lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart, method_or_widget: "_compute: refuses a non-selectable goal before reading or planning", line: 50 }
  - { file: lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart, method_or_widget: "_compute: refuses a non-selectable goal before planning", line: 48 }
  - { file: lib/features/ai_coach/widgets/compass_form_sheet.dart, method_or_widget: "switchForm chips: selectableTokens with labels", line: 251 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "minutesForLevel / profileParamMinutes / initialSessionDuration", line: 73 }
  - { file: lib/shared/repositories/plan_engine/training_history_analyzer.dart, method_or_widget: "sessionMinutesFromProfile through minutesForLevel", line: 236 }
  - { file: lib/shared/services/pro_phase_advance.dart, method_or_widget: "sessionDuration param through profileParamMinutes", line: 216 }
  - { file: scripts/goal_token_exhaustiveness_lib.dart, method_or_widget: "serverGoalEnumProblems (gate Check 4: tokens minus the legacy set)", line: 74 }
hive_key_prefix: "userBox['profile']['primary_goal' | 'physique_focus' | 'session_duration_minutes' | 'fitness_experience']; configBox['disable_legacy_goal_heal']"
hive_key_formula: "HiveService.instance.userBox.get('profile')[...]; configBox.get('disable_legacy_goal_heal') == true"
sync_methods:
  - "ProfileWriteService.patchProfileWith fires the normal syncProfileNow push (sync_profile.dart _syncUserProfile), outside the lock"
restore_methods:
  - "_restoreUserProfile merges cloud non-null wins (a legacy value can come back); LegacyGoalHealer runs after every succeeded restoreFromCloudForUser"
cloud_table: user_profile
cloud_columns:
  - primary_goal
  - physique_focus
  - session_duration_minutes
  - daily_calories
  - protein_grams
  - fat_grams
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched; updated_at is the UTC instant patchProfile already stamps", line: 1 }
provider_invalidations:
  - "none new: the heal runs inside restoreFromCloudForUser before the background heal bumps restoreCompletedTick (HiveTabScaffoldMixin: Home invalidates userProfileProvider, Nutrition macroTargetsProvider)"
telemetry_op_types:
  success: ["legacy_goal_healed (logEvent: '<old>-><new> focus_set|focus_kept')"]
  failure: ["legacy_goal_heal (recordNonFatal)", "profile_write_service_patch_profile_with (recordNonFatal)"]
cross_account_guard: "the healer and patchProfileWith check the wrapper's uid against _liveUserId and HiveUserSession.currentOwnerFullId, the second time under the profile lock BEFORE the box is touched (the box throws a StateError on disagreement)"
forbidden_patterns_checked:
  - { pattern: "a picker or coach tool offering strength / recompose (goal_list_selectable_test presence pins, parity test, gate Check 4)", absent: true }
  - { pattern: "userBox.put('profile' outside ProfileWriteService (check_profile_write_service_only.dart)", absent: true }
  - { pattern: "a raw session_duration_minutes cast passed as a generateV4 param (session_minutes_by_level_test presence pin)", absent: true }
  - { pattern: "plan_generator.dart or the engine's goal paths changed", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-16-generator-step3b-goal-list.md (4 review rounds, converged).
  - FitnessGoals.selectableTokens / isSelectable / legacyTargets / notOfferedMessage; labels Build / Cut / Maintain (d73).
  - Every picker and goal check on the selectable list: Edit Profile, the compass form, the chat onboarding, the
    dispatcher (before the cache check), both coach previews (before planning), the server enums (gate Check 4 moved into
    the lib as serverGoalEnumProblems).
  - LegacyGoalHealer after every succeeded restore: strength -> Build (+ the Strength focus when Balanced / empty, d71),
    recompose -> Cut (d72), the new targets in the same patchProfileWith write; Edit Profile opens an unhealed profile
    healed (goalFormSeed) with the RAW originals.
  - OI-488: SessionBudget.minutesForLevel on every reader of the stored minutes; Edit Profile offers 90 to an advanced
    in-form level only and moves 90 to 60 when the level drops.
regression_test_planned: |
  test/contracts/legacy_goal_heal_behavioral_test.dart; test/contracts/goal_list_selectable_test.dart;
  test/contracts/session_minutes_by_level_test.dart; test/scripts/goal_token_exhaustiveness_lib_test.dart (Check 4);
  test/contracts/ai_proxy_goal_enum_parity_test.dart; test/plan_engine_v4/session_minutes_resolution_test.dart; the Deno
  tool tests switchGoal_test.ts / regeneratePlanBlock_test.ts.
impact_analysis: |
  Account tier (the stored profile) plus platform (session_budget / training_history_analyzer, the minutes every
  generation reads) plus the ai-proxy tools (a deploy with its own go, t306). Pre-launch, test accounts only: 4 strength
  and 5 recompose profiles move at their next launch (calories become Build's / Cut's, d71 / d72; the plan follows at
  its next regeneration); 8 profiles below advanced at 90 plan at 60 from the next generation. The engine and its golden
  are unchanged (the legacy rows remain for stored values; their deletion is OI-515).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "fitness_goals, legacy_goal_healer, profile_write_service, sync_service, edit_profile_screen, tool_dispatcher, both diff previews, compass_form_sheet, onboarding_provider, perform_sign_out, session_budget, training_history_analyzer, pro_phase_advance, simulation_service; flutter analyze clean" }
  - { layer: hive_local_state, status: verified, evidence: "legacy_goal_heal_behavioral_test on real Hive: one write of goal, focus, targets (carb_grams included); owner and race cases write nothing" }
  - { layer: postgres_data, status: verified, evidence: "read-only 2026-11-16: user_profile 4 strength (3 balanced, 1 glutes_legs), 5 recompose, 8 at 90 minutes below advanced" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, CHECK or migration; primary_goal and physique_focus are plain text" }
  - { layer: edge_function_deploy, status: fixed_in_this_batch, evidence: "switchGoal.ts / regeneratePlanBlock.ts enums; Deno tests 29 passed; deno check ai-proxy clean; the deploy waits for the founder's go (t306)" }
  - { layer: client_server_contract, status: verified, evidence: "the healed values reach the cloud through the normal profile push; the client refuses a legacy goal the live coach may still propose until the deploy" }
---

## Root cause

- **Writers:** the goal list was not one list. `FitnessGoals.tokens` (five rows) fed the coach enums (gate Check 4 and
  the parity test required enum == tokens), the compass form and the dispatcher guards (`isKnown`); Edit Profile had its
  own four-entry map with Strength; the chat onboarding its own four options. The onboarding cards alone had three.
- **Readers:** every reader through `FitnessGoals.of` serves strength / recompose as real goals (the engine's strength
  split, recompose's calories), so a stored legacy value never moved.
- **Minutes:** `sessionMinutesFromProfile` returned the stored value raw and `resolveMinutes` has no level; two callers
  forward the stored value as the `param`, which wins.

## Fix

See `proposed_fix` and the plan. Execution mode: inline. `plan_generator.dart` is not touched.

## Found by CI

The first PR run failed `test/contracts/blast_radius_sync_engine_platform_test.dart`: the sync engine reaches the new
healer (called from `restoreFromCloudForUser`) and, through it, `fitness_goals.dart`, both below platform. Both now
take exact platform rules in `docs/blast_radius.yaml` and join the test's `_engine` list (the heal decides what the
profile push sends; `FitnessGoals.legacyTargets` is its table). The plan's round 4 had said the services catch-all
covered the healer.

## Accepted consequences

- d71 / d72: a healed account's calories become Build's (full surplus) or Cut's (full deficit), at the heal, in the
  same write as the goal.
- The heal does not regenerate the plan: the schedule keeps its rows until the next regeneration.
- A failed profile push leaves the cloud on the legacy value; the next `/restoring` restore merges it back (and
  recomputes the legacy targets) and the heal moves it again. Lightweight restores merge without healing.
- A stored 90 below advanced stays stored until the user's next Edit Profile save (no silent write); every generation
  plans it as 60 meanwhile.
- The legacy rows, the engine's strength paths and the dead `_mapGoal` arms stay until no older build is in use
  (OI-515).

## Mutations

Each mutation applied (`count == 1` asserted by the driver before writing), the named test files run, then restored
from a byte backup. Runner: `scratchpad/3b_mut/run.py`. Tests: H = `legacy_goal_heal_behavioral_test`, G =
`goal_list_selectable_test`, M = `session_minutes_by_level_test`, R = `session_minutes_resolution_test`, L = the gate
lib test, P = the enum parity test.

| # | Mutation | Tests run | Red |
|---|---|---|---|
| M1 | the d71 focus rule overwrites a chosen focus (`unset = true`) | H, G | 2 |
| M2 | recompose -> build_muscle in `legacyTargets` | H, G | 6 |
| M3 | the owner re-check inside `patchProfileWith` removed | H | 1 |
| M4 | the targets left out of the heal patch | H | 3 |
| M5 | the call site moved behind `shouldHealAfterRestore` | H | 1 |
| M6 | `minutesForLevel` keyed `!= 'beginner'` | M, R | 5 |
| M7 | the 90-chip condition inverted | M | 1 |
| M8 | `pro_phase_advance` back to the raw `as num?` cast | M | 1 |
| M9 | Check 4 compares with every token again | L | 4 |
| M10 | `_executeSwitchGoal` back to `isKnown` | G, P | 2 |
| M10b | `_executeRegeneratePlanBlock` back to `isKnown` | G, P | 2 |
| M11 | the compass chips back to `FitnessGoals.tokens` | G | 1 |
| M12a | `SwitchGoalDiff`'s refusal removed | G | 1 |
| M12b | `RegeneratePlanDiff`'s refusal removed | G | 1 |
| M13 | Edit Profile seeds the raw goal | G | 2 |
| M14 | the experience-change reset removed | M | 1 |
| M15 | the heal decides on a snapshot read BEFORE the lock | H | 1 (0 on the first race test: Hive updates its in-memory value synchronously, so a save that already held the lock was visible to the early read; the test now queues the save behind a first writer, the only real window) |
| M16 | `sessionMinutesFromProfile` back to the raw value | M, R | 2 |

