# OI-518: the Weekly Report weight card must treat Maintain as a hold-weight goal (founder, 2026-11-18)

Branch `oi518-maintain-callout`, revision 4 (plan-review rounds 1 to 3 applied, section 7). Tier M (§4.12.6: the diff leaves
`lib/features/{home,train,nutrition,profile}/**` for the shared rule in `lib/features/onboarding/` and `lib/core/copy/`; more
than 2 product files). Blast radius `account` (`dart run scripts/blast_radius_from_diff.dart` on the product paths,
2026-11-18; `docs/blast_radius.yaml:432` puts `lib/features/onboarding/**` at account). Execution mode (§4.12.7): inline, one
worktree; subagents only for the plan-review rounds (at most 2 at a time, Sonnet, context-blind). No migration, no Edge
Function, no stored key, no schema. §4.6 is not triggered (not payment, sync, auth, an AI prompt or the plan generator): no
kill switch, rollback is a revert of the PR.

## 1. Founder decisions (2026-11-18, this session)

1. Maintain (`general_fitness`) is judged by DISTANCE to the target, never by trend direction.
2. Inside the 3.0 kg band (`kMaintainWindowKg`, inclusive, integer tenths): a hold line with the distance, green check, no
   date, no "Adjust" warning. Copy: `Holding the line · 1.2 kg from your 75 kg target` (`Holding the line · right on your
   75 kg target` at 0.0 kg).
3. Beyond the band, either side: an orange warning with the distance and the side, no date:
   `3.4 kg above your 75 kg target · adjust your nutrition to hold the line` (`below` for the other side).
4. Cut and Build are unchanged (`adjust` / `reached` / `eta` exactly as OI-191 left them), except one crash edge fixed on the way
   (U1: a flat series with a target exactly 0.5 kg away threw inside `build`; it now shows no callout).

## 2. Writers and readers (named before the change)

| Concept | Writer | Reader |
|---|---|---|
| `primary_goal` + `target_weight_kg` | onboarding `stats_screen.dart` (validated), Edit Profile `_save`, coach `_executeSwitchGoal` (all three agree-checked by OI-191, diagnose `b5d2e8`); weigh-ins: `weight_<date>` entries in `healthBox` and the weight-log writers | `reports_screen.dart:666-667` (reads `profile` and `target_weight_kg` from `UserRepository.instance.getProfile()`), `:909` (`primary_goal`, a SECOND `getProfile()` read inside the callout), `:891` `_buildProjectionCallout` -> `target_weight_check.dart` `projectionCalloutKind` (`wantsLose = goal.contains('lose')` at `:120` is the root: every non-Cut goal reads as "wants to gain") |
| the callout's words | inline literals in `_buildProjectionCallout` (`reports_screen.dart:921-962`); `You've reached your goal weight!` is the existing Cut / Build reached line | the Weekly Report weight card only |

Bug-history check (§4.1.5, indexes rebuilt 2026-11-18): not a recurrence. Same card, other half, of OI-191 (`b5d2e8`: "the
Weekly Report's Maintain wording is OI-518"). Goal-token drift (`f19a7c`, `a4f7e1`) is a different class. The Journey card is
NOT affected: `journey_timeline.dart:58-60` `movingRight` needs `goal.contains('lose')` or `'build'` (or the 0.5 kg clause),
and the date line then also needs `remaining.abs() > 0.5`, so a Maintain user never reaches `journeyEtaAllowed`'s date line
(read directly, not run). The three `canProjectGoalDate` readers return false for Maintain already. Legacy goal tokens:
`FitnessGoals.legacyTargets` (`fitness_goals.dart:132`) heals only `strength` -> `build_muscle` and `recompose` -> `lose_fat`
(`LegacyGoalHealer`, `lib/core/services/legacy_goal_healer.dart`); `recomp` is not healed and, like any other unruled token,
passes `validateTargetWeight` (`target_weight_check.dart:53-57`) and keeps today's `adjust` / `reached` / `eta` behaviour,
unchanged by this batch (it has no band rule to apply).

## 3. Units

**U1. The rule (`lib/features/onboarding/target_weight_check.dart`, pure).**
- NEW `int weightGapTenths(double current, double target)` = `((target - current) * 10).round()`: the ONE expression of the gap
  in integer tenths. `validateTargetWeight` computes its `tenths` through it (behaviour byte-identical: same expression), and
  the copy (U2) reads the gap through it, so the kind and the printed distance can never disagree by construction.
- `ProjectionCalloutKind` gains `onTarget` and `offTarget` (not `hold` / `drifted`: `hold` is the reserved free-tier repeat
  week, `docs/naming_conventions.md:358`). In `projectionCalloutKind`, right after the `weeksDiff < 0.5` gate (unchanged: too
  little history stays `none`; the Maintain branch sits BELOW it, so a Maintain user with two same-week weigh-ins sees
  nothing, as today), `if (goal == 'general_fitness')` (the literal `validateTargetWeight` itself uses at
  `target_weight_check.dart:53-55`) decides by the ONE band rule, judged on the LAST weigh-in (`lastW`, never `firstW`):
  `switch (validateTargetWeight(goal: goal, current: lastW, target: target))` over ALL five `TargetWeightCheck` values with no
  default: `ok` = `onTarget`, `outsideMaintainWindow` = `offTarget`, `missing`, `mustBeBelowCurrent`, `mustBeAboveCurrent` =
  `none` (the last two cannot occur for Maintain; `none` is the safe arm and a new check value is an analyzer error). The trend
  arithmetic below it is untouched and unreachable for Maintain, with ONE addition for Cut and Build (round 3): after the `reached`
  line, `if (weeklyRate == 0) return none` before the date sentence. Reachable today: a flat series (80.0 and 80.0) with a Cut
  target of exactly 79.5 has `remaining = -0.5`, which skips both `adjust` (needs `> 0.5`) and `reached` (needs `< 0.5`), so the
  date sentence divides by a zero rate and `Infinity.ceil()` throws `UnsupportedError` inside `build`. The guard turns that crash into
  no callout (a pre-existing bug in the code being moved, fixed here, §4.2). Every other Cut / Build input is unchanged. The exported signature
  `ProjectionCalloutKind projectionCalloutKind(` stays (the single-source test greps it). File header gains the two kinds.
- The existing test `Maintain keeps the date sentence inside its window, none beyond` encodes the bug and is rewritten
  (`general_fitness, 74 -> 75, target 77` = `onTarget`; `target 80` = `offTarget`), not loosened.

**U2. The words (`lib/core/copy/weight_callout_copy.dart`, new, pure; class `WeightCalloutCopy`).**
- `onTargetLine({required int gapTenths, required double target})` and `offTargetLine({required int gapTenths, required
  double target})`, plus `targetLabel(double)` (the target as the new lines print it; named `targetLabel`, not `targetKg`, so no
  parameter shadows it). The copy takes the gap as INTEGER tenths (`target - last`, from `weightGapTenths`) and never imports
  `lib/features`, so `lib/core/copy` stays free of feature imports; the WIDGET calls `weightGapTenths(lastW, target)`, the same
  helper `validateTargetWeight` uses, so the kind and the printed distance share one source. Preconditions (dartdoc):
  `target > 0` and finite; `onTargetLine` takes `gapTenths.abs() <= 30`, `offTargetLine` `> 30`; the copy is never called for `none`.
- The literal templates (the separator is U+00B7 written as the escape `\u00B7`, a space on each side):
  - on target: `Holding the line \u00B7 ${gap} kg from your ${T} kg target`;
  - on target, `gapTenths == 0`: `Holding the line \u00B7 right on your ${T} kg target`;
  - off target: `${gap} kg ${above|below} your ${T} kg target \u00B7 adjust your nutrition to hold the line`.
- `gap` is built from integers (`abs ~/ 10`, `.`, `abs % 10`), never `toStringAsFixed`, so a float edge cannot print `3.0` under
  `offTarget` (always >= 3.1) or `3.1` under `onTarget` (always <= 3.0). `above` when `gapTenths < 0` (last is above the target),
  `below` when `> 0`. A true gap of 3.04 kg reads `onTarget` / `3.0 kg` (the one-decimal rule, same as the onboarding window;
  stated in the diagnose doc).
- `targetLabel(double)`: guarded by `isFinite && > 0` (else the empty string, never reached from the widget); `t = (target * 10)
  .round()`; whole when `t % 10 == 0` (printed as `t ~/ 10`), else one decimal from the integers. 75 and 75.0 -> `75`; 74.5 ->
  `74.5`; 74.84 -> `74.8`; 74.96 -> `75`; 99.95 -> `100`.
- Scope decision (round 2): `targetLabel` is used ONLY in the two new lines. The chart's `Goal: ${...}kg` label
  (`reports_screen.dart:857`), the eta sentence (`:960`) and every other surface that prints the stored target with
  `toStringAsFixed(0)` (`weight_trend_chart.dart:350`, `journey_timeline.dart:158`, `nutrition_targets.dart:26,30`,
  `nutrition_screen.dart:524`) stay as they are, so Cut and Build are byte-identical. Accepted residue, stated in the diagnose
  doc: a fractional Maintain target (the onboarding seed IS the current weight, e.g. 74.8) reads `74.8 kg` in the new line and
  `Goal: 75kg` on the chart above it. Changing those five surfaces for fractional Cut / Build targets is a visible change
  beyond OI-518 and is not made here.
- Vocabulary: "Holding the line" is the Maintain card's own subtitle (`goal_screen.dart:68`, "Hold the line \u00B7 feel your best");
  "adjust your nutrition" is the existing callout's phrase. The Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`)
  holds palette, type and primitives and no copy-voice rules (same finding as OI-191's copy review); the wording is the
  founder's (section 1), so the psychology-pass skill is not run on it; colours stay the callout's own (`AppColors.ok` /
  `AppColors.warn`, check and warning icons, `AppTypography.bodySm`). The glossary row for the user-facing phrase carries
  "NOT the free-tier hold week".

**U3. The widget (`lib/features/profile/widgets/weight_projection_callout.dart`, new).**
- A stateless `WeightProjectionCallout({required entries, required targetWeight, required goal, DateTime? now})`. `goal` is
  REQUIRED with no default, so a call site that forgets it does not compile.
- `build` keeps the old preamble (`reports_screen.dart:892-904`): `entries.length < 2` -> empty `SizedBox` (new guard; the old
  body trusted the caller), `firstDate` / `lastDate` null -> empty `SizedBox`, `firstW` / `lastW` from `weight_kg`, `weeksDiff`,
  `projectionCalloutKind(...)`; `weeklyRate` and `remaining` are NOT preamble locals: only the `eta` method computes them (no unused local, which
  the analyzer would flag). It then returns through an EXHAUSTIVE `switch` STATEMENT over
  `ProjectionCalloutKind` with no default, one `return` per kind (Dart enforces exhaustiveness on a statement too, so a kind
  added later is an analyzer error, which the pre-push hook aborts on): `none` -> empty `SizedBox`; `adjust` -> the old warning
  row; `reached` -> the old reached row (moved as it is today); `eta` -> the old date row with `DateTime.now()` replaced by
  `now ?? DateTime.now()`; `onTarget` / `offTarget` -> the new rows, built from `WeightCalloutCopy` with
  `gapTenths: weightGapTenths(lastW, targetWeight)`. The per-kind rows are private methods so each arm is one call and the old
  locals (`weeklyRate`, `weeksToGo`, `targetDate`, `monthNames`, `dateLabel`) stay inside the arm that uses them. The new rows use
  `Expanded` text so a long line wraps. `eta` is reached only with `weeklyRate != 0` (the U1 guard), so the date maths never divides by zero; no new kind reaches that arm.
- The widget computes NO `(weight - weight).abs()` of the two weights (the single-source test bans that shape in a gated file).
  It keeps `wantsLose = goal.contains('lose')` for the "diet" / "nutrition" word of the old `adjust` row: a deliberate, named
  duplicate of `target_weight_check.dart:120`'s predicate (the `adjust` kind is Cut / Build only now; the Cut and Build wording
  rows of the behavioural test pin it).
- `reports_screen.dart` calls `WeightProjectionCallout(entries: filtered, targetWeight: targetWeight, goal:
  profile['primary_goal'] as String? ?? '')`, with `profile` already read at `:666`; this is the ONE new behavioural line in the
  screen (the second `getProfile()` read at `:909` goes away with the method). The `target_weight_check.dart` import at `:9`
  becomes unused there and is removed; the new import is added. `reports_screen.dart` shrinks (allow-listed by the god screen
  gate). A profile with NO `primary_goal` still passes `''` and keeps today's non-Maintain path on this card (elsewhere the app
  defaults a missing goal to `general_fitness`, `fitness_goals.dart:62`): pre-existing, unreachable through onboarding (the goal
  step precedes Stats), accepted residue stated in the diagnose doc.

## 4. Tests (§4.4 rules 21 and 24)

- `test/onboarding/target_weight_check_test.dart`: a Maintain table through `projectionCalloutKind`, all `general_fitness`:
  - in-band falling (76 -> 74, target 75), rising and flat -> `onTarget`;
  - the old `reached` zone must NOT win: last 75.2 rising to target 75 -> `onTarget`, and last 74.8 falling to target 75 ->
    `onTarget` (the old code gave `reached` for both); the old `adjust` row is the falling in-band 76 -> 74 / target 75
    (remaining 1.0) -> `onTarget`;
  - the LAST weigh-in decides: first out of band, last in band (80 -> 76, target 75) -> `onTarget`; first in band, last out
    (76 -> 80) -> `offTarget` (kills a mutant that judges `firstW`);
  - the inclusive boundary in tenths: last 78.3 / target 75.3 -> `onTarget`, 78.4 / 75.3 -> `offTarget`, and the mirror
    (72.3 / 75.3 `onTarget`, 72.2 / 75.3 `offTarget`);
  - beyond the band both sides -> `offTarget`;
  - `weeksDiff` 0.4 with an in-band pair -> `none` (the Maintain branch sits below the gate), `weeksDiff` exactly 0.5 -> `onTarget`
    (kills a `<` -> `<=` mutant on the gate; the widget cannot reach 0.5, so this row is pure);
  - target 0, negative, NaN, infinity and lastW 0, NaN -> `none`;
  - Cut / Build rows re-asserted unchanged (`adjust`, `reached`, `eta`, the OI-191 `none`s), which also kills "the Maintain
    branch applied to every goal"; the flat-series crash edge: Cut 80.0 -> 80.0 with target 79.5 and Build 80.0 -> 80.0 with
    target 80.5 -> `none` (kills a mutant that removes the `weeklyRate == 0` guard);
  - `weightGapTenths` pinned (sign, rounding of 78.3 - 75.3), and `validateTargetWeight` results unchanged for the existing table.
- `test/contracts/weight_callout_copy_test.dart` (the repo keeps copy tests in `test/contracts/` and next to their service; no
  `test/core/copy/` exists): the exact strings of the three templates (on target, right on, above, below) with the `\u00B7`
  separator; gaps of 30 and 31 tenths print `3.0` and `3.1`; `targetLabel` rows 75, 75.0, 74.5, 74.84 -> `74.8`, 74.96 -> `75`,
  99.95 -> `100`, NaN / infinity / 0 -> empty; the copy file contains no `toStringAsFixed` and no `features/` import (source pins,
  comment-stripped), so the distance is never re-derived from a float and the layering holds.
- `test/contracts/maintain_weight_callout_behavioral_test.dart` (the regression test): first a typography warmup test (the
  `test/widgets/day_swap_allowance_line_test.dart:50-66` pattern: `AppTypography.bodySm` rendered before anything else), then
  `WeightProjectionCallout` from explicit entries, no Hive open (so the `Save` / `closeAll` hang class is unreachable):
  - a `Map<ProjectionCalloutKind, fixture>` with `expect(rows.keys.toSet(), ProjectionCalloutKind.values.toSet())`; for each fixture
    the test FIRST asserts `projectionCalloutKind(...)` of the fixture's own first / last / weeks / target equals its key (a
    fixture pasted under the wrong key fails), THEN pumps it and asserts: `none` -> no text under
    `find.descendant(of: find.byType(WeightProjectionCallout), matching: find.byType(Text))` (MaterialApp and Scaffold hold other
    `SizedBox`es, so the check is scoped), and entries `< 2` the same; `adjust` -> `Adjust your diet` for a Cut and `Adjust your
    nutrition` for a Build; `reached` -> `You've reached your goal weight!`; `eta` -> a regex on `~N weeks` with `now` injected;
    `onTarget` / `offTarget` -> the exact copy;
  - Maintain falling inside the band shows the on-target line and NOT `Adjust your`; rising inside shows it and NOT `At current
    rate`; flat inside shows it (no division by zero); drifted above and below show the warning with the right side word;
  - a float-edge row: last 66.9 / target 70.0, measured in a scratch Dart run 2026-11-18: `(70.0 - 66.9) * 10` is
    30.999999999999943, so `round()` gives 31 (`offTarget`, `3.1 kg below`) while `truncate()` gives 30 (the on-target text); a
    call site that stops using `weightGapTenths` prints the wrong gap and reddens (mutation l);
  - the flat-series crash edge through the widget: a Cut at 80.0 / 80.0 with target 79.5 pumps without an exception and shows nothing;
  - icon and text colour asserted by icon type and text style colour (`AppColors.orange` equals `AppColors.warn` and `green`
    equals `ok` in `colors.dart:118-130`, so the assertion proves the icon and the role, not a hue difference).
- `test/contracts/projection_gate_single_source_test.dart`: the `reports_screen.dart` entry is REPOINTED to
  `weight_projection_callout.dart` (`projectionCalloutKind(`); the NEW call-site pin lives in `maintain_weight_callout_behavioral_test.dart` (it reads the extent of the `WeightProjectionCallout(` call in
  `reports_screen.dart` (the open paren to its matching close, comment-stripped) and requires `goal:` and `primary_goal` INSIDE
  it, so the same tokens elsewhere in the file cannot satisfy it). The inline-gap regex then runs on the widget file; the repoint
  drops `reports_screen.dart` from that check, acceptable because the callout logic leaves that file. These pins are presence
  only; the behaviour is the tests above.
- Mutations (run and recorded in the diagnose doc, §4.4 rule 21; `grep -c` confirms each applied; a compile error is not a proof;
  the diagnose doc says which are PIN-ONLY): (a) the Maintain branch disabled; (b) band `<=` -> `<` (the inclusive edge, through
  `validateTargetWeight`); (c) `above` / `below` swapped in `offTargetLine`; (d) the widget renders `offTarget` as `onTarget`;
  (e) the `reports_screen.dart` call removed (pin-only); (f) the Maintain branch moved above the `weeksDiff` gate; (g) the
  Maintain branch moved below the `adjust` / `reached` lines; (h) `missing` mapped to `onTarget`; (i) the goal check dropped
  (Maintain branch for every goal); (j) the gate `<` -> `<=`; (k) the call site passes `goal: ''` (pin-only); (l) the widget passes
  a truncated raw gap instead of `weightGapTenths` (the float-edge row); (m) the Maintain branch judges `firstW`. (n) the widget's `weightGapTenths(lastW, targetWeight)` arguments swapped (the side word flips; the above / below rows redden);
  (o) the `weeklyRate == 0` guard removed. Swapping the arguments of `validateTargetWeight` INSIDE the Maintain branch is an
  equivalent mutant (the window is judged by the absolute gap) and is not counted. Each
  non-equivalent mutant must redden at least one test; a mutant that reddens nothing is reported as such, not as coverage.

## 5. Docs and ledgers

- Diagnose doc `docs/diagnoses/2026-11-18-weekly-report-maintain-callout-8b48f1.md` (full template; `bug_id` equals the file
  suffix; `related_bugs: [b5d2e8]`; `touched_layers_checked`: client code, Hive local state read only, the other tiers
  `not_applicable`; accepted residue: the 3.04 kg one-decimal reading, the `recomp` token, the missing-goal profile, the
  fractional-target label mismatch of U2). Gate names are NOT written in the `Gate N (check_x.dart)` form anywhere in the diagnose
  doc or the closed entry (the gate-index builder parses that shape as a number claim).
- `docs/sot_registry.yaml` `goal_target_weight_agreement`: the `reports_screen.dart` reader row keeps a row for the call site (`method: _buildWeightTrend`, semantic: passes `goal:` into
  `WeightProjectionCallout`; the stale `_buildProjectionCallout` row is replaced) and a new reader row names `weight_projection_callout.dart` / `WeightProjectionCallout.build` (semantic: Maintain onTarget /
  offTarget by distance); a sibling key `behavioral_test_path_maintain_callout:
  test/contracts/maintain_weight_callout_behavioral_test.dart` registers the new behavioural test (Gate 42 sibling form). This
  concept's rows carry no `line_range`, so there is no range to recompute.
- `lib/features/profile/CLAUDE.md` row `goal_target_weight_agreement` (the sentence "The Weekly Report's Maintain wording is
  OI-518" becomes the rule) and `lib/features/onboarding/CLAUDE.md:122` (the two new kinds, `weightGapTenths`);
  `docs/naming_conventions.md` §8 glossary (three columns: Term, Meaning, What it is NOT): `WeightProjectionCallout`,
  `onTarget` / `offTarget`, `WeightCalloutCopy`, `weightGapTenths`, with "NOT the free-tier hold week (`holdWeek()`)" on the
  phrase "Holding the line". Collision grep for each new symbol before adding (round 2 found none).
- `docs/audit/open_issues.md` and `lib/features/onboarding/CLAUDE.md` are context-artifact-budget tracked: after the edits run
  `dart run scripts/check_context_artifact_budget.dart` and, only if a band is crossed, `--record` (build the local indexes first,
  memory `reference_tooling_traps_record_budget_and_mint_oi_2026_11_06`).
- OI-518: archived to `docs/audit/closed_issues.md` by APPEND (never a rewrite; memory
  `feedback_append_to_archive_never_rewrite_check_diff_stat_deletions`; check the diff-stat deletions), with the line
  `- **Status**: CLOSED · <date> · ...` (a real middle dot, as the OI-191 entry has it) (`closed_issues.md:7319`; `check_closes_oi_performed.dart`
  reads it), removed from `open_issues.md`; the commit carries `closes-oi: OI-518` and `closes-diagnose: 8b48f1`.
- Plan-review record `docs/plan-reviews/oi518-maintain-callout.md`: `review_rounds: 3` (round 1: two reviewers, round 2: two, round 3: one; listed per round in the record's table),
  `ground_truth_verified: true`, `verdict: converged`, and at the merge `bpass: accepted` WITH `bpass_review:
  docs/reviews/<file>.md` (committed, with a line-anchored `verdict: accepted`) as the OI-191 record does
  (`docs/plan-reviews/oi191-goal-target.md:9`). The `/code-review` run writes that review file; the commit that adds it carries a
  dated `## Tuning entry` section INSIDE it (CLAUDE.md §5.1, `check_skill_tuning_history.dart`) or pre-commit blocks it.
- Out of scope, with the reason (not deferred work): the Weekly Report's own Edge Function narrative (`weekly-report/index.ts`)
  reads the stored profile for its text and is not the card; changing it is an Edge Function deploy and needs its own per-action
  go (§4.3). Nothing in it was reported against Maintain. The other surfaces that print the stored target with
  `toStringAsFixed(0)` (U2) are unchanged. The Home `WeightTrendChart` (`lib/shared/widgets/weight_trend_chart.dart:140-142`, `:209`)
  prints "You've reached your goal weight!" at a 0.2 kg distance for every goal, Maintain included: a separate surface with its own
  rule, not the OI-518 card (named in the diagnose doc so it is not read as missed). `docs/superpowers/specs/2026-10-03-progress-review-design.md:53` cites the old method
  by name and line; it is a historical spec and is not edited.

## 6. Verification before review and before the merge

Whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, targeted tests with `TZ=Asia/Kolkata`, then commit
through `scripts/safe_commit.sh`, open the PR, `sh scripts/land_pr.sh <pr> --ci-only`, `/code-review` (B-pass, writes
`docs/reviews/<file>.md` with its `## Tuning entry`) on `ci-green`, the record updated with `bpass: accepted` and `bpass_review:`,
then the founder's merge go. Device check (the founder, after `/build-apk`): a Maintain profile with weigh-ins inside the band
(falling and rising) and one beyond it, on the Weekly Report's weight card, plus a Cut profile with a whole target (the chart
label and the date sentence unchanged).

## 7. Findings and where each landed

### Round 1

| # | Sev | Finding | Landed in |
|---|---|---|---|
| A1 | P1 | an if-chain falls through to the date sentence for a new kind; flat series divides by zero | U3 exhaustive `switch`, flat-series widget test |
| A2 | P1 | test rows missing (old `reached` zone, gate order, 0.5 exact, non-finite) and mutants f-i | section 4 table and mutations f-m |
| A3 | P1 | copy re-derives the gap | U1 `weightGapTenths`, U2 integer formatting, mutation l, no-`toStringAsFixed` pin |
| A4 | P1 | target printing undefined at its edges; chart label mismatch | U2 `targetLabel` (round 2 limited it to the new lines) |
| A5 | P2 | boundary pairs worked by hand | section 4 boundary rows; 3.04 kg residue in the diagnose doc |
| A6 / B7 | P2 | wrong line cites, `recomp` is not healed, orange equals warn | section 2, section 4 colour bullet |
| A7 | P2 | existing Maintain test must be rewritten | U1 |
| A8 / B3 | P1 | single-source regex would hit the widget | U3 (no weight difference in the widget), section 4 repoint note |
| A9 | P2 | copy test location | `test/contracts/weight_callout_copy_test.dart` |
| B1 | P1 | `goal` is not read at `:666-667`; nothing tests the call site | U3 required `goal`, the call-site pin, mutation k |
| B2 | P1 | "one test per kind" is not achievable as written | `Map` keys == `values` test plus the exhaustive switch |
| B4 | P1 | `hold` collides with the reserved glossary term | enums renamed `onTarget` / `offTarget`, glossary NOT column |
| B5 | P1 | SoT range recompute step is a no-op | section 5 |
| B6 | P2 | "verbatim" is not exact; empty entries throw | U3 wording and the `< 2` guard |
| B8 | P2 | context-artifact budget | section 5 |

### Round 2

| # | Sev | Finding | Landed in |
|---|---|---|---|
| C1 | P1 | parameter `targetKg` shadows the static `targetKg()` | U2 formatter renamed `targetLabel` |
| C2 / D5 | P1 | revision 2 changed the chart label and eta sentence, a visible change for fractional Cut / Build targets on one screen only | U2 scope decision: `targetLabel` only in the two new lines, accepted residue recorded |
| C3 | P1 | a switch EXPRESSION cannot hold the arms' locals; the preamble was unspecified | U3 keeps the preamble, a switch STATEMENT with one return per kind, per-kind private methods |
| D1 | P1 | `bpass: accepted` needs `bpass_review:` and a `## Tuning entry` | section 5 plan-review record, section 6 |
| C4 | P2 | `wantsLose` duplicated | U3 names the duplicate |
| C5 / C6 / D5 | P2 | non-finite input throws in `targetLabel` / `weightGapTenths` | U2 `isFinite` guard and dartdoc preconditions |
| C7 | P2 | literal strings were examples only | U2 templates with the `\u00B7` escape |
| C8 / D5 | P2 | `lib/core/copy` would import `lib/features` | U2: the copy takes `gapTenths`, the widget calls `weightGapTenths`; layering pin in the copy test |
| C9 / D4 | P2 | missing goal profiles keep the non-Maintain path | U3 accepted residue (pre-existing, unreachable through onboarding) |
| D2 | P2 | no mutant judging `firstW` | section 4 rows and mutation m |
| D3 | P2 | fixture not tied to its key; SizedBox check unscoped | section 4: `projectionCalloutKind(...) == key`, `find.descendant` |
| D4 | P2 | Maintain detection and the other two `TargetWeightCheck` values | U1: the literal, a five-arm switch with no default |
| D1b | P2 | (e), (k), (l) were pin-only | section 4: extent-reading pin, a float-edge widget row, pin-only mutants named in the diagnose doc |
| D6 | P2 | gate-index parse of `Gate N (check_x.dart)`; closed entry Status line | section 5 |
| D7 | P2 | the new behavioural test was not registered | section 5 `behavioral_test_path_maintain_callout` |
| D8 | P2 | wrong cite `:38-50`, "three product paths", "f-j" | corrected |

### Round 3 (one reviewer, revision 3)

| # | Sev | Finding | Landed in |
|---|---|---|---|
| E1 | P1 | "no divide by zero in `eta`" is false: a flat series with `|remaining| == 0.5` skips `adjust` and `reached` and throws in `build` (pre-existing) | U1 `weeklyRate == 0` guard, section 1 item 4, section 4 rows and mutation o |
| E2 | P2 | the old code gave `reached` for 74.8 falling | section 4 wording |
| E3 | P2 | the equivalent-mutant sentence was too broad | section 4 mutation n and the scoped sentence |
| E4 | P2 | preamble versus arm locals contradicted | U3: `weeklyRate` / `remaining` only inside the `eta` method |
| E5 | P2 | the Home chart's own reached line | section 5 out of scope |
| E6 | P2 | the SoT call-site row had no `method:` | section 5 (`_buildWeightTrend`) |
| E7 | P2 | the record must say three rounds | section 5 |
