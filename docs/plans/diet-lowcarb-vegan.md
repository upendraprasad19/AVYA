# Diet plan: vegan Low carb plans fall short (founder observation, 2026-11-15)

Branch `diet-lowcarb-vegan`. Blast radius `account`: `lib/core/services/seed_service.dart` sits under
`lib/core/services/**` (account in `docs/blast_radius.yaml`); the food asset, `lib/features/nutrition/**`,
tests and docs are feature tier.
Execution mode (§4.12.7): inline, one worktree.

## 1. Observation and measurement

The founder, on the live web app (vegan, Low carb, 2153 kcal, 142 g protein, 108 g carbs, 128 g fat),
saw a plan of about 1637 kcal and 87 g protein (76 % and 61 % of target) and asked whether macros are
met. Measured with a harness over 40 seeds per cell (the generator alone, then with the Unit 4 shake,
which adds one scoop of plant protein when the day is 15 g or more short):

| Profile (kcal / protein) | Diet | kcal | protein | protein + shake | carbs | fat |
|---|---|---|---|---|---|---|
| 2153 / 142 | vegan | 78 % | 65 % | 82 % | 116 % | 76 % |
| 2153 / 142 | veg | 93 % | 73 % | 90 % | 100 % | 105 % |
| 2153 / 142 | non-veg | 95 % | 96 % | 100 % | 93 % | 98 % |
| 2600 / 170 | vegan | 70 % | 59 % | 73 % | 109 % | 68 % |
| 1600 / 120 | vegan | 87 % | 63 % | 83 % | 129 % | 92 % |

Vegan Low carb is the one clearly starved cell; veg and eggetarian are borderline at high targets;
non-veg is fine.

## 2. Cause (writer and reader, file:line before the change)

- Pool: `diet_plan_catalog.dart` "Unit 3b: Low carb / Keto only" block (F0402..F0264). Of those 14 entries
  only coconut (F0483), coconut milk (F0383) and four plain vegetables are vegan; the rest are ghee,
  butter, paneer, cheese, eggs, chicken. A vegan Low carb day has no fat or protein food that fits a
  carb ceiling except tofu and soy chunks.
- Template: `kLowCarbSlotTemplates` (`curated_diet_plan_generator.dart`): lunch has `side` as its only
  optional role and the evening snack none, so the slot sizer (`_sizeSlot`, calories weight 3, carb
  ceiling weight 5) has nothing to add calories with once the grain and legume sit at the slot's carb cap.
- Cap: `dietFamilyLowCarbCapOverride` lets a Low carb day hold two soy-family items; vegan protein is
  mostly soy (tofu, tempeh, soy chunks).
- Reader of all three: `CuratedDietPlanGenerator._poolFor` (pool filter), `_sampleDay.fits` (cap),
  `_sizeSlot` (optional roles), and `swapAlternatives` / `swapCatalogFor` (the swap sheet).

## 3. Change

1. Five catalog entries, Low carb PLANS only (a new flag `lowCarbPlansOnly`, always with `lowCarbOnly`):
   tempeh F1017, edamame F1018, avocado F0455, almond butter F0480, chia seeds F0082. All five rows exist
   in the asset and are vegan and non-UPF.
2. `kLowCarbSlotTemplates`: lunch optional `[side, fat]`, evening snack optional `[fat]`.
3. `dietFamilyLowCarbPlanCapOverride = {soy: 3}` (Low carb only) and one function `dietFamilyCapFor`.
4. `diet_plan_catalog_rules.dart` (new): `dietFamilyCapFor` and `catalogEntryOffered`, used by the generator
   and the swap sheet (the catalog file must import nothing: the asset patch script loads it).
5. Asset: `scripts/patch_food_database_v4.dart` re-run, five rows `is_everyday: false -> true`.
   `_foodLibraryVersion` 5 -> 6 so installed boxes re-seed (the swap sheet treats `is_everyday: false` as
   retired).

Not changed: Balanced (the new entries are `lowCarbOnly`, invisible to Balanced; goldens G1/G2) and Keto
(the new entries are `lowCarbPlansOnly`, the soy override is Low carb only, the templates are Low carb's).
Measured: all 14 Keto rows of the T10 matrix are byte-identical before and after.

## 4. Result (same harness, after)

| Profile | Diet | kcal | protein | protein + shake | carbs | fat |
|---|---|---|---|---|---|---|
| 2153 / 142 | vegan | 88 % | 76 % | 92 % | 116 % | 94 % |
| 2153 / 142 | veg | 95 % | 82 % | 98 % | 100 % | 107 % |
| 2153 / 142 | non-veg | 98 % | 103 % | 104 % | 92 % | 103 % |
| 2600 / 170 | vegan | 84 % | 72 % | 86 % | 111 % | 90 % |
| 1600 / 120 | vegan | 91 % | 74 % | 93 % | 127 % | 98 % |

Tried and rejected: a tighter carb ceiling (weight 8 slot, 1.05 day) brought vegan carbs to 108 % but
calories to 79 %, so it trades one miss for a bigger one. Vegan carbs stay 11 to 27 % over target; the
carb sources of a vegan day (legumes, millets) cannot be cut without starving calories.

## 5. Tests

- Pins moved with the change: the Low carb / Keto only id set (14 -> 19), the fat-role set, the template
  strings, the cap pin (+ `dietFamilyCapFor`), the T10 plan-level cap check (uses `dietFamilyCapFor`).
- New: the five foods are offered to Low carb only (plans and swap catalog, Keto never holds one, vegan
  Low carb plans do); `food_library_v4_upgrade_behavioral_test` gains the v5 -> v6 path and the v6 mirror.
- B-pass additions (seat B): the cap function is pinned by a literal table (seven families x three strategies); the
  five new entries are pinned by literal (roles, family, portions); the vegan Low carb plans must use EACH of the five
  (not any one); the Keto soy clause is tightened to at most one (Keto's carb cap leaves tofu as its only soy food, so
  the clause cannot see a Keto cap mutant, the swap-site test is the real pin); the screen test derives its 19 from
  the catalog. Mutations over the new pins: cap function drops the older Low carb layer for non-soy families; avocado
  loses its snack role; chia moves from `nut` to `fat`; edamame loses `side` (results in the review file).
- T10 floors rebaselined from the built code (minimum over 50 seeds minus 0.02). 14 of 16 Low carb rows
  rise (kcal floor +0.00 to +0.08, three rows unchanged; protein floor up to +0.15); TWO worst seeds move
  down by 0.03 because every Low carb plan's random stream changed (an optional role draws once more):
  `maintain vegan` protein 0.71 -> 0.68 (its kcal floor rises 0.69 -> 0.77) and `1200 floor veg` kcal
  0.90 -> 0.87. This is the one place the "raise only" contract bends. The contract text now says so in
  the registry (`diet_plan_curated.class_constraints`), the nested CLAUDE.md and the test, and names the
  rule: a change to a strategy's random stream may re-baseline that strategy's T10 rows, and every lowered
  row is written above `floors`. Keto rows are not re-baselined (byte-identical).
- The other four Low carb limits of that test were re-measured too (review R1-2). Worst row of the 16,
  before -> after, against the asserted limit: calories max 1.10 -> 1.08 (limit 1.12); carbs per-plan max
  1.47 -> 1.41 (limit 1.50), worst row `cut vegan`; carbs mean max 1.21 -> 1.20 (limit 1.25), same row;
  fiber min 0.33 -> 0.33 (limit 0.31, `cut female veg`). None moved toward its limit, so none is edited.
- Swap-site cap (review R1-4): `swapAlternatives` applies `dietFamilyCapFor` too. A test drives it for
  Low carb (two soy items in the plan: another is offered; three: none), Keto (one: tofu offered; two:
  none) and Balanced (one: none).
- Generator-site cap (review R2-1): a test counts soy-family foods by food id (not through `dietFamilyCapFor`)
  and asserts that a Low carb plan reaches exactly 3 while no Keto plan passes 2. It reaches 3, so the
  override is used and not dead weight.
- Keto golden (review R2-2): `G3` hashes all 800 Keto plans (16 archetypes x 50 seeds, vegan Keto built as
  Balanced). The value was captured on origin/main 8ecfc8fd, before this change, and this branch produced the
  identical hash `a47758f5...1885d`, so "Keto is byte-identical" is a permanent pin next to Balanced's G1/G2.
- Mutations (§4.4 rule 21; each confirmed applied with `grep -c` or a pattern-found check, then restored):
  G1 drop `lowCarbPlansOnly` on avocado (red, 1 test); G2 Low carb soy override removed (red, 2); G3 lunch
  fat dropped (red, 2); G4 evening fat dropped (red, 2); G5 `catalogEntryOffered` Keto ignores the flag
  (red, 2); G5b Balanced sees `lowCarbOnly` (red, 5); G6 version constant back to 5 (red, 4); G7 cap
  function ignores the Low carb override (red, 2); G8 swap catalog unfiltered for Keto (red, 1); G9 cap
  function gives Keto the Low carb override (red, 1); G10 swap cap reverts to the daily cap (red, 1, the
  new swap-site test). Ten of the eleven ran in one batch over the three generator test files; G10 ran
  alone over the swap-site test. Round 2 adds: G11 the generator's `fits` takes the Keto cap (red, 6, the
  generator-site soy test); G12 Keto offered the plan-only foods (red, 3, G3 and the Low-carb-plans-only
  test); G13 the Keto cap function gets the Low carb plan override (red, 2). Each ran over the strategy test
  file with the pattern confirmed present before the run and the file restored after.

## 5b. Landing (review R2-3)

Plan review round 1 and round 2 (one context-blind Sonnet seat each, no P0 or P1) are recorded in
`docs/plan-reviews/diet-lowcarb-vegan.md`, written once round 2's findings are closed. The B-pass
(`/code-review`, three context-blind seats) runs on the CI-green head before the merge, `bpass: accepted`
joins the record, and the merge goes through `sh scripts/land_pr.sh 285` (the founder's go for #285 was given
in chat on 2026-11-15). No APK is built. No diagnose-doc: the commits are `feat` / `chore` (rule 22 applies
to `fix` commits) and this plan, with its measurements, is the record of the observation.

## 6. Risks and mirror cases

- Existing installs re-seed the 5K-row food box once on the next launch (v5 -> v6). Same mechanism as v4
  and v5.
- A saved Low carb plan is unaffected (it is data, not re-generated); the swap sheet offers the new foods
  only for Low carb plans (`swapCatalogFor`).
- Every Low carb plan of every diet changes for a given seed (the stream moved). Veg, eggetarian,
  pescatarian and non-veg Low carb plans improve on average (measured), Keto and Balanced do not change.
- The Unit 4 shake is untouched.
- Role derivation (review R1-6, corrected by R2-4, accepted): a saved plan stores no role, and the swap
  derives it from the roles the slot allows. Only the Low carb EVENING snack allows both `snack` and `fat`
  (snack required, fat optional), so an avocado, almond butter or chia item picked there derives `snack`
  and the sheet offers snack alternatives, not fats. Lunch, breakfast and dinner have no `snack` role and
  resolve to `fat`. Keto's coconut has the same quirk; not a regression.
- Soy in one meal (review R2-7, accepted): tempeh and edamame carry no coherence token, so one Low carb
  lunch can hold both (tempeh main, edamame side), and with the cap at 3 up to three of five meals can hold
  soy. Adding the tokens would change every Low carb plan again and restart the floor re-baselining; the
  cap bounds the day, and the earlier "soy at every meal" diagnose (83ac8a) concerned a cap of 1 to 2 that
  Balanced keeps.
- Failed re-seed (review R2-8, accepted as v5 was): `_seedFoods` swallows an error and leaves the version
  key unset, so the next launch retries; meanwhile the five rows stay `is_everyday: false`, the generator
  (which never reads it) still uses them and the swap sheet does not offer them.
- Balanced swap holding a Low carb plan food (review R2-5, accepted): the G2 legacy list holds the 14 older
  ids; the five new ids go through the same `swapCatalogFor` filter before the role scan and the family
  counts, and `diet_plan_strategy_screen_test` pins that Balanced and Keto swaps never offer any Low carb
  only name (19 now). A legacy-list entry cannot be captured from main (the ids are not catalog entries
  there), so it would pin only the new behaviour.
- Soy 3 applies to every diet preference in Low carb (non-veg users included), as the plan's "every Low
  carb plan changes" says.
- B-pass A1, accepted: the Low carb soy cap of 3 applies to every diet preference. Measured over 16 archetypes x 50
  seeds, 21 of 700 non-vegan plans held three soy items (46 of 800 overall); gating it on vegan would add a
  preference parameter to the cap function, the generator and the swap sheet for a 3 % case, and the founder asked
  for a plan that meets its macros.
- B-pass A2, accepted with a measurement: the optional `fat` role in the Low carb evening snack lets ghee, butter or
  coconut milk in (213 of 800 plans; 336 at lunch, where a cooking fat is normal). Tried: a guard that keeps a snack
  slot's optional fat to foods that also carry the `snack` role (coconut, avocado, almond butter, chia). It removed
  the evening cooking fat (0 of 800) but, at 200 plans per cell, lowered vegan protein by 2 to 3 points (75 vs 77,
  71 vs 74, 69 vs 71 percent; with the shake 91 vs 92, 90 vs 92, 83 vs 85), re-rolled every Low carb floor (six
  protein floors and four kcal floors would drop, one by 0.09) and moved no non-vegan macro. This PR exists to raise
  vegan macros, so the guard was reverted. It is a presentation blemish only (macro-neutral). Reopen when a device
  check shows the founder dislikes it: the fix is that guard plus a T10 re-baseline.
- B-pass A5 / C-6, accepted: chia seeds sit in the `nut` family (daily cap 1, no Low carb override), so a day holding
  almonds or another nut item cannot also hold chia or almond butter. Consistent with the existing caps.
- Rollback: revert the PR. A device already at seed version 6 keeps the five extra `is_everyday: true` rows after a
  revert (the constant is back at 5, so it is not re-seeded); nothing reads them (the swap sheet is catalog-driven).
