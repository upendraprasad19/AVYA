# Plan — diet plan Unit 3: diet strategy (Balanced / Low carb / Keto, PRO)

Revision 7, 2026-11-14 (round dispositions: §6 round 1, §7 round 2, §8 round 3, §9 round 4, §10 round 5, §11 round 6). **Design change in revision 3:** the strategy is applied when targets are READ, not written; the stored targets stay exactly what they are today. Branch `diet-strategy` (worktree based on `diet-food-type`, Unit 2a, because it extends `FoodTypeTag`, the food-type selector rows and `profile_provider.dart`; it syncs with `main` after 2a merges and before its own review CI). Blast radius: account (onboarding, profile, sync) + the Unit 2a fixture is untouched; one migration (platform for that file).

## 0. Founder decisions (chat 2026-11-14), not re-opened

- Strategies: **Balanced** (default, today's split), **Low carb**, **Keto**. Zone dropped. PRO.
- **Option A:** the carb and fat targets change everywhere in the app; calories and protein do NOT change.
- When the user picks a strategy and presses Save, a confirm dialog asks first (it shows the targets before and after).
- No AI is called; the user may change it as many times as they like.
- The Nutrition calorie card label shows food type and strategy, e.g. `NON-VEG · KETO` (Balanced shows nothing extra). Same label on the Diet Plan screen and its PDF.
- Workout generation never reads diet.
- App is pre-launch: no existing-user migration path is offered.

## 1. Facts this plan rests on (inventory 2026-11-14, cited on `diet-food-type` at aeb46334)

1. One calculator: `BmrCalculator.calculateTargets` (`lib/core/utils/bmr_calculator.dart:177-249`). Fat = `kcal * fatPercentage / 9` (`:234`, `fatPercentage` per goal in `lib/core/constants/fitness_goals.dart:70,79,88,97,110`: 0.25, strength 0.30). Carbs are the remainder (`:235-238`), clamped **50..800** (`:245`). Protein is clamped to `[50, 40 % of kcal / 4]` (`:230-232`). No strategy input.
2. `NutritionTargets.toMap()` writes `carb_grams` (legacy) AND `carbs_grams` AND `fat_grams` (`:317-319`). Readers read `carb_grams ?? carbs_grams`.
3. Six `calculateTargets` call sites (Edit Profile's `recalculateTargets()` at `edit_profile_screen.dart:1854` reaches `recomputeDerivedTargets`, counted below; `ensureComputedTargets` starts at `user_repository.dart:1100` and has no production caller): onboarding commit (`onboarding_provider.dart:485`, writes the fields by hand at `:558-567` and the cloud payload at `:960-970`), Edit Profile/restore recompute (`profile_target_recompute.dart:140` `recomputeDerivedTargets`, merged by `profile_provider.recalculateTargets` `:150-163` and the restore overlay `sync_profile.dart:869-877`), the latent `user_repository.ensureComputedTargets` (`:1146`), the in-memory fallbacks `nutrition_provider._resolveNutritionTargets` (`:101`) and `nutrition_repository` (`:571`, calories only), and the onboarding preview `plan_screen.dart:709` (calories + protein only).
4. The restore recompute runs only when a key in `derivedTargetInputKeys` (`profile_target_recompute.dart:12-24`) changed.
5. Cloud: `user_profile.carbs_grams` / `fat_grams` (migration 021); pushed by `sync_profile.dart:258-261`, `sync_service.dart:1453-1454`, onboarding `:967-968`. No strategy column exists.
6. Readers: `nutrition_provider` (`_resolveNutritionTargets` `:64-76`, `macroTargetsProvider`, `DailyNutritionData`), Home `NutritionSummaryNotifier` (`home_provider.dart:600-610`, reads the profile directly, own defaults 250/65), Diet Plan screen header + PDF (`diet_plan_screen.dart:431-460, 639-641`), coach snapshot `daily_targets` (`ai_snapshot_builder.dart:164-171`). Server: `weekly-report` selects `carbs_grams`/`fat_grams` and does not use them; no server reader of carb/fat targets.
7. The diet-plan generators take only calories, protein, fiber and food type (`curated_diet_plan_generator.dart:302-303`); lunch and dinner always hold one `DietRole.grain` (`:80-96`).

## 2. Landings

Unit 3 ships as two landings of one unit (as Unit 2 did), each with its own review CI and B-pass:

- **3a — targets and selector (client + one column), SHIPPED DARK.** Everything in §3, behind `DietStrategyFlags.enabled`, which is FALSE in 3a (round 3 finding 1: testers on a `main` APK must never see Keto targets beside a balanced meal plan and PDF). While it is false the chips are hidden on both screens and `effectiveMacroTargets` returns the stored values, so 3a is byte-identical for every user; tests drive it through a seam. Ship-dark tier (§4.12.4): logged in `docs/ship_dark_pending_review.yaml`; the flip happens in 3b with a full ×2 review and B-pass.
- **3b — strategy-aware diet plans and coach text.** Low-carb and keto meal templates in the curated generator (no grain role for keto; a carb term in `_sizeSlot` with a stated weight; Balanced null-gated at the call site so its plans stay byte-identical), measured over 12 archetypes x 50 seeds BEFORE building; the saved-plan strategy check; Captain manual passage and `suggestMeal` carb filter (server, own deploy go). 3b's last commit flips `DietStrategyFlags` on (and removes the 3a note line). Both landings merge before the store launch (the app is pre-launch).

This plan details 3a and states 3b's scope only.

## 3. Unit 3a

### 3.1 Vocabulary

New `lib/core/constants/diet_strategies.dart`: `enum DietStrategy { balanced, lowCarb, keto }` with `storageKey` (`balanced`, `low_carb`, `keto`), `label` (`Balanced`, `Low carb`, `Keto`), `tag` (``, `LOW CARB`, `KETO`); `const kDefaultDietStrategy = DietStrategy.balanced`; tolerant `dietStrategyOf(Object? raw)`: null, empty, unknown, non-string → `balanced` (Balanced is today's behaviour, so any unreadable value is the safe one). Profile key and cloud column: `diet_strategy`. Naming rows in `docs/naming_conventions.md`.

### 3.2 The split

One pure function owns the strategy split: `BmrCalculator.macroSplit({required double dailyCalories, required double proteinGrams, required double balancedCarbs, required DietStrategy strategy}) -> ({int carbGrams, int fatGrams})`, for `lowCarb` and `keto` only: `balanced` throws `ArgumentError` (tested; round 3 finding 3; both formulas take fat as the remainder). Carbs are additionally capped at the Balanced carbs (`min(c, balancedCarbs)`), so Low carb never gives MORE carbs than Balanced (round 4 finding 4: Balanced's own clamp floor is 50, Low carb's is 75); fat is recomputed from the capped carbs.

| strategy | carbs (g) | fat (g) |
|---|---|---|
| balanced | NOT computed by `macroSplit` for stored targets: the stored values are returned unchanged (§3.3) | — |
| low_carb | `clamp(round(0.20 * kcal / 4), 75, 150)` | `max(0, round((kcal - 4P - 4C) / 9))` |
| keto | `clamp(round(0.05 * kcal / 4), 20, 50)` | `max(0, round((kcal - 4P - 4C) / 9))` |

`calculateTargets` is NOT changed (round 2 finding 4: passing a rounded int would move Balanced by a gram at .5 boundaries; with read-time application nothing needs to call `macroSplit` for Balanced at all). For low carb and keto the energy sum is within ±4.5 kcal of the integer calories; fat is never negative (`max(0, …)`, and with protein at most 40 % and the 1,200 kcal floor `0.4k + max(300, 0.2k) < k` for consistent inputs). Low carb 20 % is inside the common "< 26 % of energy" band; keto 20–50 g is the usual net-carb range.

### 3.3 Read-time application (replaces revision 2's write door, healer and `targets_strategy`)

Round 2 found two P1s and five P2s, all in the write-time machinery (no "server-confirmed free" seam exists; a local-only `targets_strategy` cannot survive a restore; adding the strategy to `derivedTargetInputKeys` re-runs the full recompute and moves calories; a kill switch cannot undo stored keto targets; local PRO reads demote during a payment in flight). Every one of them comes from STORING strategy targets. Revision 3 stores none:

- The stored four-pack (`daily_calories`, `protein_grams`, `carb_grams`/`carbs_grams`, `fat_grams`) and every writer of it are UNCHANGED (onboarding, `recomputeDerivedTargets`, the restore overlay, `ensureComputedTargets`, `derivedTargetInputKeys`): always the Balanced split, as today. The cloud `carbs_grams`/`fat_grams` stay Balanced (no server code reads them for anything; `weekly-report` selects and ignores them).
- `diet_strategy` is a plain profile field (§3.4), never a target input.
- One pure helper turns a target four-pack into SHOWN targets: `effectiveMacroTargets(({double calories, double protein, double carbs, double fat})? base, Object? storedStrategy, {required bool pro, required bool enabled}) -> ({double calories, double protein, double carbs, double fat, DietStrategy strategy})` — DOUBLES, because the readers hold doubles and stale Hive rows can hold fractional values (`sync_profile.dart:178-185`); a non-applying call returns the very same values with no conversion (round 4 finding 3). It runs on the PRE-override pack; `_applyCalorieOverride` still applies afterwards, to calories only, exactly as today. ONE rule (round 3 finding 2): the strategy applies only when `enabled && pro`, the stored strategy is not Balanced, AND `base` is a real pack (non-null, calories > 0, protein > 0, carbs > 0; round 6 finding 2: a stale stored carb value of 0 would otherwise cap keto carbs at 0). Then calories and protein are returned exactly and carbs/fat come from `macroSplit(dailyCalories: base.calories, proteinGrams: base.protein, balancedCarbs: base.carbs, strategy: strategy)`. In EVERY other case it returns `base` unchanged with `strategy: balanced`. Callers pass:
  - `_resolveNutritionTargets` (the helper runs INSIDE it, with `pro: proStateSnapshot()` and `enabled: DietStrategyFlags.enabled` read there; both reads are pure): the stored pack when complete; the RECOMPUTED pack in its `calculateTargets` branch (`:101`); its hard-coded 2400/184/280/80 defaults are Balanced (helper not called). Its fourth caller, `WeeklyNutritionNotifier.build` (`:1676`), reads calories and protein only, which never change. The test alias `resolveNutritionTargetsForTest` (`:133`, used by two contract tests) keeps its signature; new optional parameters default to flag off.
  - Home: the stored pack only when complete; its 2000/120/250/65 defaults are Balanced, helper not called.
  - The snapshot: keeps its own raw reads and its `0` defaults (`ai_snapshot_builder.dart:164-171`); it calls the helper only when the stored pack is complete and `enabled && pro` (round 4 finding 1). The new `diet_strategy` / `diet_strategy_label` keys are emitted ONLY when `DietStrategyFlags.enabled`.
  The label (§3.7), the snapshot `diet_strategy`, the chips' selected state and the dialog's OLD side (§3.6) and the PDF header use the helper's RETURNED strategy, carried in the SAME object as the numbers, never a separately read value (round 6 finding 1), so a "KETO" label always sits over keto numbers:
  - `_resolveNutritionTargets`'s map gains `'strategy_index'` (`DietStrategy.index` as a double; absent = Balanced) next to calories/protein/carbs/fat; `MacroTargetsNotifier`'s map passes it through; `DailyNutritionData` gains a `DietStrategy strategy` field (default Balanced).
  - The calorie card's `FoodTypeTag` reads `DailyNutritionData.strategy`; the Diet Plan header, the PDF header, the chips and the dialog's old side read `macroTargetsProvider`'s `'strategy_index'`. A screen never calls the helper or reads `diet_strategy` itself for display.
  - The snapshot uses the strategy its own helper call returned.
  With the flag off the key is absent and the field is Balanced, so every existing reader of the map is unchanged (round 7: no consumer iterates, spreads, serialises or compares the map; `_applyCalorieOverride` spreads it, so the key survives). The read is `DietStrategy.values[(map['strategy_index'] ?? 0).toInt()]`, through one helper.
- The three readers of carb/fat targets call it, and nothing else reads them raw:
  1. `nutrition_provider.dart` `_resolveNutritionTargets` (`:64-76`): the single source of `macroTargetsProvider`, `DailyNutritionData` (the calorie-card bars, `nutrition_screen.dart:441`), the Diet Plan header/PDF (`diet_plan_screen.dart:165,431-460,639-641`) and `profile_content.dart:56`. Its compute-fallback branch (`:101`) applies the helper to the fallback values too.
  2. Home `NutritionSummaryNotifier` (`home_provider.dart:600-610`).
  3. The coach snapshot `daily_targets` (`ai_snapshot_builder.dart:164-171`), plus `diet_strategy` and `diet_strategy_label` (the EFFECTIVE strategy).
- PRO read: `SubscriptionService.instance.proStateSnapshot()` (pure). ONLY WHEN `DietStrategyFlags.enabled` (round 5 finding 1: a flag-off user keeps the exact old dependency set; a conditional `ref.watch` is legal in Riverpod), the THREE providers (`DailyNutritionNotifier`, `MacroTargetsNotifier`, Home `NutritionSummaryNotifier`) `ref.watch(subscriptionInfoProvider.select((s) => s.isPro))` (new import of `profile_provider.dart` in `nutrition_provider.dart`) and `ref.watch(restoreCompletedTickProvider)` (`home_provider.dart:~253`; a plain import, `home_provider.dart` does not import `nutrition_provider.dart`), so a PRO change or a restore that brings a different `diet_strategy` re-renders. Accepted windows (stated, nothing is written in either): an `expires_at` that passes mid-session fires no event, so screens show the strategy until the next invalidation while the coach snapshot (read live) already shows Balanced; an uncertain PRO state shows Balanced until known.
- Flag: `DietStrategyFlags` (`lib/features/nutrition/services/diet_strategy_flags.dart`, after `DietPlanFlags`): `enabled = debugEnabledOverride ?? (kDietStrategyDefaultOn && configBox['disable_diet_strategy'] != true)`, where `@visibleForTesting static bool? debugEnabledOverride` is THE test seam for every flag-on test (providers, widgets, snapshot; reset in `tearDown`; round 6 finding 4); `kDietStrategyDefaultOn = false` in 3a; the read is wrapped in try/catch with the default (unit tests have no Hive), like `DietPlanFlags`; the configBox key is cleared by `clearAllData()` at sign-out like `disable_curated_diet_plan` (so a kill switch set on a device lasts until sign-out; the fleet-wide off is a build with the constant false); a naming row.
- Consequences, each by construction: a lapse shows Balanced targets immediately and a renewal brings the strategy back (the stored choice is kept); the kill switch reverts every screen at once; a restore needs nothing (the field restores like any profile key); Edit Profile's full recompute never interacts with the strategy; no calorie or protein value ever changes because of the strategy.
- A pin test (source scan of `lib/`) asserts that `carb_grams`, `carbs_grams` and `fat_grams` are read from the profile map only inside `_resolveNutritionTargets`, `NutritionSummaryNotifier`, `ai_snapshot_builder` and the existing writers/sync/restore files (allow-list by file), so a new raw reader fails CI.
- Accepted limit: an uncertain PRO state (a fresh-install restore before the first refresh, offline with a passed local `expires_at`) SHOWS Balanced targets until the state is known. Nothing is written, so it heals the moment the state is known.
- Stated limit (B-pass seat A finding 1): Home and the snapshot apply the strategy only to a COMPLETE stored four-pack, while `_resolveNutritionTargets` also applies it to its recompute fallback. A profile with recompute inputs but no stored pack (not seen after onboarding, which writes all four keys) already disagrees on `main` between Home's 250/65 defaults, the snapshot's zeros and Nutrition's recompute. The strategy keeps that split; it does not add one.

### 3.4 Write door

`UserProfileNotifier.setDietStrategy(DietStrategy next)` → `Future<bool>`, same shape as `setFoodType` after the Unit 2a B-pass: serialised chain, account check, no-op when unchanged; ONE write: `updateProfile({'diet_strategy': key})` (Hive first; `ProfileWriteService.patchProfile` already fires `syncProfileNow`, `lib/features/profile/services/profile_write_service.dart:122-127`), then `pushSnapshot` (not awaited). No target is written. Invalidates `macroTargetsProvider`, `dailyNutritionProvider`, Home `nutritionSummaryProvider`, `dietPlanProvider`. Edit Profile gates a non-Balanced chip tap with `gateAndVerify` (as on the Diet Plan screen), seeds its strategy form value from the EFFECTIVE strategy and adds `diet_strategy` to its `updates` map ONLY when `DietStrategyFlags.enabled` AND the user tapped a chip different from that effective value AND (for a non-Balanced value) `proStateSnapshot()` is still true at Save (round 6 finding 3: PRO can lapse between tap and Save) (round 5 finding 3: comparing a Balanced-seeded form with a stored, paused `keto` would erase the paused choice on any unrelated save); its existing `recalculateTargets()` is unaffected. On the Diet Plan screen a tap on the already-selected (effective) chip does nothing. With the flag off nothing writes `diet_strategy`, so neither Hive nor the cloud push changes.

### 3.5 PRO

- Selecting a non-Balanced strategy goes through `subscription.gateAndVerify(AppConstants.featureDietStrategy, …)` (new constant `diet_strategy` beside `app_constants.dart:47-68`; the list entry goes in `allProFeatures` at `subscription_service.dart:94`); a free user sees `PaywallSheet` via `showPaywallSheet(feature: 'Diet Strategy')` — a DISPLAY string, with its own subtitle case in `paywall_sheet.dart`'s switch (`Low carb and keto targets, set for your goal.`) and a row in `paywall_feature_label_test.dart` (round 3 finding 5). Balanced is always selectable. **Local PRO check only:** `diet_strategy` is NOT added to `_highValueFeatures` (`subscription_service.dart:646-650`); rule 19's list is unchanged. A free user may hold a stored non-Balanced choice (set while PRO): the chip shown as selected is the EFFECTIVE strategy (Balanced), with a one-line hint `Keto is paused. It comes back with PRO.` (round 4 finding 5).
- No healer, no `targets_strategy`, no subscription hook.

### 3.6 Selector and confirm dialog

- **Diet Plan screen:** a `DietStrategyChips` row under the existing `FoodTypeChips` (PRO badge on Low carb / Keto for free users). A tap on a different strategy opens the confirm dialog, whose numbers come from `effectiveMacroTargets` on the current profile: the OLD side with the current PRO state, the NEW side with `pro: true` (the gate has just passed, so a user mid-verification still sees the real change; round 4 finding 5): title `Switch to Keto?`, body: `Your daily targets change:` then two rows `Carbs 250 g → 30 g`, `Fat 65 g → 168 g`, and `Calories and protein stay the same.`; buttons `Cancel` / `Switch`. Switch → `setDietStrategy`, then a snackbar `Targets updated for Keto`. False → `Couldn't change the diet strategy. Try again.` When the old and new EFFECTIVE targets are equal as the ROUNDED integers shown (round 5 finding 5), there is no dialog: the field is written and the snackbar reads `Your targets are already low in carbs.` (a low-calorie, heavy-protein user whose Balanced carbs already sit at or below the Low carb value; Low carb then equals Balanced for them, stated). Same in Edit Profile. The plan is not regenerated (its foods do not depend on the strategy in 3a).
- **Edit Profile:** the same chips in the diet section; Save shows the same dialog only when the strategy changed. Edit Profile's save already runs the full `recalculateTargets()` (its inputs may have changed), so its dialog previews all four from `effectiveMacroTargets` over a pure `recomputeDerivedTargets` of the edited form (the same full recompute `_save` runs); when calories or protein move it says `Calories and protein also change because you edited other fields.` instead of "stay the same". Cancel returns to the form unsaved. (`edit_profile_screen.dart` is on the god-screen allow-list; the chips and dialog are shared widgets anyway.)
- Wardroom copy: reviewed against `lib/shared/widgets/wardroom/CLAUDE.md` (plain words; no hype).
- Screen ceiling: `diet_plan_screen.dart` is at 763 lines (ceiling 800, not allow-listed). The chips, the dialog and the tap handler live outside it (`lib/shared/widgets/diet_strategy_chips.dart`, `lib/features/nutrition/widgets/diet_strategy_confirm_dialog.dart`, `lib/features/nutrition/services/diet_strategy_actions.dart`); the screen's net growth is budgeted at ≤ 25 lines. The `setFoodType` docstring sentence "Unit 3's strategy will [feed BMR/TDEE], and is added here then" is corrected in the same commit (the strategy never feeds BMR/TDEE).

### 3.7 Label

`FoodTypeTag` (a `StatelessWidget` over the profile map, `food_type_tag.dart:12-20`; its calorie-card call site is `nutrition_screen.dart:417`, where `nutrition` is in scope, so it is passed `nutrition.strategy`) gains a `strategy` parameter, passed the strategy carried with the numbers (§3.3; rounds 5 and 6): `NON-VEG · KETO`; Balanced (and the flag off) adds nothing. Calorie card, Diet Plan header, PDF header (`| Food type: Non-veg | Strategy: Keto`).

### 3.8 Diet plan in 3a

No generator change in 3a (round 1 finding 6; moved to 3b). The Diet Plan header shows the new targets; for Low carb / Keto one line under it reads `Meals for Keto come in the next update. This plan uses balanced meals.` (removed by 3b). The saved plan gains a top-level `diet_strategy` stamp (written by `_savePlan` ONLY when `DietStrategyFlags.enabled`, round 4 finding 2; no reader in 3a) so 3b can judge a saved plan against the strategy the way `savedPlanMatchesFoodType` judges the food type (round 1 finding 5). Hints from a saved plan stay valid in 3a because its foods do not change.

### 3.9 Coach

The snapshot adds `diet_strategy` + `diet_strategy_label` (the helper's returned strategy) next to `diet_preference` (`ai_snapshot_builder.dart`); `daily_targets` carries the effective carbs/fat (§3.3). The strategy is chosen only through the selector, never by the coach extraction (a chat "I'm keto" still folds to Non-veg in `foodTypeOf`); one sentence in the nutrition CLAUDE.md row says so (round 3 finding 9). No server change in 3a; the coach reads the snapshot. (The Captain manual passage is 3b.)

### 3.10 Cloud column (migration, founder go)

`user_profile.diet_strategy text NULL CHECK (diet_strategy IN ('balanced','low_carb','keto'))`. Number from `sh scripts/mint_migration.sh diet-strategy`. Pushed by `sync_profile.dart` (the fixed list of conditional keys at `:200-262`: a new conditional entry, like `diet_preference`, that ALSO requires `DietStrategyFlags.enabled`, round 5 finding 2); NOT added to the onboarding replay in `sync_service.dart` (always Balanced). Restored by `_restoreUserProfile` (merges every non-null cloud key; `restore-user-snapshot` selects `*`). `user_profile` has row-level policies only (`100_rls_initplan_select_wrap.sql:141-144`), so no policy change. `backups/live_schema_columns.json` gains `diet_strategy` in the same commit; `backups/applied_migrations.json` when applied. Apply BEFORE 3a merges (PostgREST rejects an unknown column and the whole profile upsert would fail). With the flag off nothing writes the field (§3.4), so strictly it must be live before 3b's flip; applying it before 3a's merge keeps one simple order and is additive. Rollback: revert the client, then `ALTER TABLE user_profile DROP COLUMN diet_strategy`.

### 3.11 SoT and docs

New SoT concept `diet_strategy_targets`: writer `setDietStrategy` + Edit Profile `_save` (the field only); readers `effectiveMacroTargets` via the three readers; behavioural path = the new writer-to-reader test. Nested CLAUDE.md: nutrition, profile, ai_coach. Naming rows (`diet_strategy`, `DietStrategy`, `macroSplit`, `effectiveMacroTargets`). `check_hive_map_field_drift.dart` (`:356` lists the macro keys): add `diet_strategy` if the list requires every profile key.

### 3.12 Kill switch (§4.6)

`DietStrategyFlags.enabled == false` (3a's default, or `configBox['disable_diet_strategy'] = true` after 3b's flip) → the helper returns the base values with Balanced and the chips hide on BOTH screens (Diet Plan and Edit Profile). Because nothing strategy-specific is stored, every screen reverts at once (round 2 finding 5 closes by construction).

## 4. Tests (3a)

1. `macroSplit`: low carb / keto carbs within bounds and never above the Balanced carbs (a heavy-protein, low-calorie row where Balanced sits at 60 g), fat ≥ 0 (incl. protein at its 40 % cap at 1,200 kcal and an inconsistent stored pair), energy within ±4.5 kcal. `calculateTargets` untouched (existing tests).
2. `effectiveMacroTargets` truth table: {PRO, free} × {balanced, low_carb, keto, missing, garbage} × {enabled, disabled} × {real pair, null base, zero calories}; every non-applying row returns the base EXACTLY with `strategy: balanced` (incl. a legacy profile holding only `carb_grams`); "keto stored, pack incomplete" shows defaults with Balanced; calories and protein never change. `macroSplit(balanced)` throws.
2b. Ship-dark identity (flag at its 3a default, false), for a profile holding `diet_strategy: keto` AND for one without it, incl. a fractional stored pack and an incomplete pack: `macroTargetsProvider`, `DailyNutritionData`, Home summary and the coach snapshot JSON (no new keys) equal the pre-3a output; an Edit Profile save leaves the profile map and the `_syncUserProfile` payload identical (the push entry is flag-gated, so even a profile holding the field sends no new key); the three providers' dependency sets are unchanged (no new watches); `_savePlan`'s JSON has no `diet_strategy`; chips absent on both screens.
3. Writer-to-reader: `setDietStrategy(keto)` on real Hive → profile `diet_strategy` → `macroTargetsProvider`, `DailyNutritionData`, Home summary and snapshot `daily_targets` + `diet_strategy` all show keto carbs/fat; the stored four-pack is byte-identical before and after; account change returns false; unchanged = no write.
4. Lapse and renewal: PRO keto → state flips to free (provider) → every reader shows Balanced, stored `diet_strategy` still keto → PRO again → keto back. Kill switch ON → Balanced everywhere.
5. Restore: a cloud row with `diet_strategy: keto` restores the field; with PRO the readers show keto, with free Balanced; `derivedTargetInputKeys` unchanged (pin).
6. Raw-reader pin (§3.3) with a positive control.
7. Widgets (flag forced on through the seam): chips (free → paywall with `Diet Strategy`; PRO → dialog), dialog numbers equal the helper before/after, Cancel writes nothing, equal-effective → no dialog/snackbar, Edit Profile dialog only on a strategy change, the 3a note line for Low carb / Keto; provider rebuild on a PRO flip and on a restore tick.
8. Workout isolation: extend `food_type_no_workout_reader_test.dart` with `diet_strategy`.
9b. Carrier: the label and the numbers come from ONE provider read (calorie card from `DailyNutritionData`, Diet Plan header/PDF/chips from `macroTargetsProvider`); a mutation that makes `FoodTypeTag` read `diet_strategy` from the profile goes red.
9. Paused strategy kept: a lapsed user with stored `keto` makes an unrelated Edit Profile save, and a tap on the selected Balanced chip on the Diet Plan screen — stored `keto` survives both; renewal brings keto back. A user whose Balanced carbs are below the Low carb value gets no dialog and the "already low" snackbar.
Every new guard mutated once (§4.4 r21).

## 6. Round 1 dispositions (context-blind Sonnet, verified at aeb46334)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | `recalculateTargets` on a strategy switch or a lapse can silently move calories/protein (targets lag inputs) | `macroSplit` pure function; the switch and the healer rewrite only carbs/fat from stored calories/protein; the dialog previews with the same call (§3.2, §3.4, §3.5, §3.6) |
| 2 | P2 | healer hook point and uncertain PRO state | boot after `evaluateEntitlementAtBoot` (promotion only), after a successful refresh (both), `ref.listen` (promotion only); demotion only on a server-confirmed free state, not while verifying, same owner (§3.5) |
| 3 | P2 | pure functions cannot read `subscriptionInfoProvider` | callers resolve with `proStateSnapshot()` and pass a `DietStrategy` (§3.3) |
| 4 | P2 | "the gate server-verifies" is false | stated as a local check; not added to `_highValueFeatures` (§3.5) |
| 5 | P2 | saved plan after a strategy switch | 3a: foods unchanged so hints stay valid; `diet_strategy` stamped for 3b's check (§3.8) |
| 6 | P2 | §3.8 carb penalty cannot reach targets | generator work moved to 3b with a measured design; 3a shows one line (§2, §3.8) |
| 7 | P3 | seven call sites; the "4C <= 0.2 kcal" sentence; onboarding replay; extraction never writes the strategy; naming/schema rows | all applied (§1, §3.2, §3.3, §3.10) |

Q1: write-time rule, one door (kept). Q2: Edit Profile's dialog previews all four when other fields moved them. Q3: nothing breaks below 50 g (only Balanced clamps at 50).

## 7. Round 2 dispositions (context-blind Sonnet on revision 2, verified at aeb46334)

All seven findings came from storing strategy-specific targets. Revision 3 removes that mechanism (application at read time, §3.3) instead of patching each symptom.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | no "server-confirmed free" seam; `refreshFromSupabase` returns void | no demotion exists any more; the readers follow the current PRO state (§3.3, §3.5) |
| 2 | P1 | local-only `targets_strategy` breaks the lapse rule after a restore | `targets_strategy` removed; nothing strategy-specific is stored |
| 3 | P2 | `diet_strategy` in `derivedTargetInputKeys` re-runs the full recompute on restore | not added; pin test asserts the list is unchanged |
| 4 | P2 | `macroSplit(int)` would move Balanced by 1 g; no `max(0, …)` | Balanced never goes through `macroSplit` (stored values returned); `double` calories; `max(0, …)` on fat |
| 5 | P2 | kill switch cannot undo stored keto targets | nothing to undo: the switch changes what readers show |
| 6 | P2 | full-recompute doors demote on a local PRO read | they no longer take a strategy |
| 7 | P2 | healer hooks run before the restore; `ref.listen` vs `listenManual` | no hooks |
| 8 | P3 | reader inventory, double `syncProfileNow`, label source, drift list | readers listed in §3.3; `patchProfile` already syncs (§3.4); the label shows the effective strategy (§3.7); drift list in §3.11 |

Accepted limit (stated in §3.3): an uncertain PRO state shows Balanced until known; nothing is written.

## 8. Round 3 dispositions (context-blind Sonnet on revision 3, verified at aeb46334)

No P0/P1. The reader inventory (§3.3) was confirmed complete across `lib/`, `supabase/functions/` and `supabase/migrations/`; rounds 1 and 2 confirmed closed.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | 3a would show keto targets beside a balanced plan and PDF to testers | 3a ships dark (`DietStrategyFlags`, default false; ship-dark tier, logged); 3b flips it (§2, §3.3) |
| 2 | P2 | helper contradicts itself on an incomplete pack | one rule: applies only to a real calorie/protein pair; defaults are Balanced; label/snapshot/dialog use the returned strategy (§3.3) |
| 3 | P3 | dead `fatPercentage`; undefined Balanced in `macroSplit` | parameter dropped; Balanced throws (§3.2) |
| 4 | P3 | provider rebuild details | three providers, `select(isPro)`, restore tick, import named, windows stated (§3.3) |
| 5 | P3 | paywall display string, subtitle, label test, `allProFeatures` | specified (§3.5) |
| 6 | P3 | lapsed user picking Balanced gets a no-change dialog | equal effective targets → no dialog, no snackbar (§3.6) |
| 7 | P3 | screen headroom; stale docstring | handler file, ≤ 25 lines budget, docstring fixed (§3.6) |
| 8 | P3 | kill-switch hygiene | `DietStrategyFlags`, `clearAllData`, naming row, both screens (§3.3, §3.12) |
| 9 | P3 | coach-extracted keto | stated in the nutrition CLAUDE.md row (§3.9) |

## 9. Round 4 dispositions (context-blind Sonnet on revision 4)

No P0/P1. All three P2s were places where the dark 3a would still change something for a flag-off user; each is now gated and in the identity test (§4 test 2b).

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | coach snapshot gains keys and would copy the provider's fallbacks | snapshot keeps its raw reads and 0 defaults; helper only on a complete pack with the flag on and PRO; new keys only with the flag (§3.3) |
| 2 | P2 | Edit Profile `_save` and `_savePlan` write the strategy with the flag off | written only with the flag on and (Edit Profile) only on a real change (§3.4, §3.8) |
| 3 | P2 | int record moves fractional stored values | doubles throughout; a non-applying call returns the same values; runs before `_applyCalorieOverride` (§3.3) |
| 4 | P3 | Low carb can exceed Balanced carbs | capped at the Balanced carbs (§3.2) |
| 5 | P3 | chip selection and dialog for lapsed / in-flight users; `allProFeatures` location | effective chip + "paused" hint; NEW side with `pro: true`; `subscription_service.dart:94` (§3.5, §3.6) |
| 6 | P3 | citations; tick provider import; flag reader try/catch; `clearAllData` | applied (§1, §3.3) |

## 10. Round 5 dispositions (context-blind Sonnet on revision 5)

No P0/P1; three narrow P2s, no redesign.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | new `ref.watch` calls change flag-off rebuild triggers | both watches only when the flag is on; identity test checks dependency sets (§3.3, §4 2b) |
| 2 | P2 | the conditional push entry sends a held field with the flag off | push entry also requires the flag (§3.10, §4 2b) |
| 3 | P2 | a Balanced-seeded form compared with stored `keto` erases a paused choice | seed and compare against the EFFECTIVE value; write only on a tapped different chip; selected-chip tap is a no-op; test 9 (§3.4) |
| 4 | P3 | `macroSplit` call missing `balancedCarbs` | written out with named parameters (§3.3) |
| 5 | P3 | Low carb can equal Balanced; dialog on rounding noise | compare rounded integers; "already low in carbs" copy; stated (§3.6) |
| 6 | P3 | helper placement, Weekly caller, test alias | helper runs inside `_resolveNutritionTargets`; Weekly unchanged; alias signature kept (§3.3) |
| 7 | P3 | no import cycle; `FoodTypeTag` input; citations | applied (§3.3, §3.7, §3.4) |

## 11. Round 6 dispositions (context-blind Sonnet on revision 6)

No P0/P1; one P2 spec gap; the reader list and all round 5 dispositions confirmed.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | the helper's returned strategy had no path to the label, chips, dialog and PDF | carried in the same objects as the numbers: `'strategy_index'` in the targets map, `DailyNutritionData.strategy`; screens never re-derive it; test 9b (§3.3, §3.7) |
| 2 | P3 | a stale stored carbs of 0 caps keto at 0 | the helper applies only to a pack with carbs > 0 (§3.3) |
| 3 | P3 | Edit Profile: PRO can lapse between tap and Save | gate at tap, re-check `proStateSnapshot()` at Save (§3.4) |
| 4 | P3 | flag test seam not named | `DietStrategyFlags.debugEnabledOverride` (§3.3) |

## 12. Round 7 (context-blind Sonnet on revision 7): converged

No P0, P1 or P2. Two P3 notes applied: the `strategy_index` read default and the `FoodTypeTag` call site (§3.3, §3.7). The reviewer confirmed every consumer of the targets map and of `DailyNutritionData` tolerates the new key/field, the flag-off path is unchanged, and the round 6 dispositions close.
