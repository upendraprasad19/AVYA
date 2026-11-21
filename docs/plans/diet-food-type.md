# Plan — diet plan Unit 2a: one food-type vocabulary on the client (`diet-food-type`)

- **Date:** 2026-11-14 · **Revision:** 5 (rounds 1-4 applied, §7; round 4 verdict: converged; unit SPLIT per CLAUDE.md §4.12.1)
- **Split:** rounds 1 and 2 both found P1s in the server/coach half and none in the vocabulary core, so this unit is the CLIENT half (2a). The server/coach half (TS mirror, daily-snapshot extraction, `suggestMeal`, protein-gap-alert, weekly-report, captain manual, env switches) is Unit 2b, planned next with every carried finding (`diet-food-type-server-notes.md`). No Edge Function changes or deploys in 2a.
- **Release order (round 3 finding 1):** a push to `main` deploys the web app (`vercel.json` `ignoreCommand` builds `main` only), so 2a reaches testers the moment it merges. Before 2b, the server would mishandle the new keys: `protein-gap-alert/message.ts:17` gives an eggetarian the chicken quick fix, and `daily-snapshot` compares the AI's `vegetarian` with a locked stored `veg` by `===` (`valuesEqualForLockCheck`), writing a false conflict marker the coach reads. So **2b's Edge Functions are deployed first and 2a's PR merges after them.** 2b's server code accepts both the old and the canonical spellings (one normaliser), so deploying it before 2a changes nothing for today's stored values. 2a's PR may be built, reviewed and CI-green before that; only its merge waits. No APK is built from a tree that has 2a without 2b deployed.
- **Builds on:** Unit 1 (`diet-food-quality`, PR #269). This branch starts from Unit 1's head and syncs with `main` once #269 merges.
- **Closes:** OI-257 (the `veg` / `vegetarian` mismatch; its blocker was this product decision).
- **Bug class:** writer/reader vocabulary drift (recurrence of `a2b2f1`, OI-257) → FULL diagnose template.
- **Blast radius:** expected `account` (profile write path).
- **Execution mode (§4.12.7):** inline, one worktree (`.claude/worktrees/diet-food-type`), decided at batch start.

## 0. Founder decisions (chat, 2026-11-14), quoted

- "options will be veg, non-veg, eggetarian, pescatarian" + "keep vegan as food type, yes".
- "By default, let's keep the diet as non-veg … which will include all non-veg foods."
- "Everywhere it should be same. The coach should be aware about this. And workout generation has no effect with the diet selected."
- Food type is FREE. Selector on the diet plan screen and in Edit Profile; onboarding does not ask.
- Keto / low carb are a separate PRO "diet strategy" (Unit 3), not a food type.
- "In the nutrition screen … at the top of the screen … the user's selected diet and strategy should be mentioned" (food type here; strategy in Unit 3).
- Pre-launch: every account is a test account (CLAUDE.md §1). No migration menu, no data migration.

## 1. Symptom and inventory (read at Unit 1 head `3da92d26`)

| Site | Role | Values today |
|---|---|---|
| `lib/features/onboarding/screens/plan_screen.dart:580` | writer | `'veg'` (never asked) |
| `lib/features/onboarding/providers/onboarding_provider.dart:507, :554` | writer (Hive profile) | `?? 'veg'` |
| `onboarding_provider.dart:947` | writer (cloud push) | passthrough |
| `lib/features/profile/screens/edit_profile_screen.dart:1267-1273, :1866` | writer (chips) | `non_veg`, `vegetarian`, `vegan`, `pescatarian`, `keto` |
| `edit_profile_screen.dart:61, :235, :307, :2181-2189` | reader / lock compare | init `'non_veg'`, load `?? 'veg'` (stored `'veg'` highlights no chip, OI-257); raw-string lock compare |
| `lib/core/services/sync/sync_profile.dart:236` / `sync_service.dart:1438` | restore / push | passthrough |
| `lib/features/nutrition/screens/diet_plan_screen.dart:40, :60, :87` | reader | `?? 'veg'` |
| `lib/features/nutrition/services/diet_plan_generator.dart:1314-1343` `passesDiet` | reader | `vegan`; `veg`/`vegetarian`; anything else passes everything |
| `curated_diet_plan_generator.dart` candidate filter, `diet_plan_swap.dart:125` | reader | via `passesDiet` |
| `lib/features/nutrition/providers/diet_plan_provider.dart:52-60` `DietPlanNotifier` | reader (saved plan → Nutrition hints) | watches only `authUserIdTokenProvider` |
| `lib/features/ai_coach/services/ai_snapshot_builder.dart:109` | reader → coach | raw value |
| `supabase/functions/daily-snapshot`, `protein-gap-alert`, `weekly-report`, `_shared/captain_manual.ts`, `_shared/tools/nutrition/suggestMeal.ts` | server | Unit 2b |

Consequences today: no eggetarian choice; a pescatarian gets chicken and mutton plans; a new user is silently `veg` (founder wants `non_veg`); `keto` stored as a food type. Workout generation: `diet_preference` appears nowhere in `lib/shared/repositories/plan_engine`, `lib/features/train`, `lib/features/home` (0 hits; pinned by T6).

## 2. Design

### 2.1 One vocabulary, one normaliser

Canonical stored keys (snake_case, matching Edit Profile's `non_veg`): `veg`, `non_veg`, `eggetarian`, `pescatarian`, `vegan`. Default `non_veg`.

`lib/core/constants/food_types.dart` (pattern `equipment_defaults.dart` `equipmentAccessOf`):
- `enum FoodType { veg, nonVeg, eggetarian, pescatarian, vegan }` with `storageKey`, `label` (`Veg`, `Non-veg`, `Eggetarian`, `Pescatarian`, `Vegan`), `shortLabel` (`VEG`, `NON-VEG`, `EGGETARIAN`, `PESCATARIAN`, `VEGAN`).
- `FoodType foodTypeOf(Object? raw)`: trim, lower-case, `-` and spaces → `_`, then:
  - `veg | vegetarian | lacto_vegetarian | jain | sattvic` → veg (Jain's root-vegetable rule is not modelled; stated)
  - `non_veg | nonveg | non_vegetarian | nonvegetarian | omnivore | anything | everything` → nonVeg
  - `egg | eggetarian | eggitarian | ovo_vegetarian | lacto_ovo_vegetarian | vegetarian_eggs` → eggetarian
  - `pescatarian | pescetarian` → pescatarian
  - `vegan | plant_based` → vegan
  - null, `''` → nonVeg (founder default for "never chosen")
  - `keto | low_carb` → nonVeg (the only non-food-type values written today: Edit Profile's Keto chip, the extraction prompt)
  - any other non-null string → **veg** (fail-safe: an unknown deliberate value never serves meat)
- `FoodType foodTypeOfProfile(Map? profile)`.
- The table lives in a fixture `supabase/functions/_shared/testdata/food_type_vocabulary.json` read by the Dart test now and by Unit 2b's Deno test (inside the functions tree so the Deno job can read it).

### 2.2 Writers

1. **Onboarding:** `plan_screen.dart:580` writes `'non_veg'`; `onboarding_provider.dart:507` calls a new pure `resolveOnboardingDietPreference(answers)` (returns the answer's canonical key, default `non_veg`; round 3 finding 6) instead of the inline `?? 'veg'`; comments :468/:578 and `lib/features/onboarding/CLAUDE.md:139` updated. `:554` / `:947` stay passthrough (now carry `non_veg`).
2. **One write door:** `UserProfileNotifier.setFoodType(FoodType next)` in `lib/features/profile/providers/profile_provider.dart`. Calls are SERIALISED through a chained `Future` field on the notifier (round 3 finding 2): each call awaits the previous one, then reads the OLD value from `UserRepository.instance.getProfile()` (not from `state`), so two quick taps (Veg, then Non-veg) end with Non-veg stored and each compare is against the value the previous call actually wrote. The chain is `_chain = _chain.catchError((_) {}).then((_) => _run(...))`, so a failed link never blocks or rethrows into the next (round 4 finding 2). Each call captures the signed-in user id when it is made; after awaiting the previous link it aborts (no write, no lock, no push) if the current id differs (sign-out or account switch while queued; round 4 finding 1). Then:
   - no-op when the stored string already equals `next.storageKey`;
   - else `updateProfile({'diet_preference': next.storageKey})` (→ `UserRepository.updateProfileFields` → `ProfileWriteService.patchProfile`, which already fires `syncProfileNow` under its own signed-out guard, `profile_write_service.dart:122-126`; no second sync);
   - then, signed in only, `unawaited(SyncService.instance.pushSnapshot())` (coach snapshot, as Edit Profile does);
   - then `unawaited(UserRepository.lockCoachExtractionFields(['diet_preference']))` ONLY when the food type itself changed (`foodTypeOfProfile(old) != next`); a legacy spelling rewritten to the same type (stored `vegetarian`, tapped Veg) writes the canonical key and does not lock.
   - No `ref.invalidate(dietPlanProvider)` (round 2 finding 6): the Nutrition hints rebuild through the watch in §2.3.4, and the profile provider does not import the nutrition feature.
   - No `recalculateTargets`: the food type does not feed BMR/TDEE today (`recomputeDerivedTargets` inputs are weight/height/goal/activity). Unit 3's strategy is the first input that will; it is added to this door then.
   - The lock call is the guard for 2b's switch-ON (rollback) path, where the extraction writes the column again for an unlocked field (round 4 finding 3; 2b is deployed before 2a merges).
3. **One chip widget:** `lib/shared/widgets/food_type_chips.dart` `FoodTypeChips(value, onChanged)`: five `FoodType` values in a `Wrap(spacing: 8, runSpacing: 8)`. Each chip is Edit Profile's EXISTING selectable pill moved verbatim into the shared widget (`edit_profile_screen.dart:1282-1310`: `AnimatedContainer` 180 ms, padding 16x10, `AppColors.accentTint`/`AppColors.input` fill, accent/border outline, pill radius, `AppTypography.body` DM Sans 13 w700/w400), wrapped in `Semantics(button: true, selected: …, label: …)` with a REAL 44 dp minimum height: `constraints: BoxConstraints(minHeight: 44)` and `alignment: Alignment.center` on the `AnimatedContainer` (the existing 16x10 padding around a 13 px line is ~37 dp; round 4 finding 6). Wardroom check (round 2 finding 14, round 3 finding 5): `WardChip` is a STATUS pill (`monoXs` 9 px JetBrains Mono caps; `filled` reserved for "the single most-important chip on a screen", wardroom `CLAUDE.md:102`), unreadable as a primary selector and inconsistent with Edit Profile's sibling selectors (goal, injuries), so the shared widget reuses the selector style those siblings already use; no new style is invented. Used by Edit Profile and the Diet Plan screen. `package:` imports.
4. **Edit Profile:** `_dietPreference` → `FoodType _foodType = foodTypeOfProfile(profile)` and `_originalFoodType` the same, so stored `vegetarian`/`veg` → Veg chip, `keto`/null → Non-veg chip (OI-257 ends). The save map writes `_foodType.storageKey`. `computeCoachExtractionFieldsToLock` keeps its string signature but is passed the two canonical keys, so re-saving a stored `vegetarian` as Veg does not lock. The Keto chip disappears. FREE.
5. **Diet Plan screen selector:** `FoodTypeChips` under the TDEE card. Taps are ignored while a change is in flight (`_changingFoodType`, cleared in `finally`). On a different chip: `await ref.read(userProfileProvider.notifier).setFoodType(next)`; `setState(() => _foodType = next)` BEFORE regenerating (the swap sheet reads `_foodType`); regenerate (unsaved, `_saved = false`); snackbar "Plan rebuilt for Veg. Save to keep it." No confirm dialog (free, reversible).
6. **Sync push / restore:** passthrough; readers normalise.

### 2.3 Readers

1. **Diet Plan screen** (:40, :60, :87): `FoodType _foodType` via `foodTypeOfProfile`; `'veg'` fallbacks removed; `DietPlanInputs.dietPreference` gets `_foodType.storageKey`; `_savePlan` writes `_foodType.storageKey` as the plan's `food_type` (§2.4).
2. **`passesDiet` normalises internally** (`foodTypeOf(dietPref)` first), so existing callers and tests passing `'non-veg'`, `'vegetarian'` keep working. Signature `passesDiet(row, pref, {DietFamily? family})`:
   - vegan, veg: unchanged rules.
   - eggetarian: `family == DietFamily.egg` returns TRUE before BOTH veg checks (`is_veg == false` and the `_nonVegNames` blocklist, which lists 'Egg (Whole, boiled)' and 'Egg White (boiled)', `diet_plan_generator.dart:220-230`); otherwise the veg rule.
   - pescatarian: `family` `egg` or `fish` returns true before both checks; otherwise the veg rule.
   - nonVeg: everything passes.
   - **Egg/fish identity = the catalog family.** Measured at `3da92d26` (confirmed by both reviewers): the catalog's `is_veg == false` rows are exactly egg 7, chicken 5, fish 6, mutton 2 (20 rows). A test pins that every `is_veg == false` catalog entry has a family in `{egg, chicken, fish, mutton}`.
   - The curated generator's candidate filter and `swapAlternatives` pass the entry's family; the legacy generator (kill-switch path, OI-508) passes none, so eggetarian/pescatarian get the veg rule there (never meat; stated). The same holds when the curated generator itself falls back to legacy (`curated_diet_plan_generator.dart:225-229`, no valid sample): an eggetarian or pescatarian then gets a veg-rule plan with no egg or fish (safe; T3 asserts a fallback plan never contains meat).
   - `DietPlanInputs` comment (`diet_plan_generator.dart:86`) updated to the canonical keys.
3. **Coach snapshot:** `ai_snapshot_builder.dart:109` emits `foodTypeOfProfile(profile).storageKey` and `diet_preference_label`. +~30 bytes vs the 10K limit; `test/ai_coach/snapshot_compaction_test.dart:30` rerun. The coach already reads `snapshot.profile.diet_preference` (captain manual :282); the prose rewrite is Unit 2b.
4. **`DietPlanNotifier.build`** watches `userProfileProvider.select((p) => foodTypeOfProfile(p))` (an enum: a profile write that does not change the food type does not rebuild) and returns `{}` for a saved plan of another food type (§2.4). Sign-out safety is inherited: `userProfileProvider.build` watches `authUserIdTokenProvider` (`profile_provider.dart:41`). Import direction nutrition → profile (exists elsewhere; verify no cycle at build).
5. **Nutrition calorie card** (`nutrition_screen.dart:332`): tag line `FoodType.shortLabel` from the reactive profile already passed in (`:240-263`). Unit 3 appends ` · KETO`. Tapping the tag opens the Diet Plan screen (same route as the existing diet-plan entry on the Nutrition screen; the task board lists this). Same tag on the Diet Plan screen header and in the PDF title line.

### 2.4 Saved plan vs food type

- `_savePlan` adds a TOP-LEVEL `food_type: _foodType.storageKey` before `'meals'` (the item key-set pin slices from `'items': m.items`, unaffected). `saved_diet_plans.plan_json` is JSONB and restore writes it back verbatim (`sync_restore_completeness.dart:354-366, :567-580`).
- On first entry, a saved plan whose `food_type` differs from the current food type is not loaded; a fresh plan is generated, and a snackbar "Your saved plan was for Non-veg. Here is a Veg plan; save to keep it." shows once per (saved plan id, food type) per app session (a library-level set, `@visibleForTesting` reset, cleared in T5's `setUp`). A plan without `food_type` (saved before this unit) loads as today and keeps feeding hints whatever the current food type; such plans exist only on test accounts (pre-launch), so no heal is added.
- Intended consequence, stated: after a food-type change, the Nutrition tab's "From Your Diet Plan" hints disappear (`DietPlanNotifier` returns `{}`) until the user saves a plan of the new type; hints from a plan of the wrong food type would suggest the wrong foods.

### 2.5 Not changed in 2a

Workout generation (T6); macro targets (Unit 3); every Edge Function and the captain manual (Unit 2b); the lock mechanism and migration 148.

## 3. Kill switch (§4.6)

None for 2a. A closed-enum normaliser that maps every old value is strictly more tolerant than today; flagging it keeps two vocabularies alive, the defect itself. No AI prompt, sync, payment, auth or plan-generator ALGORITHM change. `passesDiet` output is unchanged for `veg`, `vegetarian`, `vegan`, `non_veg`, `non-veg`, `keto`, `''`; it becomes STRICTER by design for `pescatarian` (today: everything passes), `eggetarian` and any unknown or whitespace-variant string (today: everything passes; now the veg rule, or the egg/fish exception on the curated path). T3 pins every one of those rows explicitly. Guarded by T1-T5. (Unit 2b carries the env switches for the server/AI changes.)

## 4. Tests

- **T1 normaliser** (`test/core/food_types_test.dart`): every row of the fixture (veg, vegetarian, Veg with spaces, non_veg, non-veg, Non Veg, non-vegetarian, omnivore, eggetarian, eggitarian, vegetarian_eggs, pescatarian, pescetarian, vegan, plant-based, jain, keto, low_carb, null, '', `xyz` → veg); labels; storageKey round trip.
- **T2 writers** (`test/contracts/diet_preference_vocabulary_writer_to_reader_test.dart`, real Hive, write→read): `resolveOnboardingDietPreference` table (absent → `non_veg`, `veg` → `veg`, `vegetarian` → `veg`); `plan_screen.dart:580` writes `'non_veg'` (PRESENCE pin, stated: a widget method; the SoT entry marks that leg `presence_only` with this reason); `setFoodType` writes each key; locks on a real change; does NOT lock for stored `vegetarian` → Veg (writes `veg`); no-op on equal; two un-awaited calls (Veg, then Non-veg) end with `non_veg` stored and two locks (both are real changes: non_veg → veg → non_veg; corrected at build time, diagnose `6f5aaa`); pushSnapshot skipped when signed out (seam); a queued call whose user id changed before it runs writes nothing; a throwing first link does not stop the second; Edit Profile save of each chip writes its canonical key and re-saving stored `vegetarian` as Veg yields no lock field (`computeCoachExtractionFieldsToLock`).
- **T3 generator** (`test/nutrition/curated_diet_plan_test.dart`): eggetarian and pescatarian archetypes (cut + maintain) × 50 seeds on the real asset; eggetarian: no chicken/fish/mutton family; pescatarian: no chicken/mutton; positive controls (an egg item in ≥1 eggetarian plan; a fish item in ≥1 pescatarian plan); protein floors start at the veg floors and are raised only after measuring (contract, raise only); swap alternatives obey the rule with an **independent oracle** (family sets + `is_veg`, never `passesDiet`); catalog family pin; `passesDiet` table: unchanged rows (`veg`, `vegetarian`, `vegan`, `non_veg`, `non-veg`, `keto`, `''`) and the deliberately stricter rows (`pescatarian`, `eggetarian`, `xyz`, `'veg '`) each pinned; the egg exception passes 'Egg (Whole, boiled)' (on the `_nonVegNames` list) for eggetarian; positive controls assert an egg item / a fish item actually APPEARS; a forced-fallback eggetarian/pescatarian plan contains no meat.
- **T4 chips** (`test/shared/food_type_chips_test.dart`; `test/profile/edit_profile_food_type_test.dart`): five chips, `selected` semantics, each chip ≥44 dp tall at textScale 1.0 and 2.0 with no overflow, no Keto; Edit Profile with stored `veg` / `vegetarian` / `keto` / null highlights Veg / Veg / Non-veg / Non-veg.
- **T5 saved plan + hints** (`test/contracts/diet_plan_saved_loaded_behavioral_test.dart` extended, real Hive): mismatch → fresh plan + snackbar once; no `food_type` → loaded; equal → loaded; `DietPlanNotifier` returns `{}` on mismatch and rebuilds after a `setFoodType` write AND after an Edit-Profile-style `updateProfile` write (both doors).
- **T6 workout isolation** (`test/contracts/food_type_no_workout_reader_test.dart`, PRESENCE ONLY, stated): no `diet_preference`, `profile['diet`, `foodType`, `FoodType` under `plan_engine/`, `train/`, `home/`.
- **T7 card tag** (widget): EGGETARIAN for an eggetarian profile, NON-VEG for an empty one.
- **Re-run (pin old literals, expected green):** `test/nutrition/diet_plan_quality_constraints_test.dart`, `test/nutrition/diet_plan_generator_test.dart`, `test/nutrition/food_database_tagged_test.dart`, `test/ai_coach/snapshot_compaction_test.dart`, `test/ai_coach/coach_memory_model_test.dart`, `test/profile/edit_profile_coach_extraction_lock_test.dart`, `test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart`, `test/widgets/diet_plan_screen_no_modal_test.dart`.
- **Mutations** (diagnose table): unknown → nonVeg; `vegetarian` → nonVeg; eggetarian without the egg exception; pescatarian admits chicken; `setFoodType` locks on a spelling-only change / never locks; mismatch ignored; `DietPlanNotifier` stops watching; chip list keeps Keto; onboarding default back to `veg`.

## 5. Docs / registries

New SoT concept `diet_preference_vocabulary` (writers §2.2, readers §2.3, `behavioral_test_path` T2); edit `docs/sot_registry.yaml:~1567` (saved-plan schema gains `food_type`) and any `line_range` this diff shifts (recompute from anchors); `docs/naming_conventions.md` rows (`food type` = user-facing name of `diet_preference`; `FoodType`; `FoodTypeChips`); nested CLAUDE.md: nutrition, profile (:48), onboarding (:139), ai_coach (:38); OI-257 closed; diagnose doc FULL (`related_bugs: [a2b2f1]`, recurrence OI-257); task board: Unit 2 shown as 2a + 2b.

### 5.1 Build checklist (round 3 findings 9-11)

- Rename every Edit Profile site of `_dietPreference` / `_originalDietPreference` (`edit_profile_screen.dart:61, :104, :235, :307, :1286-1288, :1866, :1903-1904`); `grep -n "_dietPreference" lib/` returns nothing afterwards.
- Imports of the shared widget: `package:icanbefitter/core/theme/colors.dart` (`AppColors`), `package:icanbefitter/core/theme/typography.dart` (`AppTypography`), `package:icanbefitter/core/theme/spacing.dart` (`AppRadius`), as `edit_profile_screen.dart:16-18` already does; plus `package:icanbefitter/core/constants/food_types.dart`.
- The PR description and the plan-review record carry a pre-merge line: "Do not merge before Unit 2b's Edge Functions are deployed (versions recorded in 2b's diagnose doc)." (round 4 finding 4)
- Labels exactly `Veg`, `Non-veg`, `Eggetarian`, `Pescatarian`, `Vegan` (the founder's words); `shortLabel` upper-case for the card tag.
- After writing the new files, run `dart run scripts/blast_radius_from_diff.dart` on the real paths (CLAUDE.md §4.9: it fails open on a missing path) and add `docs/blast_radius.yaml` entries if a new path lands below its true tier; recompute `docs/sot_registry.yaml` ranges for `coach_extraction_locked_fields` (`:16452-16510`) and the diet-plan concepts (`:1448-1549`) from their anchors.
- `test/widgets/diet_plan_screen_no_modal_test.dart` asserts `Icons.refresh` and `Icons.check_circle` `findsOneWidget`: the chips must add neither icon.

## 6. Verified while planning (at `3da92d26`)

- `UserProfileNotifier.updateProfile` (`profile_provider.dart:45`) → `UserRepository.updateProfileFields` (`user_repository.dart:295`) → `ProfileWriteService.patchProfile` (mutex; `_fireSync` → `syncProfileNow` with a signed-out guard, `profile_write_service.dart:122-126`). `UserRepository.lockCoachExtractionFields` static (`:1374`).
- `saved_diet_plans.plan_json JSONB NOT NULL` (migration 048); restore verbatim.
- `DietPlanNotifier.build` watches only `authUserIdTokenProvider` today (`diet_plan_provider.dart:55`); `userProfileProvider.build` watches it too (`profile_provider.dart:41`).
- `WardChip` (`ward_chip.dart:17`) is a tone pill with no `onTap`.
- Cloud `food_database.is_veg` populated on every row (read-only query 2026-11-14), relevant to 2b.

## 7. Review dispositions

### Round 1 (on revision 1)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | unknown → non_veg serves meat | Unknown non-null → veg (§2.1). |
| 2 | P1 | raw extracted value reaches notes/embeddings/markers | Unit 2b (server). |
| 3 | P1 | suggestMeal egg/fish heuristic admits meat | Unit 2b. |
| 4 | P2 | Edit Profile door leaves hints stale | `DietPlanNotifier` watches the food type (§2.3.4, T5). |
| 5 | P2 | two door descriptions; signed-out guard | One door `setFoodType`, one `FoodTypeChips` (§2.2.2-3). |
| 6 | P2 | suggestMeal filters after limit | Unit 2b. |
| 7 | P2 | swap oracle calls the helper under test | Independent oracle + family pin (T3). |
| 8 | P2 | AI writes the cloud column only | Unit 2b (extraction stops writing it); 2a doors lock on change meanwhile (§2.2.2). |
| 9 | P2 | AI/prompt changes without a lever | Unit 2b switches. |
| 10 | P2 | Deno tests pin raw values | Unit 2b. |
| 11 | P2 | snackbar every visit; stale `_dietPref` | Once per session; `setState` before regenerate (§2.2.5, §2.4). |
| 12 | P3 | protein feasibility | Floors from veg floors, raise after measuring (T3). |
| 13 | P3 | stale registry/comments/CLAUDE.md | §5. |
| 14 | P3 | T6 weak; fixture location | Presence-only, widened; fixture under `_shared/testdata/` (§2.1). |
| 15 | P3 | chip accessibility | Semantics + 44 dp (§2.2.3). |

### Round 2 (on revision 2)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | no single normalise point before every daily-snapshot consumer | Unit 2b (top of `mergeCoachingNotes` + parser). |
| 2 | P1 | lock/conflict modes under the switch unstated | Unit 2b; 2a keeps the client lock, purpose stated (§2.2.2). |
| 3 | P1 | fake_sb has no `.or` | Unit 2b (two `.eq` queries). |
| 4 | P1 | name heuristics unsafe both ways | Unit 2b (whole-word lists, `is_veg` column for `isVeg`). |
| 5 | P1 | Gemini-style spellings fall to veg | Added to §2.1 and T1. |
| 6 | P2 | invalidate creates profile→nutrition import, redundant | Dropped; the watch is the one mechanism (§2.2.2, §2.3.4). |
| 7 | P2 | duplicate `syncProfileNow` | Removed; only `pushSnapshot` added (§2.2.2). |
| 8 | P2 | recalculateTargets | Not needed now; Unit 3 adds it to this door (§2.2.2). |
| 9 | P2 | legacy-spelling lock cases | Both pinned in T2; Edit Profile compares canonical keys (§2.2.4). |
| 10 | P2 | post-selector hint loss; `_savePlan` key source; static set isolation | Stated as intended (§2.4); `_foodType.storageKey`; resettable set. |
| 11 | P2 | notifier watch safety/test setup | Confirmed safe; T5 uses real Hive. |
| 12 | P2 | onboarding :554/:947 missing | Added to §1, T2. |
| 13 | P2 | old-literal tests to re-run | Listed in §4. |
| 14 | P2 | Wardroom primitive | `WardChip` wrapped (§2.2.3). |
| 15 | P3 | Jain simplification | Stated (§2.1). |
| 16 | P2 | split | Done: this is 2a; 2b next. |

### Round 3 (on revision 3)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | pre-2b window: new keys reach protein-gap-alert and daily-snapshot's `===` lock compare via the auto-deployed web app | Release order: 2b's Edge Functions deploy first, 2a merges after (header). |
| 2 | P2 | `setFoodType` no-op check races on stale state; double regenerate | Serialised chain, old value read from the repository; screen ignores taps in flight; T2 race case (§2.2.2, §2.2.5). |
| 3 | P2 | "unchanged for every value" is false | Reworded: unchanged set and stricter-by-design set, each pinned (§3, T3). |
| 4 | P2 | egg exception must bypass both veg checks | Stated; T3 uses a row on `_nonVegNames` (§2.3.2). |
| 5 | P2 | WardChip is a 9 px status pill | Shared widget reuses Edit Profile's existing selector pill; rationale stated (§2.2.3). |
| 6 | P2 | onboarding default has no seam | Pure `resolveOnboardingDietPreference`; widget leg presence-only with reason (§2.2.1, T2). |
| 7 | P2 | curated-to-legacy fallback for egg/fish types | Stated; T3 asserts no meat in a fallback plan (§2.3.2). |
| 8 | P3 | pre-2a saved plans keep feeding hints | Stated, test accounts only (§2.4). |
| 9 | P3 | rename checklist | §5.1. |
| 10 | P3 | blast radius of new files; registry ranges | §5.1. |
| 11 | P3 | label casing | `Veg`, `Non-veg`, … (§5.1). |

### Round 4 (on revision 4) — verdict: converged

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | queued `setFoodType` across a sign-out/account switch | Capture the user id; abort if changed; T2 case (§2.2.2). |
| 2 | P2 | a failed chain link poisons the next | `catchError` before `then`; T2 case (§2.2.2). |
| 3 | P3 | lock rationale contradicted the release order | Reworded: guard for 2b's rollback path (§2.2.2). |
| 4 | P3 | release order only in prose | Pre-merge line in the PR description and record (§5.1). |
| 5 | P3 | imports unnamed | Named (§5.1). |
| 6 | P3 | 44 dp not real with the current padding | `minHeight: 44` + centre alignment; T4 at textScale 2.0 (§2.2.3). |
