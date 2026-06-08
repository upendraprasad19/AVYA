---
bug_id: a4f7e1
date: 2026-06-08
batch: psych-skill-and-audit-2026-06-07 (recompose server-enum follow-up — ai-proxy deploy)
status: fixed
blast_radius: account
symptom: >
  The AI coach's `regeneratePlanBlock` tool exposed a `goal` z.enum that omitted
  'recompose' (only build_muscle / lose_fat / general_fitness / strength). Its
  sibling `switchGoal` had 'recompose' added during the Hermes E-pass, but the
  parallel tool was missed. So if the model routed a recompose user's request
  ("regenerate my plan for a recomp", "switch focus to recomposition then rebuild
  the block") to regeneratePlanBlock with goal='recompose', zod rejected the tool
  call and the action failed — the same F19 goal-fallthrough class, one tool over.
concept: fitness_goal_resolution
sot_registry_entry: >
  config SoT (FitnessGoals) — the canonical goal tokens. Server AI-coach plan
  tools (switchGoal.newGoal, regeneratePlanBlock.goal) are now pinned to it by
  scripts/check_goal_token_exhaustiveness.dart (Check 4) +
  test/contracts/ai_proxy_goal_enum_parity_test.dart. Not a Hive/cloud
  writer-reader storage concept (see ADR-0015, F19).
writers:
  - "{ file: supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts, method: schema goal z.enum, line: 13 } — adds 'recompose' so the AI can regenerate a recomposition block"
  - "{ file: supabase/functions/_shared/tools/plan/switchGoal.ts, method: schema newGoal z.enum, line: 10 } — already carried 'recompose' (Hermes E-pass); the sibling now matches"
readers:
  - "{ file: lib/features/ai_coach/services/tool_dispatcher.dart, method: _executeRegeneratePlanBlock, line: 666 } — replays the planner's FitnessGoals-resolved schedules; recompose → hypertrophy block (no private goal switch)"
  - "{ file: lib/features/ai_coach/services/tool_dispatcher.dart, method: _executeSwitchGoal, line: 798 } — FitnessGoals.isKnown guard already accepts recompose before persisting primary_goal"
  - "{ file: lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart, method: _humanGoal, line: 241 } — recompose label resolves via FitnessGoals.label, not a hardcoded case"
hive_key_prefix: n/a (goal is not a keyed Hive concept; regeneratePlanBlock writes schedule_* rows, not the goal)
hive_key_formula: n/a
sync_methods: >
  n/a for the goal itself — regeneratePlanBlock writes schedule_* rows
  (syncWorkoutData → scheduled_workouts). Only switchGoal persists the goal
  (primary_goal travels inside the profile map via syncOnboarding).
restore_methods: n/a (the enum is request-shaping; no restored state)
cloud_table: scheduled_workouts
cloud_columns: >
  (goal not persisted by regeneratePlanBlock — it shapes the generated
  schedule rows: workout_name / type / status. switchGoal persists
  user_profile.primary_goal.)
contract_test_path: test/contracts/ai_proxy_goal_enum_parity_test.dart
ist_handling: n/a (no date logic in the goal enum)
provider_invalidations: >
  n/a for this enum widening — switch_goal already refreshes profile readers via
  _invalidateProfileProviders (nutritionTargets / header / MY TARGETS);
  regenerate_plan_block invalidates workout readers after the schedule write.
telemetry_op_types: tool_dispatch_regenerate_plan_block_failed (existing failure breadcrumb; no new op type)
cross_account_guard: >
  user-scoped — tool_dispatcher routes the regenerated schedules through
  WorkoutWriteService (wrapUserScopedBox); an enum value carries no cross-account
  surface.
forbidden_patterns_checked: >
  no goal z.enum in switchGoal.ts or regeneratePlanBlock.ts may OMIT a FitnessGoals
  token or LIST a non-token — enforced by scripts/check_goal_token_exhaustiveness.dart
  Check 4 (server blind spot, newly added) + the parity contract test.
proposed_fix: >
  Add 'recompose' to regeneratePlanBlock's goal z.enum (the client already
  resolves it via FitnessGoals end-to-end — _executeRegeneratePlanBlock replays
  the planner's FitnessGoals-resolved schedules; regenerate_plan_diff._humanGoal
  labels via FitnessGoals.label). Extend check_goal_token_exhaustiveness.dart with
  Check 4 — every FitnessGoals token must appear in BOTH server tool enums and
  neither may list a non-token (the gate previously scanned only client Dart,
  which is exactly how this drifted). Add a Flutter parity contract test pinning
  both server enums to the SoT. Redeploy ai-proxy so the enum ships live.
regression_test_planned: >
  test/contracts/ai_proxy_goal_enum_parity_test.dart (3 cases — FitnessGoals
  tokens sanity incl. recompose; switchGoal newGoal enum == tokens;
  regeneratePlanBlock goal enum == tokens, no missing/no phantom) — GREEN
  (fails pre-fix: tokens.difference(regen enum) = {recompose}). Plus co-located
  Deno cases: switchGoal_test "accepts all 5 valid goals" + regeneratePlanBlock_test
  "accepts recompose goal".
touched_layers_checked:
  - "{ layer: client_code, status: verified, evidence: reader path traced — tool_dispatcher._executeRegeneratePlanBlock (l666) replays FitnessGoals-resolved schedules; _executeSwitchGoal (l798) FitnessGoals.isKnown guard; regenerate_plan_diff._humanGoal (l241) FitnessGoals.label. No private goal switch rejects recompose. dart analyze clean }"
  - "{ layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: regeneratePlanBlock.ts goal enum now lists recompose; ai-proxy redeployed from this committed disk state (v69 -> next) via the byte-identical host-shell flow, boot-verified (verify_jwt=false -> smoke reaches the module) }"
  - "{ layer: client_to_server_contract, status: verified, evidence: scripts/check_goal_token_exhaustiveness.dart Check 4 + test/contracts/ai_proxy_goal_enum_parity_test.dart assert both server enums == FitnessGoals tokens; gate + test GREEN }"
  - "{ layer: postgres_schema, status: not_applicable, evidence: no schema change — request-shaping enum }"
  - "{ layer: postgres_data, status: not_applicable, evidence: no data change — recompose users' primary_goal already 'recompose'; targets/plan recompute on read }"
impact_analysis: >
  Pre-fix the gap was narrow but real: the common regenerate path sends goal=null
  (defaults to the user's profile goal on the client, which already handles
  recompose), so most flows worked. The hard failure was only when the model
  explicitly set goal='recompose' on regeneratePlanBlock — zod rejected it and the
  tool call failed for the one goal the whole F19 batch was about. Post-fix both
  server plan tools accept the full canonical goal set, and the gate's new server
  Check 4 + the parity test make the client/server goal contract self-policing, so
  a goal added to FitnessGoals can never again ship to one tool but not the other.
  No migration; no data backfill.
closes-diagnose: a4f7e1
---

# a4f7e1 — `regeneratePlanBlock` AI tool couldn't accept the `recompose` goal

## What happened
The F19 remediation made `recompose` a first-class fitness goal (canonical
`FitnessGoals` SoT; BmrCalculator / PlanGenerator / display readers all route
through it). The Hermes E-pass then added `recompose` to the **`switchGoal`** AI
tool's `newGoal` enum so the coach could switch a user to it. But `switchGoal`
has a sibling — **`regeneratePlanBlock`** — that exposes its own `goal` z.enum to
the model, and that one was never updated. It still listed only
`build_muscle / lose_fat / general_fitness / strength`.

So if the model chose `regeneratePlanBlock` (rather than `switchGoal`) for a
recomposition request and passed `goal: "recompose"`, the zod schema rejected the
tool call. Same F19 fallthrough class — a recognised goal the surface couldn't
act on — one tool over.

## Root cause
Two goal enums, no shared source of truth on the server side, and a gate with a
**client-only blind spot**. `scripts/check_goal_token_exhaustiveness.dart` (built
for F19) guaranteed *client* exhaustiveness — onboarding cards, BmrCalculator,
PlanGenerator, CardioFinisher — but never looked at the server tool enums. So
when `recompose` landed in `switchGoal.ts` only, nothing flagged the asymmetry.

## Fix
1. **Enum** — add `"recompose"` to `regeneratePlanBlock.ts`'s `goal` z.enum.
   The client already resolves it end-to-end (verified: `_executeRegeneratePlanBlock`
   replays the planner's `FitnessGoals`-resolved schedules; `_humanGoal` labels via
   `FitnessGoals.label`; `_executeSwitchGoal` has a `FitnessGoals.isKnown` guard).
2. **Gate** — extend `check_goal_token_exhaustiveness.dart` with **Check 4**:
   every `FitnessGoals` token must appear in BOTH `switchGoal.ts` and
   `regeneratePlanBlock.ts` enums, and neither may list a non-token. Closes the
   server blind spot.
3. **Test** — new `test/contracts/ai_proxy_goal_enum_parity_test.dart` pins both
   server enums to the SoT (rule 21; fails pre-fix). Co-located Deno cases updated
   (`switchGoal_test` 4→5 goals; `regeneratePlanBlock_test` recompose-accept).
4. **Deploy** — redeploy `ai-proxy` so the enum (and the prior `switchGoal` one)
   ship live.

## Recurrence
Direct sibling of **F19 (f19a7c)** — goal-token fallthrough — and the same broad
class as writer/reader drift across N consumers without a single source of truth.
The gate's new server Check 4 + the parity test make the client↔server goal
contract self-policing. See ADR-0015 (canonical fitness-goal SoT).
