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
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: writes primary_goal and target_weight_kg together after OI-191's agreement check", line: 1941 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwitchGoal: goal, seeded target and targets in one patch", line: 1398 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: "logWeight: the weight_<istDate> entries the callout reads", line: 165 }
  - { file: lib/features/onboarding/target_weight_check.dart, method_or_widget: "weightGapTenths / validateTargetWeight: the one gap expression and the Maintain window", line: 58 }
readers:
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: "_buildWeightTrend: hands the raw profile and the filtered weigh-ins to WeightProjectionLine", line: 651 }
  - { file: lib/features/profile/widgets/weight_projection_callout.dart, method_or_widget: "WeightProjectionLine: reads primary_goal and target_weight_kg from the profile map, then WeightProjectionCallout", line: 54 }
  - { file: lib/features/profile/widgets/weight_projection_callout.dart, method_or_widget: "WeightProjectionCallout.build: draws each ProjectionCalloutKind (exhaustive switch); maintainAsOfSuffix / parseDateKeyUtc: the staleness suffix", line: 110 }
  - { file: lib/features/onboarding/target_weight_check.dart, method_or_widget: "projectionCalloutKind: Maintain branch by distance (onTarget / offTarget), flat-series guard; Maintain skips the history gate", line: 132 }
  - { file: lib/core/copy/weight_callout_copy.dart, method_or_widget: "onTargetLine / offTargetLine / targetLabel / asOfSuffix: the Maintain words, printed from integer tenths", line: 37 }
hive_key_prefix: "userBox['profile'] keys primary_goal, target_weight_kg; healthBox weight_<istDate> (weight_kg, date)"
hive_key_formula: "read only: UserRepository.instance.getProfile()['primary_goal' | 'target_weight_kg']; weigh-ins via the weight_<istDate> entries in healthBox (no write in this batch)"
sync_methods:
  - "none: display only, no write path and no sync change"
restore_methods:
  - "none: a restored profile or weight log is read by the same widget"
cloud_table: null
cloud_columns: []
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "istDateStr: today's IST date for the Maintain 'as of' staleness (follow-on 2026-11-19; one conversion, never istNow(); the weigh-in keys are IST date keys read as UTC calendar dates); the date sentence keeps DateTime.now() (an injectable clock in the widget, for tests)", line: 94 }
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
    sentence. FOLLOW-ON (founder 2026-11-19, plan `docs/plans/oi518-maintain-followon.md`): Maintain SKIPS the history gate (the
    gate is `weeksDiff < 0.5 && goal != 'general_fitness'`, Cut / Build keep it), and a Maintain line carries ` · as of <date>` when
    the last weigh-in is more than 7 days old.
  - U2 `lib/core/copy/weight_callout_copy.dart`: the words, from integer tenths, never a float.
  - U3 `lib/features/profile/widgets/weight_projection_callout.dart`: the callout leaves the Reports screen as a stateless widget
    with a REQUIRED `goal` and an exhaustive switch statement. B-pass amendment: `WeightProjectionLine` also owns the profile-to-callout
    chain (the screen hands over `profile: profile, entries: filtered`, pinned to those exact arguments), because the first version's
    inline `goal:` argument was protected only by a source grep.
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
| f | Maintain branch moved above the history gate | 2 (this is now the SHIPPED design, follow-on 2026-11-19; the mutant is moot) |
| g | Maintain branch moved below the `adjust` / `reached` lines | 13 |
| h | `missing` mapped to `onTarget` | 1 |
| i | Maintain branch for every goal (`if (true)`) | 11 |
| j | history gate `<` -> `<=` | 1 (Cut / Build only after the follow-on; see the follow-on table p1 / p2) |
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
  FOUNDER DECISION 2026-11-19: leave as is.
- A profile with NO `primary_goal` passes `''` and keeps today's non-Maintain path on this card (elsewhere a missing goal reads as
  `general_fitness`): pre-existing, unreachable through onboarding (the goal step precedes Stats).
- `recomp` is not healed by `LegacyGoalHealer` (`FitnessGoals.legacyTargets` maps only `strength` and `recompose`) and passes the
  goal rule as an unruled token: its callout behaviour is unchanged.
- A Maintain user keeps ONE of the two trend-era gates (B-pass finding 1): at least two weigh-ins in the selected window.
  FOUNDER DECISION 2026-11-19: Maintain skips the half-week rule (a distance needs no span), so two weigh-ins a day apart already
  draw the line; Cut and Build keep it (follow-on, `projectionCalloutKind`).
- On the "All" filter the callout judges the LAST weigh-in whatever its age, so a Maintain user whose last weigh-in is months old
  reads the present-tense "Holding the line" line (B-pass finding 5). FOUNDER DECISION 2026-11-19: a Maintain line gets
  ` · as of 3 Nov` (` · as of 28 Dec 2026` when the year differs from today's IST year) when the last weigh-in is MORE than 7 days
  old (`kMaintainStaleAfterDays`, `maintainAsOfSuffix`); Cut and Build lines are unchanged. The 1W filter already drops entries
  of 7 days or older, so the suffix shows on 1M / 3M / All.
- The Home `WeightTrendChart` prints "You've reached your goal weight!" at a 0.2 kg distance for every goal, Maintain included: a
  separate surface with its own rule, not the OI-518 card.
- The Weekly Report Edge Function narrative (`weekly-report/index.ts`) is not the card; changing it is an Edge Function deploy and
  needs its own per-action go.
- The staleness suffix reads the dev/test clock seam (`now ?? nowWall()`), while the Cut / Build date sentence (`DateTime.now()`) and
  the screen's 1W / 1M window cutoff do not (B-pass seat 1, follow-on). Only the dev panel's time travel can show the difference
  (`setTestClock` is a no-op in release); changing the Cut / Build sites is outside the founder-approved scope.
- The Maintain off-target line followed by the suffix reads `... · adjust your nutrition to hold the line · as of 3 Nov` (two
  separators): the founder-approved shape, wrapped by the row's `Expanded`.
- The `adjust` row keeps a named duplicate of the pure rule's `goal.contains('lose')` for its "diet" / "nutrition" word (Cut and
  Build only now; the Cut and Build wording rows of the behavioural test pin it).

## B-pass mutation round (CLAUDE.md 4.4 rule 21, lens 6)

A fresh seat ran 82 mutant applications on the post-plan tree (`docs/reviews/bb5a04f8a371-review.md`): 66 killed by a runtime
assertion, 2 by a source-grep pin only, 8 equivalent, 6 real survivors. The survivors were fixed and re-mutated: the screen's wiring
(7 mutants: an always-empty goal, a re-derived goal, the callout hidden for Maintain, a wrong or rounded target, reversed or
truncated entries) now dies on runtime rows over `WeightProjectionLine` plus an exact-arguments pin; an in-window big-swing trend
gate, an ignored injected clock, the 0.1 kg gate boundary, a removed `targetWeight <= 0` guard (visible only for a Cut with no target)
and the removed 10 px spacing each redden a test. Pin-only protection that remains: the screen's two call arguments (a mutant that
changes `filtered` or `profile` elsewhere in the screen is the screen's own, unchanged logic).

## Device check (founder, after /build-apk)

A Maintain profile with weigh-ins inside the 3 kg band (once falling, once rising) must show the green "Holding the line" line and
no date or "Adjust"; one beyond the band the orange line with the side; a Cut profile with a whole target must show the same chart
label and date sentence as before.

## Follow-on 2026-11-19: history gate and "as of" suffix (plan `docs/plans/oi518-maintain-followon.md`, revision 4, 3 review rounds)

Tests: `test/onboarding/target_weight_check_test.dart`, `test/contracts/weight_callout_copy_test.dart`,
`test/contracts/maintain_weight_callout_behavioral_test.dart` (146 tests; 153 with the call-site pin
`test/contracts/projection_gate_single_source_test.dart`, the fourth file of the mutation runs; green under `TZ` = Asia/Kolkata, UTC, Etc/GMT+12 and
America/New_York). Mutations run against the four test files (each confirmed APPLIED by a changed-file assertion, the tree
re-hashed after the run; a compile error would not have counted, none occurred). Failing tests per mutant in brackets:

| id | mutant | red |
|---|---|---|
| a | Maintain exemption removed | 3 |
| b | exemption applied to every goal | 3 |
| c | Cut-only / Build-only exemption | 4 / 4 |
| d, e | staleness `<=` to `<`; `<=` to `<= +1` | 6 / 6 |
| f1 | today from the UTC components | 4 in every zone |
| f2 | today from `now.toLocal()` | 4 UTC, 7 Etc/GMT+12, 4 New_York; EQUIVALENT in Asia/Kolkata (local = IST) |
| f3 | today from `DateTime.now()` | 8 in every zone |
| f4 | hand-rolled +5:00 / +6:00 offset | 1 / 1 in every zone (the 18:29Z / 18:31Z rows) |
| f5 | DOUBLE IST shift | 2 in every zone (the 14:00Z row) |
| f6 | ages as a local-midnight difference | 1 in America/New_York (the DST row); EQUIVALENT in the three fixed-offset zones |
| g | suffix dropped from `_offTargetRow` / `_onTargetRow` | 2 / 6 |
| h | suffix on a Cut / Build `eta` / `adjust` / `reached` row | 3 / 5 / 3 |
| i | year rule on month / inverted / from `DateTime.now()` | 2 / 14 / 5 |
| j | two month names swapped / list off by one | 2 / 14 |
| k | `.abs()` on the age (a future date shows the suffix) | 2 |
| l | `now` ignored by the staleness read / `WeightProjectionLine` drops `now:` | 7 / 2 |
| m | staleness read from `entries.first` | 22 |
| n, o | leading zero kept; separator changed | 6 / 14 |
| p1, p2 | history gate `<` to `<=`; `0.5` to `0.6` (Cut / Build rows at exactly 0.5) | 1 / 1 |
| q | `lastDay` / `today` swapped | 10 |
| r | key regex without `^`; without `$`; round trip on the day only | 1 / 2 / 1 |

Equivalent mutants, not counted: `lastDay.year < today.year` for `!=` (the caller never passes a future day); dropping the year
comparison from the round trip, and keeping ONLY the month comparison (every rolled date, whether a day or a month overflow,
changes the month, so the month comparison alone is a complete guard; the other two comparisons are belt and braces). The plan
expected month-only to be killed; the run measured it as equivalent.

### Follow-on B-pass mutation seat (100 mutants, 91 applied, 2026-11-19)

The seat applied 91 mutants on head 2d34fa0d; 17 survived, all missing pins (no shipped-code defect). Each now has a test and was
re-run (confirmed applied, killed, tree restored and re-hashed):

| survivor | mutant | killed by | red |
|---|---|---|---|
| M1, M2, M3 | the production clock `now ?? nowWall()` replaced by a 2000 / 2100 constant / `istNow()` | `WeightProjectionLine` with NO injected clock under `setTestClockTo` (14:00Z, next day, 2031) | 1 each |
| M93, M94, M95 | suffix / last weigh-in read from `entries[1]` | three-weigh-in Maintain rows (on and off target) | 1 / 1 / 2 |
| M100 | the span's last date read from the middle entry | three-weigh-in Cut row with the middle entry on the first day | 1 |
| M44, M49 | hidden gap / size condition on the Maintain exemption | pure rows (gap 15 kg at 0.14 weeks; target 120 at 0.4 weeks) | 1 each |
| M37, M35 | Cut / Build exemption at `lastW == target`; `weeksDiff >= 0` | pure rows (a short or negative span is `none` for Cut and Build) | 1 each |
| M77 | IST day taken one minute early | the exact 18:30Z row (IST midnight) | 1 in every zone |
| M67, M68 | key regex `\d{1,2}` month / `\d{3,4}` year | bad keys `2026-1-05`, `026-11-18` (and `2026-1-5`, `2026-11-1`) | 1 each |
| M75, M76 | no suffix for a key more than 5 years / 3650 days old | a 2014 key prints `as of 5 Mar 2014` | 1 each |

Equivalent (seat's reasoning, accepted): `entries.length < 1` in the line (the callout's own `< 2` guard catches it); `.inHours ~/ 24`
on UTC dates; `!startsWith('general')` / `!contains('fitness')` (the only such goal); `now ?? DateTime.now()` (identical to `nowWall()`
in a release build).
