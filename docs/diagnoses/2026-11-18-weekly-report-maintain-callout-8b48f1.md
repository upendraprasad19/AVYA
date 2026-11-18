---
bug_id: 8b48f1
date: 2026-11-18
batch: oi518-maintain-callout
status: fixed
blast_radius: account
tier: m_fix
symptom: |
  OI-518 (found while investigating OI-191, founder 2026-11-18). The Weekly Report's weight-trend card decided "moving the right
  way" with `goal.contains('lose')`, so every goal that is not Cut read as "wants to gain". For Maintain (`general_fitness`,
  target within 3 kg of the current weight):
  - a small drift DOWN showed the orange "Adjust your nutrition to stay on track";
  - a drift UP showed "At current rate, you'll reach <target> kg in ~N weeks (around <month year>)", a date to a hold-weight
    target.
  Found on the way (same function, same batch): a flat Cut / Build series with the target exactly 0.5 kg away skipped both the
  `adjust` and the `reached` line and divided by a zero rate in the date sentence, so `Infinity.ceil()` threw inside `build`.
concept: goal_target_weight_agreement
sot_registry_entry: goal_target_weight_agreement
contract_test_path: test/contracts/maintain_weight_callout_behavioral_test.dart
related_bugs: [b5d2e8]
recurrence: |
  Not a recurrence. Same card, other half, of OI-191 (b5d2e8: "the Weekly Report's Maintain wording is OI-518"): OI-191 made the
  goal and the target agree and gated the callout's DATE sentence; it left the trend-direction decision alone. Bug-history lookup
  (CLAUDE.md 4.1.5, indexes rebuilt 2026-11-18): the goal-token drift entries (f19a7c, a4f7e1) are a different class. The
  Journey card is not affected: `journey_timeline.dart` needs `goal.contains('lose')` or `'build'` (or a 0.5 kg clause) before its
  date line, so a Maintain user never reaches it (read directly, not run on a device).
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: writes primary_goal and target_weight_kg together after OI-191's agreement check", line: 1936 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwitchGoal: goal, seeded target and targets in one patch", line: 1395 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: "logWeight: the weight_<istDate> entries the callout reads", line: 165 }
  - { file: lib/features/onboarding/target_weight_check.dart, method_or_widget: "weightGapTenths / validateTargetWeight: the one gap expression and the Maintain window", line: 58 }
readers:
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: "_buildWeightTrend: reads target_weight_kg and primary_goal, builds WeightProjectionCallout", line: 744 }
  - { file: lib/features/profile/widgets/weight_projection_callout.dart, method_or_widget: "WeightProjectionCallout.build: draws each ProjectionCalloutKind (exhaustive switch)", line: 58 }
  - { file: lib/features/onboarding/target_weight_check.dart, method_or_widget: "projectionCalloutKind: Maintain branch by distance (onTarget / offTarget), flat-series guard", line: 136 }
  - { file: lib/core/copy/weight_callout_copy.dart, method_or_widget: "onTargetLine / offTargetLine / targetLabel: the Maintain words, printed from integer tenths", line: 37 }
hive_key_prefix: "userBox['profile'] keys primary_goal, target_weight_kg; healthBox weight_<istDate> (weight_kg, date)"
hive_key_formula: "read only: UserRepository.instance.getProfile()['primary_goal' | 'target_weight_kg']; weigh-ins via the weight_<istDate> entries in healthBox (no write in this batch)"
sync_methods:
  - "none: display only, no write path and no sync change"
restore_methods:
  - "none: a restored profile or weight log is read by the same widget"
cloud_table: null
cloud_columns: []
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key is written or compared by this batch; the date sentence keeps DateTime.now() (an injectable clock in the widget, for tests)", line: 1 }
provider_invalidations:
  - "none: the widget is rebuilt by the Reports screen's own setState and reads Hive-backed values passed in by the screen"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a: a display widget over values the screen already read from the signed-in profile"
forbidden_patterns_checked:
  - { pattern: "goal.contains('lose') as the Weekly Report's only direction test for a Maintain goal", absent: true }
  - { pattern: "a Maintain goal drawing a date sentence or an Adjust verdict", absent: true }
  - { pattern: "an inline (lastW - targetWeight).abs() gap in a gated reader", absent: true }
  - { pattern: "toStringAsFixed in the Maintain copy", absent: true }
  - { pattern: "a switch over ProjectionCalloutKind with a default arm", absent: true }
proposed_fix: |
  Plan docs/plans/oi518-maintain-callout.md (revision 4), record docs/plan-reviews/oi518-maintain-callout.md (3 rounds).
  Founder decisions (2026-11-18): a Maintain goal is judged by DISTANCE to the target, never by trend; inside the 3.0 kg window a
  hold line with the distance, beyond it a warning with the distance and the side, never a date.
  - U1 `target_weight_check.dart`: `weightGapTenths` (the one gap expression, shared with `validateTargetWeight`);
    `ProjectionCalloutKind` gains `onTarget` and `offTarget`; `projectionCalloutKind` decides Maintain right after the history
    gate by `validateTargetWeight` on the LAST weigh-in (five-arm switch, no default); a flat series returns `none` before the date
    sentence.
  - U2 `lib/core/copy/weight_callout_copy.dart`: the words, from integer tenths, never a float.
  - U3 `lib/features/profile/widgets/weight_projection_callout.dart`: the callout leaves the Reports screen as a stateless widget
    with a REQUIRED `goal` and an exhaustive switch statement; the screen passes `primary_goal`.
regression_test_planned:
  - test/contracts/maintain_weight_callout_behavioral_test.dart
  - test/onboarding/target_weight_check_test.dart
  - test/contracts/weight_callout_copy_test.dart
  - test/contracts/projection_gate_single_source_test.dart
impact_analysis: |
  Account tier by path (the shared rule lives under lib/features/onboarding, read by Edit Profile and the coach door), but the
  behaviour change is one display widget. Cut and Build output is byte-identical except the flat-series crash edge (now no callout).
  No migration, no schema, no Edge Function, no stored key. The app is pre-launch with testers only (CLAUDE.md section 1).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "target_weight_check, weight_callout_copy, weight_projection_callout, reports_screen; whole-project flutter analyze and the pre-commit gate loop run before the push" }
  - { layer: hive_local_state, status: verified, evidence: "read only: primary_goal and target_weight_kg from the profile and the weigh-ins the screen already passes in; nothing is written" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration" }
  - { layer: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed; the weekly-report narrative reads the stored profile for its own text and is not the card" }
  - { layer: client_server_contract, status: not_applicable, evidence: "display only; no request or response shape changed" }
---

## Root cause

- **Reader:** `reports_screen.dart` `_buildProjectionCallout` (removed) and `target_weight_check.dart` `projectionCalloutKind`
  decided direction with `wantsLose = goal.contains('lose')`: `movingRight = (wantsLose && rate < 0) || (!wantsLose && rate > 0)`.
  Maintain has no direction to move in, so a down-drift read "not moving the right way" (`adjust`) and an up-drift read "moving
  the right way" (`eta`, a date).
- **Writer:** none drifted. `primary_goal` and `target_weight_kg` are written together by the three OI-191 doors and agree at save
  time; the weigh-ins come from `logWeight`. The defect is a reader that applied a gain/lose test to a hold goal.
- **Second defect, same function:** `weeklyRate == 0` with `|remaining| == 0.5` skipped `adjust` (`> 0.5`) and `reached`
  (`< 0.5`) and reached `(remaining / weeklyRate).abs().ceil()`, which throws on infinity.

## Fix

See `proposed_fix`. Execution mode: inline (section 4.12.7); subagents only for the three plan-review rounds. The copy was fixed by
the founder in the brainstorm; the Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`) carries palette, type and
primitives and no copy-voice rules (the same finding as OI-191's copy review), so the lines reuse the app's own words ("Hold the
line" is the Maintain card's subtitle on the goal screen; "adjust your nutrition" is the callout's existing phrase) and the
callout's existing colours and icons. The psychology-pass skill was not run on founder-fixed wording.

## Mutation record (CLAUDE.md 4.4 rule 21)

The new protection is the tests written in this batch, so the fix was mutated and the four test files re-run for each mutant
(`TZ=Asia/Kolkata flutter test` on `target_weight_check_test`, `weight_callout_copy_test`,
`maintain_weight_callout_behavioral_test`, `projection_gate_single_source_test`; 110 tests green unmutated). Each mutant was
confirmed APPLIED (the driver asserts the file text changed and re-hashes the four files after the run), none was a compile
error, and every non-equivalent mutant reddened at least one test.

| Mutant | What changed | Tests reddened |
|---|---|---|
| a | Maintain branch disabled (`if (false)`) | 18 |
| b | window edge `<=` -> `<` in `validateTargetWeight` | 7 |
| c | `above` / `below` swapped in the copy | 9 |
| d | the widget draws `offTarget` as `onTarget` | 5 |
| e | the screen's call replaced by a `SizedBox` | 1 (PIN-ONLY: the call-site pin) |
| f | Maintain branch moved above the history gate | 2 |
| g | Maintain branch moved below the `adjust` / `reached` lines | 13 |
| h | `missing` mapped to `onTarget` | 1 |
| i | Maintain branch for every goal (`if (true)`) | 11 |
| j | history gate `<` -> `<=` | 1 |
| k | the screen passes `goal: ''` | 1 (PIN-ONLY: the call-site pin) |
| l | the widget passes a truncated raw gap instead of `weightGapTenths` | 1 (the 66.9 / 70.0 float-edge row) |
| m | the Maintain branch judges `firstW` | 7 |
| n | `weightGapTenths` arguments swapped in the widget (side word flips) | 5 |
| o | the flat-series guard removed | 2 |

Equivalent mutant, not counted: swapping the arguments of `validateTargetWeight` inside the Maintain branch (the window is
judged by the absolute gap). Pin-only protection (e, k): no test pumps `ReportsScreen`; the call-site pin reads the extent of the
`WeightProjectionCallout(` call, so the same tokens elsewhere in the file cannot satisfy it.

## Accepted residue

- A true gap of 3.04 kg reads `onTarget` with "3.0 kg" (one-decimal rule, the same as the onboarding window).
- A fractional Maintain target (the onboarding seed IS the current weight, e.g. 74.8) prints `74.8 kg` in the new line while the
  chart label above it and the other surfaces print the stored target with `toStringAsFixed(0)` ("Goal: 75kg"). Changing those
  five surfaces would also change fractional Cut / Build targets on screens outside OI-518; not done here (plan round 2).
- A profile with NO `primary_goal` passes `''` and keeps today's non-Maintain path on this card (elsewhere a missing goal reads as
  `general_fitness`): pre-existing, unreachable through onboarding (the goal step precedes Stats).
- `recomp` is not healed by `LegacyGoalHealer` (`FitnessGoals.legacyTargets` maps only `strength` and `recompose`) and passes the
  goal rule as an unruled token: its callout behaviour is unchanged.
- The Home `WeightTrendChart` prints "You've reached your goal weight!" at a 0.2 kg distance for every goal, Maintain included: a
  separate surface with its own rule, not the OI-518 card.
- The Weekly Report Edge Function narrative (`weekly-report/index.ts`) is not the card; changing it is an Edge Function deploy and
  needs its own per-action go.
- The `adjust` row keeps a named duplicate of the pure rule's `goal.contains('lose')` for its "diet" / "nutrition" word (Cut and
  Build only now; the Cut and Build wording rows of the behavioural test pin it).

## Device check (founder, after /build-apk)

A Maintain profile with weigh-ins inside the 3 kg band (once falling, once rising) must show the green "Holding the line" line and
no date or "Adjust"; one beyond the band the orange line with the side; a Cut profile with a whole target must show the same chart
label and date sentence as before.
