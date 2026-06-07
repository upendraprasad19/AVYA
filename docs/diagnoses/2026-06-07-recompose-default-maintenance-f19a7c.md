---
bug_id: f19a7c
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 1)
status: fixed
blast_radius: account
symptom: >
  The default onboarding goal "Recompose" emitted key 'recomp', which
  plan_screen._mapGoal translated to the token 'recompose' — a value no
  calculator recognised. BmrCalculator's goal switch fell to `default`
  (maintenance calories + 1.6 g/kg protein, the lowest), and the plan engine
  fell to the fat-loss split. Every user who tapped through the pre-selected
  default got the OPPOSITE of a recomposition.
concept: fitness_goal_resolution
sot_registry_entry: "config SoT (FitnessGoals) — contract pinned by scripts/check_goal_token_exhaustiveness.dart + test/contracts/recompose_goal_targets_test.dart, not a Hive/cloud storage writer-reader concept (see ADR-0014)"
writers:
  - "{ file: lib/features/onboarding/screens/plan_screen.dart, method: _mapGoal, line: 662 } — onboarding goal key → canonical primary_goal token"
readers:
  - "{ file: lib/core/utils/bmr_calculator.dart, method: calculateTargets, line: 141 } — calorie/protein/fat targets via FitnessGoals.of(goal)"
  - "{ file: lib/shared/repositories/plan_engine/plan_generator.dart, method: generateV4, line: 61 } — split+exercise via FitnessGoals.planGoal; cardio via FitnessGoals.of(goal).cardio"
hive_key_prefix: n/a (primary_goal is a field on the userBox['profile'] map, not a keyed concept)
hive_key_formula: n/a
sync_methods: syncOnboarding (primary_goal travels inside the profile map)
restore_methods: _restoreUserProfile (primary_goal within the restored profile map)
cloud_table: user_profile
cloud_columns: primary_goal
contract_test_path: test/contracts/recompose_goal_targets_test.dart
ist_handling: n/a (no date logic in goal resolution)
provider_invalidations: nutritionTargetsProvider, dietPlanProvider (recomputed on goal change via ProfileWriteService / onboarding completion)
telemetry_op_types: n/a
cross_account_guard: user-scoped — primary_goal lives in userBox['profile'] accessed via wrapUserScopedBox
forbidden_patterns_checked: >
  no raw `case 'build_muscle'` goal switch in bmr_calculator.dart; no hardcoded
  `goal == 'lose_fat'` cardio gate in plan_generator/cardio_finisher — enforced
  by scripts/check_goal_token_exhaustiveness.dart.
proposed_fix: >
  Introduce a canonical FitnessGoals source-of-truth
  (lib/core/constants/fitness_goals.dart): one map per token of
  {label, deltaMult, proteinPerKg, fatPercentage, planGoal, cardio}. BmrCalculator
  computes dailyCalories = tdee + deltaMult × paceDelta (recompose = -0.5 → modest
  deficit) + proteinPerKg 2.0; PlanGenerator routes split/exercise via
  FitnessGoals.planGoal (recompose → build_muscle hypertrophy) and cardio via the
  `cardio` flag (recompose = true). Default onboarding goal switched to Build. A
  gate forces every onboarding key + consumer to line up so no token can fall
  through a default again.
regression_test_planned: test/contracts/recompose_goal_targets_test.dart (7 cases — recomp deficit + 2.0 protein + hypertrophy + cardio; full goal calorie ordering; Build default) — GREEN
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: FitnessGoals SoT + BmrCalculator/PlanGenerator/CardioFinisher/display-readers rewired; analyze clean; recompose_goal_targets_test 7/7 green }"
  - "{ layer: postgres_schema, status: not_applicable, evidence: primary_goal is an existing free-text user_profile column — no migration }"
  - "{ layer: postgres_data, status: verified, evidence: 'recompose' is the canonical token already written for recomp users; no backfill needed (calc is recomputed on read/onboarding) }"
  - "{ layer: client_to_server_contract, status: verified, evidence: _mapGoal still emits 'recompose'; the gate asserts every onboarding key maps to a FitnessGoals token }"
impact_analysis: >
  Pre-fix, the pre-selected default goal silently produced maintenance calories +
  1.6 g/kg protein + a fat-loss plan for every tap-through user. Post-fix:
  Recompose is a real first-class profile (TDEE−½ pace delta, 2.0 protein,
  hypertrophy split, light cardio) and the default is Build (wedge-thesis aligned).
  No data migration — targets recompute. Touches the plan generator (rule 14 —
  authorized by the approved plan).
closes-diagnose: f19a7c
---

# F19 — Default "Recompose" goal silently produced maintenance calories

## What happened
`goal_screen.dart` pre-selected the **Recompose** card (`key: 'recomp'`,
`_goals.first`). `plan_screen._mapGoal` mapped `'recomp' → 'recompose'`. But
`'recompose'` matched no case in `BmrCalculator.calculateTargets`'s goal `switch`
→ `default` → `dailyCalories = tdee` (maintenance) + `proteinPerKg = 1.6` (lowest).
The plan engine's `SplitResolver` / `CardioFinisher` likewise fell through to the
fat-loss architecture. So the *default* goal gave every tap-through user the
opposite of a recomposition.

## Root cause
Goal tokens were **stringly-typed with no source of truth** — the same token had
to be independently handled in `BmrCalculator`, `SplitResolver`, `CardioFinisher`,
and 4 display readers. `'recompose'` was added to `_mapGoal` but never to those
consumers, so it silently hit each `default`.

## Fix
1. **Canonical SoT** `lib/core/constants/fitness_goals.dart` — one row per token:
   `{label, deltaMult, proteinPerKg, fatPercentage, planGoal, cardio}`. Recompose:
   `deltaMult -0.5` (modest deficit), `proteinPerKg 2.0`, `planGoal build_muscle`
   (hypertrophy), `cardio true` (light finisher).
2. `BmrCalculator` switch → `FitnessGoals.of(goal)` (`tdee + deltaMult × delta`).
3. `PlanGenerator` uses `FitnessGoals.of(goal).planGoal` for split/exercise (so
   the engine never sees `'recompose'`) and `.cardio` for the finisher gate;
   `CardioFinisher` self-gates via the SoT too.
4. Display readers route their `default` through `FitnessGoals.label`.
5. Default onboarding goal → **Build** (`build_muscle` first in `_goals`).
6. **Gate** `scripts/check_goal_token_exhaustiveness.dart` + behavioral test
   `test/contracts/recompose_goal_targets_test.dart`.

## Recurrence
First instance for goal-token fallthrough (no prior diagnose for this class).
Related class: writer/reader-style drift across N consumers without a SoT —
the gate makes it non-recurring. See ADR for the canonical-goal decision.
